--!strict
-- Slot.lua
-- Pure data. One Slot = one position in a Formation. Slots are pooled and
-- reused by FormationComponent (see its free-list) so a minion joining or
-- leaving an army never allocates a new table once the formation has
-- reached its high-water mark of concurrently-occupied slots.
--
-- Movement bookkeeping (_movement / _lastDirection / _moving) lives here
-- rather than back on the minion, because FormationSystem iterates SLOTS
-- (flat, cache-friendly array), not minions scattered across armies. This
-- mirrors the FollowComponent/FollowSystem split already in the codebase:
-- Slot = state, FormationSystem = work.

export type Slot = {
	SlotId: number,
	Offset: Vector3,            -- local-space offset from the formation anchor
	JitterOffset: Vector3,      -- tiny deterministic per-slot idle offset (no per-frame random)
	WorldPosition: Vector3,     -- current interpolated world position (what minions walk toward)
	AssignedMinion: any?,       -- MinionEntity occupying this slot, or nil
	Occupied: boolean,

	-- Bookkeeping owned by FormationComponent/FormationSystem, not by the
	-- minion's own components. Reset on every Reset() call.
	_occupiedIndex: number?,    -- this slot's index inside FormationSystem's flat record array (O(1) unregister)
	_movement: any?,            -- cached MovementComponent reference for AssignedMinion
	_lastDirection: Vector3?,
	_moving: boolean,
}

local Slot = {}
Slot.__index = Slot

local function new(slotId: number): Slot
	return setmetatable({
		SlotId = slotId,
		Offset = Vector3.zero,
		JitterOffset = Vector3.zero,
		WorldPosition = Vector3.zero,
		AssignedMinion = nil,
		Occupied = false,

		_occupiedIndex = nil,
		_movement = nil,
		_lastDirection = nil,
		_moving = false,
	}, Slot) :: any
end

-- Reset+reuse instead of allocating a new table. Called whenever a slot is
-- pulled out of the free-list to be handed to a newly-joining minion.
-- Offset/JitterOffset are recomputed by the caller (FormationGenerator),
-- everything else is wiped.
function Slot.Reset(slot: Slot, offset: Vector3, jitterOffset: Vector3, worldPosition: Vector3)
	slot.Offset = offset
	slot.JitterOffset = jitterOffset
	slot.WorldPosition = worldPosition
	slot.AssignedMinion = nil
	slot.Occupied = false
	slot._occupiedIndex = nil
	slot._movement = nil
	slot._lastDirection = nil
	slot._moving = false
end

return {
	new = new,
	Reset = Slot.Reset,
}