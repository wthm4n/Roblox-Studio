--[[
	Scared.lua
	A panicking NPC. Unpredictable, clumsy, terrified.

	Behaviors:
	  - Flees in random panic directions (not optimal path)
	  - Random chance to freeze in place
	  - Random chance to "trip" and slow way down
	  - Never fights back
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(script.Parent.Parent.Parent.Shared.Config)

local Scared = setmetatable({}, { __index = PersonalityBase })
Scared.__index = Scared

local CFG = Config.Scared

-- ── Constructor ────────────────────────────────────────────────────────────

function Scared.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Scared)
	self.Name          = "Scared"
	self._frozen       = false
	self._freezeTimer  = 0
	self._tripped      = false
	self._tripTimer    = 0
	self._panicTimer   = 0
	self._updateTimer  = 0
	self._screamPlayed = false
	return self
end

-- ── Interface ──────────────────────────────────────────────────────────────

function Scared:OnUpdate(dt: number)
	local entity = self.Entity

	-- ── Freeze state ─────────────────────────────────────────────────────
	if self._frozen then
		self._freezeTimer -= dt
		entity.Humanoid.WalkSpeed = 0
		entity.Pathfinder:Stop()
		if self._freezeTimer <= 0 then
			self._frozen = false
			entity.Humanoid.WalkSpeed = CFG.PanicSpeed
		end
		return
	end

	-- ── Trip / slow state ─────────────────────────────────────────────────
	if self._tripped then
		self._tripTimer -= dt
		if self._tripTimer <= 0 then
			self._tripped = false
			entity.Humanoid.WalkSpeed = CFG.PanicSpeed
		end
		return
	end

	self._updateTimer += dt
	if self._updateTimer < 0.25 then return end
	self._updateTimer = 0

	local rootPos        = entity.RootPart.Position
	local nearest, dist  = self:_nearestPlayer(rootPos)

	if nearest and dist <= CFG.FleeRadius then
		-- Override FSM — scared NPCs never chase or attack
		local state = entity.FSM:GetState()
		if state == "Chase" or state == "Attack" then
			entity.FSM:Transition("Flee")
		end

		-- Random freeze
		if not self._frozen and math.random() < CFG.FreezeChance then
			self._frozen      = true
			self._freezeTimer = CFG.FreezeDuration
			return
		end

		-- Random trip
		if not self._tripped and math.random() < CFG.SlowChance then
			self._tripped   = true
			self._tripTimer = CFG.SlowDuration
			entity.Humanoid.WalkSpeed = CFG.PanicSpeed * CFG.SlowMultiplier
		end

		-- Panic flee: random direction with slight bias away from player
		self:_panicFlee(nearest)
		self._panicTimer += 0.25

	else
		-- Calm down after player leaves
		entity.Humanoid.WalkSpeed = Config.Movement.WalkSpeed
		self._screamPlayed = false
		if entity.FSM:GetState() == "Flee" then
			entity.FSM:Transition("Idle")
		end
	end
end

function Scared:OnTargetFound(player: Player)
	-- Never engage — force flee
	task.defer(function()
		local state = self.Entity.FSM:GetState()
		if state == "Chase" or state == "Attack" then
			self.Entity.FSM:Transition("Flee")
		end
	end)
end

function Scared:OnDamaged(amount: number, attacker: Player?)
	-- Getting hit causes a guaranteed freeze moment
	self._frozen      = true
	self._freezeTimer = 0.8
	self.Entity.Pathfinder:Stop()
end

-- ── Private ────────────────────────────────────────────────────────────────

function Scared:_nearestPlayer(from: Vector3): (Player?, number)
	local Players  = game:GetService("Players")
	local nearest  = nil
	local nearDist = math.huge
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

function Scared:_panicFlee(player: Player)
	local entity  = self.Entity
	local root    = entity.RootPart.Position
	local pRoot   = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not pRoot then return end

	-- Base direction away from player
	local awayDir = (root - pRoot.Position).Unit

	-- Add random panic offset (30-70 degrees off the ideal direction)
	local randAngle = math.rad(math.random(30, 70) * (math.random() > 0.5 and 1 or -1))
	local cosA, sinA = math.cos(randAngle), math.sin(randAngle)
	local panicDir = Vector3.new(
		awayDir.X * cosA - awayDir.Z * sinA,
		0,
		awayDir.X * sinA + awayDir.Z * cosA
	).Unit

	local dest = root + panicDir * 20
	entity.Humanoid.WalkSpeed = CFG.PanicSpeed
	entity.Pathfinder:MoveTo(dest)
end

function Scared:Destroy() end

return Scared
