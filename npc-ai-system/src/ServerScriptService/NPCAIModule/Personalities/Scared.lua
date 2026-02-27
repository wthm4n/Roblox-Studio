--[[
	Scared.lua - Fixed version
	Key fix: Scared NPC now BLOCKS the FSM from ever entering Chase/Attack
	by overriding those transitions at the StateMachine level via OnStateChanged,
	not just reacting after the fact with task.defer (which was too late).
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Scared = setmetatable({}, { __index = PersonalityBase })
Scared.__index = Scared

local CFG = Config.Scared

function Scared.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Scared)
	self.Name          = "Scared"
	self._frozen       = false
	self._freezeTimer  = 0
	self._tripped      = false
	self._tripTimer    = 0
	self._updateTimer  = 0
	return self
end

-- ── CRITICAL FIX: intercept state transitions before they stick ────────────
function Scared:OnStateChanged(newState: string, oldState: string)
	-- Immediately redirect any Chase or Attack back to Flee
	if newState == "Chase" or newState == "Attack" then
		-- Use task.defer so we're not calling Transition inside Transition
		task.defer(function()
			local current = self.Entity.FSM:GetState()
			if current == "Chase" or current == "Attack" then
				self.Entity.FSM:Transition("Flee")
			end
		end)
	end
end

function Scared:OnUpdate(dt: number)
	local entity = self.Entity

	-- ── Freeze: stop everything ───────────────────────────────────────────
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

	-- ── Tripped: slow movement ────────────────────────────────────────────
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

	local rootPos       = entity.RootPart.Position
	local nearest, dist = self:_nearestPlayer(rootPos)

	if nearest and dist <= CFG.FleeRadius then
		-- Make sure we're in Flee state
		local state = entity.FSM:GetState()
		if state ~= "Flee" then
			entity.FSM:Transition("Flee")
		end

		-- Random freeze chance
		if not self._frozen and math.random() < CFG.FreezeChance then
			self._frozen      = true
			self._freezeTimer = CFG.FreezeDuration
			return
		end

		-- Random trip chance
		if not self._tripped and math.random() < CFG.SlowChance then
			self._tripped   = true
			self._tripTimer = CFG.SlowDuration
			entity.Humanoid.WalkSpeed = CFG.PanicSpeed * CFG.SlowMultiplier
		end

		self:_panicFlee(nearest)
	else
		-- Player out of range — calm down
		entity.Humanoid.WalkSpeed = Config.Movement.WalkSpeed
		if entity.FSM:GetState() == "Flee" then
			entity.FSM:Transition("Idle")
		end
	end
end

function Scared:OnTargetFound(player: Player)
	-- Belt-and-suspenders: also catch it here
	task.defer(function()
		local state = self.Entity.FSM:GetState()
		if state == "Chase" or state == "Attack" then
			self.Entity.FSM:Transition("Flee")
		end
	end)
end

function Scared:OnDamaged(amount: number, attacker: Player?)
	-- Getting hit = guaranteed short freeze
	self._frozen      = true
	self._freezeTimer = 0.8
	self.Entity.Pathfinder:Stop()
end

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
	local entity = self.Entity
	local root   = entity.RootPart.Position
	local pRoot  = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not pRoot then return end

	local awayDir   = (root - pRoot.Position).Unit
	local randAngle = math.rad(math.random(30, 70) * (math.random() > 0.5 and 1 or -1))
	local cosA, sinA = math.cos(randAngle), math.sin(randAngle)
	local panicDir  = Vector3.new(
		awayDir.X * cosA - awayDir.Z * sinA,
		0,
		awayDir.X * sinA + awayDir.Z * cosA
	).Unit

	entity.Humanoid.WalkSpeed = CFG.PanicSpeed
	entity.Pathfinder:MoveTo(root + panicDir * 20)
end

function Scared:Destroy() end

return Scared