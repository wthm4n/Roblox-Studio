--[[
	Scared.lua

	Behavior:
	  - Completely ignores all players for TargetSys (never chases, never attacks)
	  - Does its own proximity scanning every frame
	  - Player enters FleeRadius → immediately flee AWAY from them
	  - Player gets within HearRange (closer) → random freeze or slow panic effect
	  - If attacked → flee hard for 5s regardless of distance
	  - Flee ends only when no player is within FleeRadius AND not attacked
	  - Never attacks back under any circumstance

	Direction fix:
	  Since TargetSys.CurrentTarget is always nil for Scared, _beginFlee
	  would pick a random direction. Instead we override _beginFlee by
	  directly calling Pathfinder:MoveTo with the correct away-direction
	  ourselves, and we re-path every 3s via _fleeUpdateTimer.
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)
local Players         = game:GetService("Players")

local Scared = setmetatable({}, { __index = PersonalityBase })
Scared.__index = Scared

local CFG = Config.Scared

function Scared.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Scared)
	self.Name              = "Scared"
	self._isFleeing        = false
	self._isAttacked       = false
	self._attackedTimer    = 0
	self._panicTimer       = 0
	self._currentSpeed     = CFG.PanicSpeed
	self._frozen           = false
	self._nearestThreat    = nil   -- Vector3 of nearest player position
	self._fleeUpdateTimer  = 0     -- re-path away every N seconds

	-- Scared NPCs never engage TargetSys
	entity.TargetSys:IgnoreAll()

	self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
		entity.TargetSys:IgnorePlayer(player)
	end)

	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Scared:CanEnterCombat(): boolean
	return false
end

function Scared:ShouldForceFlee(): boolean
	return self._isFleeing or self._isAttacked
end

function Scared:GetFleeSpeed(): number?
	if self._frozen then return 0 end
	return self._currentSpeed
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────

function Scared:OnUpdate(dt: number)
	-- ── Attacked timer ────────────────────────────────────────────────────
	if self._isAttacked then
		self._attackedTimer -= dt
		if self._attackedTimer <= 0 then
			self._isAttacked = false
		end
	end

	-- ── Panic effect timer ────────────────────────────────────────────────
	if self._panicTimer > 0 then
		self._panicTimer -= dt
		if self._panicTimer <= 0 then
			self._frozen       = false
			self._currentSpeed = CFG.PanicSpeed
		end
	end

	-- ── Proximity scan ────────────────────────────────────────────────────
	local root          = self.Entity.RootPart
	local anyInRange    = false
	local anyInPanic    = false
	local nearestDist   = math.huge
	local nearestPos    = nil

	for _, player in ipairs(Players:GetPlayers()) do
		local char  = player.Character
		local pRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not pRoot then continue end

		local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
		if not hum or hum.Health <= 0 then continue end

		local dist = (root.Position - pRoot.Position).Magnitude

		if dist <= CFG.FleeRadius then
			anyInRange = true
			if dist < nearestDist then
				nearestDist = dist
				nearestPos  = pRoot.Position
			end
		end

		if dist <= Config.Detection.HearRange and self._panicTimer <= 0 then
			anyInPanic = true
		end
	end

	local wasAlreadyFleeing = self._isFleeing
	self._isFleeing      = anyInRange
	self._nearestThreat  = nearestPos  -- track for flee direction

	-- Panic effect when player gets very close
	if anyInPanic and self._panicTimer <= 0 then
		self:_triggerPanic()
	end

	-- Speed reset when nothing threatening
	if not self._isFleeing and not self._isAttacked and not self._frozen then
		self._currentSpeed = CFG.PanicSpeed
	end

	-- ── Flee pathing ──────────────────────────────────────────────────────
	-- We handle our own flee direction since TargetSys.CurrentTarget is nil.
	-- Re-path every 2 seconds or immediately when we just started fleeing.
	local shouldBeMoving = self._isFleeing or self._isAttacked
	if shouldBeMoving then
		self._fleeUpdateTimer -= dt
		local justStarted = anyInRange and not wasAlreadyFleeing

		if justStarted or self._fleeUpdateTimer <= 0 then
			self._fleeUpdateTimer = 2
			self:_pathAwayFromThreat()
		end
	else
		self._fleeUpdateTimer = 0
	end
end

function Scared:OnDamaged(amount: number, attacker: Player?)
	self._isAttacked    = true
	self._attackedTimer = 5

	-- Store attacker position as threat so we flee the right way
	if attacker and attacker.Character then
		local pRoot = attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if pRoot then
			self._nearestThreat = pRoot.Position
		end
	end

	self:_triggerPanic()
	-- Immediately re-path away
	self._fleeUpdateTimer = 0
end

-- ── Private ───────────────────────────────────────────────────────────────

function Scared:_pathAwayFromThreat()
	if self._frozen then return end  -- can't move when frozen

	local entity   = self.Entity
	local root     = entity.RootPart
	local threat   = self._nearestThreat

	local awayDir: Vector3
	if threat then
		awayDir = (root.Position - threat).Unit
		awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)
		if awayDir.Magnitude < 0.01 then
			-- Exactly on top of threat — pick random direction
			awayDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		else
			awayDir = awayDir.Unit
		end
	else
		-- No known threat pos — random direction
		awayDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
	end

	local dest = root.Position + awayDir * Config.Patrol.WanderRadius
	entity.Pathfinder:MoveTo(dest)
end

function Scared:_triggerPanic()
	local roll = math.random()

	if roll < CFG.FreezeChance then
		self._frozen       = true
		self._panicTimer   = CFG.FreezeDuration
		self._currentSpeed = 0
	elseif roll < CFG.FreezeChance + CFG.SlowChance then
		self._frozen       = false
		self._currentSpeed = CFG.PanicSpeed * CFG.SlowMultiplier
		self._panicTimer   = CFG.SlowDuration
	else
		self._frozen       = false
		self._currentSpeed = CFG.PanicSpeed
	end
end

function Scared:OnStateChanged(newState: string, oldState: string) end
function Scared:OnTargetFound(target: Player) end
function Scared:OnTargetLost() end

function Scared:Destroy()
	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
		self._playerAddedConn = nil
	end
end

return Scared -- idk