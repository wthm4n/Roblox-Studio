--!strict
-- FormationComponent.lua
-- Owns one Army's slots. Minions never compute their own position; they
-- are assigned a Slot once and FormationSystem walks them toward
-- slot.WorldPosition every tick. This module only does the bookkeeping:
-- allocate/free slots, recompute offsets on shape change, and the cheap
-- per-frame interpolation pass. It does NOT call MoveTo/SetDirection --
-- that's FormationSystem's job (registry of work), this is state.
--
-- Slot pooling: _slots is a dense array, indexed 1.._slotCapacity, that
-- only ever GROWS (new Slot tables are appended, never removed) -- it is
-- the formation's all-time high-water mark of concurrently-used slots.
-- _freeStack is a stack of currently-unused slots pulled from that array.
-- Joining pops a free slot (or appends a brand-new one if the stack is
-- empty); leaving pushes the slot back. Steady-state armies (the common
-- case: minions die and get replaced) do ZERO table allocation after the
-- army's first trip to its peak size.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormationGenerator = require(ReplicatedStorage.Framework.FormationGenerator)
local Slot = require(ReplicatedStorage.Framework.Slot)

export type FormationConfig = {
	Shape: FormationGenerator.ShapeName?,
	Spacing: number?,
	SmoothRate: number?, -- higher = snappier, lower = floatier. 1/seconds.
}

export type FormationComponent = {
	Shape: FormationGenerator.ShapeName,
	Spacing: number,
	SmoothRate: number,
	AnchorCFrame: CFrame,

	AddMinion: (self: FormationComponent, minion: any) -> Slot.Slot,
	RemoveMinion: (self: FormationComponent, minion: any) -> (),
	GetSlot: (self: FormationComponent, minion: any) -> Slot.Slot?,
	SetShape: (self: FormationComponent, shape: FormationGenerator.ShapeName) -> (),
	SetSpacing: (self: FormationComponent, spacing: number) -> (),
	SetAnchor: (self: FormationComponent, cframe: CFrame) -> (),
	InterpolateSlots: (self: FormationComponent, dt: number) -> (),
	OccupiedCount: (self: FormationComponent) -> number,
	Destroy: (self: FormationComponent) -> (),

	_slots: { Slot.Slot },          -- dense, index = SlotId, only ever grows
	_freeStack: { Slot.Slot },      -- pooled, currently-unused slots
	_occupied: { Slot.Slot },       -- flat array of currently-occupied slots (cache-friendly iteration)
	_minionToSlot: { [any]: Slot.Slot },
}

local FormationComponent = {}
FormationComponent.__index = FormationComponent

-- O(1): pop a free slot or append a new one. Recomputes that single
-- slot's offset for the current shape -- never touches any other slot.
local function acquireSlot(self: FormationComponent): Slot.Slot
	local slot = table.remove(self._freeStack)
	if slot then
		local offset, jitter = FormationGenerator.GetOffset(self.Shape, slot.SlotId, self.Spacing)
		Slot.Reset(slot, offset, jitter, self.AnchorCFrame:PointToWorldSpace(offset))
		return slot
	end

	local slotId = #self._slots + 1
	local newSlot = Slot.new(slotId)
	local offset, jitter = FormationGenerator.GetOffset(self.Shape, slotId, self.Spacing)
	Slot.Reset(newSlot, offset, jitter, self.AnchorCFrame:PointToWorldSpace(offset))
	self._slots[slotId] = newSlot
	return newSlot
end

-- O(1): minion already has a cached MovementComponent reference; this is
-- just dictionary lookup + array swap-remove, no scanning.
function FormationComponent:AddMinion(minion: any): Slot.Slot
	local existing = self._minionToSlot[minion]
	if existing then
		return existing
	end

	local slot = acquireSlot(self)
	slot.Occupied = true
	slot.AssignedMinion = minion
	slot._movement = minion.GetComponent and minion:GetComponent("Movement") or nil

	table.insert(self._occupied, slot)
	slot._occupiedIndex = #self._occupied
	self._minionToSlot[minion] = slot

	return slot
end

function FormationComponent:RemoveMinion(minion: any)
	local slot = self._minionToSlot[minion]
	if not slot then
		return
	end
	self._minionToSlot[minion] = nil

	-- O(1) swap-remove from the occupied array using the slot's cached index
	local occupied = self._occupied
	local idx = slot._occupiedIndex
	local lastIdx = #occupied
	if idx and idx ~= lastIdx then
		local lastSlot = occupied[lastIdx]
		occupied[idx] = lastSlot
		lastSlot._occupiedIndex = idx
	end
	occupied[lastIdx] = nil

	slot.Occupied = false
	slot.AssignedMinion = nil
	slot._movement = nil
	slot._lastDirection = nil
	slot._moving = false
	slot._occupiedIndex = nil

	table.insert(self._freeStack, slot)
end

function FormationComponent:GetSlot(minion: any): Slot.Slot?
	return self._minionToSlot[minion]
end

-- O(n) in THIS army's occupied minions only (spec-allowed "Formation
-- rebuild O(n)"). Reuses every existing slot table -- only Offset/Jitter
-- are recomputed, no slot is freed or reallocated, so a shape change
-- mid-fight doesn't cause a pool churn.
function FormationComponent:SetShape(shape: FormationGenerator.ShapeName)
	if shape == self.Shape then
		return
	end
	self.Shape = shape
	for _, slot in ipairs(self._occupied) do
		local offset, jitter = FormationGenerator.GetOffset(shape, slot.SlotId, self.Spacing)
		slot.Offset = offset
		slot.JitterOffset = jitter
	end
end

function FormationComponent:SetSpacing(spacing: number)
	if spacing == self.Spacing then
		return
	end
	self.Spacing = spacing
	for _, slot in ipairs(self._occupied) do
		local offset, jitter = FormationGenerator.GetOffset(self.Shape, slot.SlotId, spacing)
		slot.Offset = offset
		slot.JitterOffset = jitter
	end
end

function FormationComponent:SetAnchor(cframe: CFrame)
	self.AnchorCFrame = cframe
end

-- Called every frame for every formation (cheap: pure vector math, no
-- Move()/MoveTo calls here -- that's FormationSystem's bucketed pass).
-- Frame-rate independent exponential smoothing so slots glide rather than
-- snap when the anchor moves or the shape changes.
function FormationComponent:InterpolateSlots(dt: number)
	local alpha = 1 - math.exp(-self.SmoothRate * dt)
	local anchor = self.AnchorCFrame
	for _, slot in ipairs(self._occupied) do
		local target = anchor:PointToWorldSpace(slot.Offset + slot.JitterOffset)
		slot.WorldPosition = slot.WorldPosition:Lerp(target, alpha)
	end
end

function FormationComponent:OccupiedCount(): number
	return #self._occupied
end

function FormationComponent:Destroy()
	table.clear(self._slots)
	table.clear(self._freeStack)
	table.clear(self._occupied)
	table.clear(self._minionToSlot)
end

local function new(config: FormationConfig?): FormationComponent
	config = config or {}
	local self = setmetatable({
		Shape = config.Shape or "Circle",
		Spacing = config.Spacing or 5,
		SmoothRate = config.SmoothRate or 6,
		AnchorCFrame = CFrame.new(),

		_slots = {},
		_freeStack = {},
		_occupied = {},
		_minionToSlot = {},
	}, FormationComponent)

	return (self :: any) :: FormationComponent
end

return {
	new = new,
}
