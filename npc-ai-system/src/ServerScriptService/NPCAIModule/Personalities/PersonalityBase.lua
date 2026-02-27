--[[
	PersonalityBase.lua

	Clean architecture: Personalities answer questions. States own transitions.

	Personalities expose:
	  :CanEnterCombat()   → bool  — should this NPC ever chase/attack?
	  :ShouldForceFlee()  → bool  — should this NPC flee right now?
	  :GetFleeSpeed()     → number? — override flee speed (nil = use Config default)

	States check these each frame and decide transitions themselves.
	Personalities NEVER call FSM:Transition directly.
--]]

local PersonalityBase = {}
PersonalityBase.__index = PersonalityBase

function PersonalityBase.new(entity: any, config: table)
	local self = setmetatable({}, PersonalityBase)
	self.Entity = entity
	self.Config = config or {}
	self.Name   = "Base"
	return self
end

-- Override in Scared, Passive
function PersonalityBase:CanEnterCombat(): boolean
	return true
end

-- Override in Scared, Passive
function PersonalityBase:ShouldForceFlee(): boolean
	return false
end

-- Override to customize flee speed
function PersonalityBase:GetFleeSpeed(): number?
	return nil
end

-- Hooks — called by NPCController, used for internal personality state only
-- These must NEVER call FSM:Transition
function PersonalityBase:OnUpdate(dt: number) end
function PersonalityBase:OnStateChanged(newState: string, oldState: string) end
function PersonalityBase:OnTargetFound(player: Player) end
function PersonalityBase:OnTargetLost() end
function PersonalityBase:OnDamaged(amount: number, attacker: Player?) end
function PersonalityBase:Destroy() end

return PersonalityBase