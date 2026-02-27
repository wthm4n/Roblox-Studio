--[[
	Scared.lua

	Hysteresis fix: ShouldForceFlee() uses two thresholds.
	  Enter flee: player <= FleeRadius
	  Exit flee:  player > FleeRadius + 10
	Prevents Flee<->Idle oscillation when player is on the edge of the radius.
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Scared = setmetatable({}, { __index = PersonalityBase })
Scared.__index = Scared

local CFG = Config.Scared

function Scared.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Scared)
	self.Name             = "Scared"
	self._frozen          = false
	self._freezeTimer     = 0
	self._tripped         = false
	self._tripTimer       = 0
	self._updateTimer     = 0
	self._nearestPlayer   = nil
	self._nearestDist     = math.huge
	self._isThreatActive  = false  -- hysteresis flag
	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Scared:CanEnterCombat(): boolean
	return false
end

function Scared:ShouldForceFlee(): boolean
	if self._nearestPlayer then
		if not self._isThreatActive and self._nearestDist <= CFG.FleeRadius then
			self._isThreatActive = true
		elseif self._isThreatActive and self._nearestDist > CFG.FleeRadius + 10 then
			self._isThreatActive = false
		end
	else
		self._isThreatActive = false
	end
	return self._isThreatActive
end

function Scared:GetFleeSpeed(): number?
	if self._frozen then return 0 end
	if self._tripped then return CFG.PanicSpeed * CFG.SlowMultiplier end
	return CFG.PanicSpeed
end

-- ── Internal update ────────────────────────────────────────────────────────

function Scared:OnUpdate(dt: number)
	local entity = self.Entity

	-- Tick timers
	if self._frozen then
		self._freezeTimer -= dt
		if self._freezeTimer <= 0 then
			self._frozen = false
		end
	end

	if self._tripped then
		self._tripTimer -= dt
		if self._tripTimer <= 0 then
			self._tripped = false
		end
	end

	-- Apply speed
	local speed = self:GetFleeSpeed()
	if speed then
		entity.Humanoid.WalkSpeed = speed
	end

	-- Throttled scan
	self._updateTimer += dt
	if self._updateTimer < 0.25 then return end
	self._updateTimer = 0

	self._nearestPlayer, self._nearestDist = self:_scanNearestPlayer()

	if self._isThreatActive and self._nearestPlayer then
		if not self._frozen then
			if math.random() < CFG.FreezeChance then
				self._frozen      = true
				self._freezeTimer = CFG.FreezeDuration
				entity.Pathfinder:Stop()
				return
			end

			if not self._tripped and math.random() < CFG.SlowChance then
				self._tripped   = true
				self._tripTimer = CFG.SlowDuration
			end

			self:_panicMove()
		end
	end
end

function Scared:OnDamaged(amount: number, attacker: Player?)
	self._frozen         = true
	self._freezeTimer    = 0.8
	self._isThreatActive = true  -- getting hit always activates threat
	self.Entity.Pathfinder:Stop()
end

-- ── Private ────────────────────────────────────────────────────────────────

function Scared:_scanNearestPlayer(): (Player?, number)
	local Players  = game:GetService("Players")
	local nearest  = nil
	local nearDist = math.huge
	local from     = self.Entity.RootPart.Position
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			local d = (from - root.Position).Magnitude
			if d < nearDist then nearDist = d; nearest = p end
		end
	end
	return nearest, nearDist
end

function Scared:_panicMove()
	local entity = self.Entity
	local player = self._nearestPlayer
	if not player or not player.Character then return end

	local root  = entity.RootPart.Position
	local pRoot = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not pRoot then return end

	local awayDir   = (root - pRoot.Position).Unit
	local randAngle = math.rad(math.random(30, 70) * (math.random() > 0.5 and 1 or -1))
	local cosA, sinA = math.cos(randAngle), math.sin(randAngle)
	local panicDir  = Vector3.new(
		awayDir.X * cosA - awayDir.Z * sinA,
		0,
		awayDir.X * sinA + awayDir.Z * cosA
	).Unit

	entity.Pathfinder:MoveTo(root + panicDir * 20)
end

function Scared:Destroy() end

return Scared