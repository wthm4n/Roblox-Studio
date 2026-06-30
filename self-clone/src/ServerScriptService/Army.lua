--!strict
-- Army.lua
-- Represents ONE player's army. Owns minions, a Formation, and ownership
-- bookkeeping ONLY -- no gameplay logic lives here. Mining, combat,
-- tasks, etc. are all future systems that will read from / queue work
-- onto an Army; this module just has to guarantee O(1) membership
-- operations and never let unrelated code touch minions except through
-- this API.
--
-- Membership storage: a dense array (Minions) for O(n) ForEach/iteration,
-- PLUS two side-tables for O(1) random access:
--   _indexByMinion : minion -> its index in Minions (for O(1) swap-remove)
--   _byId          : entity.Id -> minion (for O(1) GetMinion(id))
-- This is the same swap-remove-with-index-map pattern MinionService
-- already uses for its owner sets, applied one level up.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormationComponent = require(ReplicatedStorage.Components.FormationComponent)
local FormationSystem = require(ReplicatedStorage.Framework.FormationSystem)

export type ArmySettings = {
	[string]: any,
}

export type Army = {
	ArmyId: number,
	Owner: Player,
	Minions: { any },
	Formation: FormationComponent.FormationComponent,
	CurrentTask: any?,
	Selection: { [any]: true },
	Settings: ArmySettings,

	AddMinion: (self: Army, minion: any) -> (),
	RemoveMinion: (self: Army, minion: any) -> (),
	GetMinion: (self: Army, id: number) -> any?,
	Count: (self: Army) -> number,
	ForEach: (self: Army, callback: (minion: any) -> ()) -> (),
	GetNearest: (self: Army, position: Vector3) -> any?,
	Clear: (self: Army) -> (),
	Select: (self: Army, minion: any) -> (),
	Deselect: (self: Army, minion: any) -> (),
	ClearSelection: (self: Army) -> (),
	SetAnchor: (self: Army, cframe: CFrame) -> (),
	Destroy: (self: Army) -> (),

	_indexByMinion: { [any]: number },
	_byId: { [number]: any },
	_destroyingConns: { [any]: RBXScriptConnection },
}

local Army = {}
Army.__index = Army

-- O(1): append + two side-table writes + one Slot allocation (itself
-- O(1) amortized, see FormationComponent). No scan of existing minions.
function Army:AddMinion(minion: any)
	if self._indexByMinion[minion] then
		return
	end

	table.insert(self.Minions, minion)
	self._indexByMinion[minion] = #self.Minions
	self._byId[minion.Id] = minion

	self.Formation:AddMinion(minion)

	-- Army owns lifecycle bookkeeping: if the minion is destroyed by
	-- anything else (combat, despawn, whatever future system), the Army
	-- and its Formation slot free themselves automatically -- callers
	-- never have to remember to call RemoveMinion themselves.
	self._destroyingConns[minion] = minion.Destroying:Once(function()
		self:RemoveMinion(minion)
	end)
end

-- O(1): swap-remove from the dense array using the cached index, plus
-- O(1) side-table cleanup and O(1) slot release.
function Army:RemoveMinion(minion: any)
	local idx = self._indexByMinion[minion]
	if not idx then
		return
	end

	local minions = self.Minions
	local lastIdx = #minions
	if idx ~= lastIdx then
		local lastMinion = minions[lastIdx]
		minions[idx] = lastMinion
		self._indexByMinion[lastMinion] = idx
	end
	minions[lastIdx] = nil

	self._indexByMinion[minion] = nil
	self._byId[minion.Id] = nil
	self.Selection[minion] = nil

	local conn = self._destroyingConns[minion]
	if conn then
		conn:Disconnect()
		self._destroyingConns[minion] = nil
	end

	self.Formation:RemoveMinion(minion)
end

function Army:GetMinion(id: number): any?
	return self._byId[id]
end

function Army:Count(): number
	return #self.Minions
end

function Army:ForEach(callback: (minion: any) -> ())
	for _, minion in ipairs(self.Minions) do
		callback(minion)
	end
end

-- O(n) over this army's own minions only -- unavoidable without a spatial
-- structure, which is intentionally out of scope for the foundation (a
-- future spatial-hash module can sit alongside Army without changing
-- this API). Never O(n^2): only ever scans ONE army's minions, never
-- compares minions against other armies' minions.
function Army:GetNearest(position: Vector3): any?
	local nearest = nil
	local nearestDist = math.huge
	for _, minion in ipairs(self.Minions) do
		local model = minion.Model
		local root = model and model.PrimaryPart
		if root then
			local dist = (root.Position - position).Magnitude
			if dist < nearestDist then
				nearestDist = dist
				nearest = minion
			end
		end
	end
	return nearest
end

-- Destroys every minion (which cascades into RemoveMinion via the
-- Destroying hook above) rather than just detaching them -- the Army
-- OWNS its minions, so clearing the army clears their lifecycle too.
function Army:Clear()
	local minions = self.Minions
	for i = #minions, 1, -1 do
		local minion = minions[i]
		if minion and not minion.Destroyed then
			minion:Destroy()
		end
	end
end

function Army:Select(minion: any)
	if self._indexByMinion[minion] then
		self.Selection[minion] = true
	end
end

function Army:Deselect(minion: any)
	self.Selection[minion] = nil
end

function Army:ClearSelection()
	table.clear(self.Selection)
end

-- Forwarded to Formation; called once per frame by ArmyService/owner
-- tracking, not by gameplay code directly.
function Army:SetAnchor(cframe: CFrame)
	self.Formation:SetAnchor(cframe)
end

function Army:Destroy()
	self:Clear()
	FormationSystem.UnregisterFormation(self.Formation)
	self.Formation:Destroy()
	table.clear(self._indexByMinion)
	table.clear(self._byId)
	table.clear(self._destroyingConns)
	table.clear(self.Selection)
end

local function new(armyId: number, owner: Player): Army
	local self = setmetatable({
		ArmyId = armyId,
		Owner = owner,
		Minions = {},
		Formation = FormationComponent.new({ Shape = "Circle", Spacing = 5 }),
		CurrentTask = nil,
		Selection = {},
		Settings = {},

		_indexByMinion = {},
		_byId = {},
		_destroyingConns = {},
	}, Army)

	FormationSystem.RegisterFormation(self.Formation)

	return (self :: any) :: Army
end

return {
	new = new,
}
