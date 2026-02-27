--[[
	Passive.lua

	Behavior:
	  - Roams/patrols normally, completely ignores players proximity
	  - ShouldForceFlee() always returns false unless attacked
	  - OnDamaged: flee from attacker for a short time, then resume patrol
	  - Never attacks back (CanEnterCombat = false)
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Passive = setmetatable({}, { __index = PersonalityBase })
Passive.__index = Passive

local CFG = Config.Passive

-- How long the NPC flees after being hit before calming down
local FLEE_DURATION = 6

function Passive.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Passive)
	self.Name          = "Passive"
	self._fleeTimer    = 0       -- counts down after being hit
	self._isProvoked   = false   -- true only while flee timer is active
	self._attacker     = nil     -- who hit us
	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Passive:CanEnterCombat(): boolean
	return false  -- never attacks, ever
end

function Passive:ShouldForceFlee(): boolean
	return self._isProvoked  -- only true after being hit
end

function Passive:GetFleeSpeed(): number?
	return CFG.FleeSpeed
end

-- ── Internal update ────────────────────────────────────────────────────────

function Passive:OnUpdate(dt: number)
	if not self._isProvoked then return end

	-- Count down flee timer
	self._fleeTimer -= dt
	if self._fleeTimer <= 0 then
		self._isProvoked = false
		self._attacker   = nil
	end
end

function Passive:OnDamaged(amount: number, attacker: Player?)
	-- Being hit is the ONLY trigger for flee behavior
	self._isProvoked = true
	self._fleeTimer  = FLEE_DURATION
	self._attacker   = attacker

	-- Immediately path away from attacker
	if attacker then
		local entity = self.Entity
		local pRoot  = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if pRoot then
			local away = (entity.RootPart.Position - pRoot.Position).Unit
			entity.Humanoid.WalkSpeed = CFG.FleeSpeed
			entity.Pathfinder:MoveTo(entity.RootPart.Position + away * CFG.FleeRadius)
		end
	end
end

function Passive:Destroy() end

return Passive