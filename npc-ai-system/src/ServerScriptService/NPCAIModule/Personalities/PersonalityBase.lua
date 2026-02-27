--[[
	PersonalityBase.lua
	Base class all personality types inherit from.
	Defines the interface every personality must implement.

	A Personality is a layer ON TOP of the FSM.
	It overrides or extends state behavior without rewriting the core system.

	Each personality gets:
	  - self.Entity  → the NPCController
	  - self.Config  → personality-specific config table
	  - :OnUpdate(dt) called every heartbeat
	  - :OnStateChanged(newState, oldState) called on FSM transitions
	  - :OnTargetFound(player) called when a target is detected
	  - :OnTargetLost() called when target disappears
	  - :OnDamaged(amount, attacker) called on damage
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

-- Override these in subclasses
function PersonalityBase:OnUpdate(dt: number) end
function PersonalityBase:OnStateChanged(newState: string, oldState: string) end
function PersonalityBase:OnTargetFound(player: Player) end
function PersonalityBase:OnTargetLost() end
function PersonalityBase:OnDamaged(amount: number, attacker: Player?) end
function PersonalityBase:Destroy() end

return PersonalityBase
