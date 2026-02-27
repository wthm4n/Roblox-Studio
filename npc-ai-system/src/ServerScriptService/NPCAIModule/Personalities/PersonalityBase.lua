--[[
	PersonalityBase.lua
	Base class all personality types inherit from.

	Added: CanEnterCombat() — returns true by default.
	Scared and Passive override this to return false, which States.lua
	checks before ever transitioning to Chase or Attack.
	This replaces the broken task.defer approach entirely.
--]]

local PersonalityBase = {}
PersonalityBase.__index = PersonalityBase

function PersonalityBase.new(entity: any, config: table)
	local self = setmetatable({}, PersonalityBase)
	self.Entity  = entity
	self.Config  = config or {}
	self.Name    = "Base"
	return self
end

function PersonalityBase:CanEnterCombat(): boolean
	return true  -- Aggressive, Tactical, and base NPCs can fight
end

function PersonalityBase:OnUpdate(dt: number) end
function PersonalityBase:OnStateChanged(newState: string, oldState: string) end
function PersonalityBase:OnTargetFound(player: Player) end
function PersonalityBase:OnTargetLost() end
function PersonalityBase:OnDamaged(amount: number, attacker: Player?) end
function PersonalityBase:Destroy() end

return PersonalityBase