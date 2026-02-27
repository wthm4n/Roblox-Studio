--[[
	SquadBehavior.lua  (place in ServerScriptService.NPCAIModule.Personalities)

	A personality MIXIN — not a standalone personality.
	Wraps any existing personality and layers squad coordination on top.

	Usage in PersonalityManager.create():
	  local base = PersonalityClass.new(entity)
	  return SquadBehavior.wrap(entity, base)

	What it adds:
	  • OnTargetFound → alerts the squad via SquadManager
	  • OnSquadAlert  → receives broadcasts, forces target tracking
	  • OnUpdate      → applies formation offsets when chasing
	                    leader sets waypoints, followers path to leader's pos + offset
	  • IsLeader()    → helpers for other personalities to query their role
	  
	Design principle:
	  SquadBehavior delegates ALL base personality calls through to the
	  wrapped personality. It only intercepts/augments specific hooks.
	  This means Tactical + Squad, Aggressive + Squad, etc. all work
	  without modifying the underlying personality files.
--]]

local SquadManager = require(game.ServerScriptService.NPCAIModule.SquadManager)
local Config       = require(game.ReplicatedStorage.Shared.Config)

local CFG = Config.Squad

local SquadBehavior = {}
SquadBehavior.__index = SquadBehavior

-- ─── Wrap ──────────────────────────────────────────────────────────────────

--[[
	Wraps a base personality instance and returns a new object that:
	  1. Passes all base personality method calls through unchanged
	  2. Overrides/extends OnTargetFound, OnUpdate, and adds OnSquadAlert
--]]
function SquadBehavior.wrap(entity: any, base: any): any
	local self = setmetatable({}, SquadBehavior)

	self.Entity      = entity
	self._base       = base
	self.Name        = (base.Name or "None") .. "+Squad"

	-- Squad state
	self._alertCooldown = 0   -- prevent spam-alerting
	self._huntMode      = false
	self._huntTimer     = 0
	self._formationTimer = 0

	-- Register with the squad system
	SquadManager.register(entity)

	return self
end

-- ─── Squad Queries (usable by States or other personalities) ───────────────

function SquadBehavior:IsLeader(): boolean
	return SquadManager.getLeader(self.Entity) == self.Entity
end

function SquadBehavior:GetSquadSize(): number
	return SquadManager.getMemberCount(self.Entity)
end

-- ─── Base personality pass-throughs ────────────────────────────────────────

function SquadBehavior:CanEnterCombat(): boolean
	if self._huntMode then return true end  -- squad alert overrides base
	return self._base:CanEnterCombat()
end

function SquadBehavior:ShouldForceFlee(): boolean
	return self._base:ShouldForceFlee()
end

function SquadBehavior:GetFleeSpeed(): number?
	return self._base:GetFleeSpeed()
end

function SquadBehavior:OnStateChanged(newState: string, oldState: string)
	self._base:OnStateChanged(newState, oldState)
end

function SquadBehavior:OnTargetLost()
	self._base:OnTargetLost()
end

function SquadBehavior:OnDamaged(amount: number, attacker: any?)
	self._base:OnDamaged(amount, attacker)

	-- Being shot at alerts the whole squad
	if attacker and self._alertCooldown <= 0 then
		self._alertCooldown = CFG.AlertCooldown
		SquadManager.alert(self.Entity, attacker)
	end
end

-- ─── Extended hooks ────────────────────────────────────────────────────────

function SquadBehavior:OnTargetFound(player: any)
	self._base:OnTargetFound(player)

	-- Alert squad when we personally spot someone
	if self._alertCooldown <= 0 then
		self._alertCooldown = CFG.AlertCooldown
		SquadManager.alert(self.Entity, player)
	end
end

--[[
	Called by SquadManager when an ally alerts us about a target.
	broadcaster = the brain that spotted the player first.
--]]
function SquadBehavior:OnSquadAlert(target: any, broadcaster: any)
	local entity = self.Entity

	-- Enter hunt mode: override CanEnterCombat for CFG.AlertDuration
	self._huntMode  = true
	self._huntTimer = CFG.AlertDuration

	-- If we can actually track the target, do so immediately
	if entity.TargetSys then
		entity.TargetSys:UnignorePlayer(target)
		entity.TargetSys:RegisterThreat(target, CFG.AlertThreatBoost)
	end

	-- Force chase state if we're just patrolling
	local state = entity.FSM:GetState()
	if state == "Idle" or state == "Patrol" then
		-- Use LastKnownPos from broadcaster so we navigate toward the fight
		local bRoot = broadcaster.RootPart
		if bRoot and entity.Pathfinder then
			-- Path toward the broadcaster first (who has line of sight)
			entity.Pathfinder:MoveTo(bRoot.Position)
		end
		entity.FSM:Transition("Chase")
	end

	print(("[SquadBehavior] %s received ALERT from %s — hunting %s"):format(
		entity.NPC.Name,
		broadcaster.NPC.Name,
		tostring(target)))
end

function SquadBehavior:OnUpdate(dt: number)
	-- Decay timers
	self._alertCooldown  -= dt
	self._formationTimer += dt

	-- Hunt mode expiry
	if self._huntMode then
		self._huntTimer -= dt
		if self._huntTimer <= 0 then
			self._huntMode = false
			-- If no personal target either, go idle
			if not self.Entity.TargetSys.CurrentTarget then
				self.Entity.FSM:Transition("Idle")
			end
		end
	end

	-- ── Formation logic (every 0.3s) ────────────────────────────────────
	if self._formationTimer >= 0.3 then
		self._formationTimer = 0
		self:_applyFormation()
	end

	-- Delegate to base personality
	self._base:OnUpdate(dt)
end

-- ─── Formation ─────────────────────────────────────────────────────────────

function SquadBehavior:_applyFormation()
	local entity = self.Entity
	local state  = entity.FSM:GetState()

	-- Only apply formation during Chase
	if state ~= "Chase" then return end

	local isLeader = self:IsLeader()
	local offset   = SquadManager.getFormationOffset(entity)

	if isLeader then
		-- Leader chases the target directly — no offset needed
		-- The leader's pathfinder is already managed by States.Chase
		return
	end

	-- Follower: path to (leader position + formation offset)
	-- If no leader is alive, fall back to normal chase
	local leader = SquadManager.getLeader(entity)
	if not leader or not leader.NPC.Parent then return end

	local target = entity.TargetSys.CurrentTarget
		or SquadManager.getSharedTarget(entity)

	if not target then return end

	-- Destination: formation slot relative to current target position
	-- This means the group surrounds the player, not clusters on the leader
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local dest = targetRoot.Position + offset

	-- Only re-path if we've drifted from our slot
	local myPos   = entity.RootPart.Position
	local slotDist = (myPos - dest).Magnitude

	if slotDist > CFG.FormationSnapDist then
		entity.Pathfinder:MoveTo(dest)
	end
end

-- ─── Cleanup ───────────────────────────────────────────────────────────────

function SquadBehavior:Destroy()
	SquadManager.unregister(self.Entity)
	self._base:Destroy()
end

return SquadBehavior