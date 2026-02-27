--[[
	SquadBehavior.lua  (place in ServerScriptService.NPCAIModule.Personalities)

	A personality MIXIN — not a standalone personality.
	Wraps any existing personality and layers squad coordination on top.

	FIXES (v2):
	  - OnSquadAlert no longer calls FSM:Transition("Chase") directly.
	    Previously: Chase.OnUpdate ran immediately after, found CurrentTarget=nil
	    (threat table was just written, TargetSys:Update() hadn't run yet),
	    and kicked back to Idle every single time.
	    Now: we seed TargetSys.LastKnownPos with the broadcaster's position
	    so Chase has a valid destination, then transition. Chase will hold
	    because LastKnownPos is set even when CurrentTarget is nil.
	  - _huntMode now properly gates CanEnterCombat so Chase doesn't
	    immediately bail via the personality check.
	  - Formation: followers now path to target position + offset directly
	    (not leader position), so they spread around the player correctly.
--]]

local SquadManager = require(game.ServerScriptService.NPCAIModule.SquadManager)
local Config       = require(game.ReplicatedStorage.Shared.Config)

local CFG = Config.Squad

local SquadBehavior = {}
SquadBehavior.__index = SquadBehavior

-- ─── Wrap ──────────────────────────────────────────────────────────────────

function SquadBehavior.wrap(entity: any, base: any): any
	local self = setmetatable({}, SquadBehavior)

	self.Entity          = entity
	self._base           = base
	self.Name            = (base.Name or "None") .. "+Squad"

	self._alertCooldown  = 0
	self._huntMode       = false
	self._huntTimer      = 0
	self._formationTimer = 0

	SquadManager.register(entity)

	return self
end

-- ─── Squad queries ─────────────────────────────────────────────────────────

function SquadBehavior:IsLeader(): boolean
	return SquadManager.getLeader(self.Entity) == self.Entity
end

function SquadBehavior:GetSquadSize(): number
	return SquadManager.getMemberCount(self.Entity)
end

-- ─── Base pass-throughs ────────────────────────────────────────────────────

function SquadBehavior:CanEnterCombat(): boolean
	-- Hunt mode overrides the base personality so Chase doesn't immediately bail
	if self._huntMode then return true end
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
	if attacker and self._alertCooldown <= 0 then
		self._alertCooldown = CFG.AlertCooldown
		SquadManager.alert(self.Entity, attacker)
	end
end

-- ─── Extended hooks ────────────────────────────────────────────────────────

function SquadBehavior:OnTargetFound(player: any)
	self._base:OnTargetFound(player)
	if self._alertCooldown <= 0 then
		self._alertCooldown = CFG.AlertCooldown
		SquadManager.alert(self.Entity, player)
	end
end

--[[
	Called by SquadManager when an ally alerts us.

	THE FIX: instead of blindly calling FSM:Transition("Chase") and hoping
	TargetSys already has CurrentTarget set (it doesn't — Update() hasn't
	run yet this frame), we:
	  1. Enter hunt mode so CanEnterCombat() returns true
	  2. Seed TargetSys.LastKnownPos with the broadcaster's position
	     Chase.OnUpdate checks LastKnownPos as a fallback when CurrentTarget=nil,
	     so the NPC will walk toward the fight instead of snapping back to Idle
	  3. Transition to Chase — now it will hold because LastKnownPos is valid
	  4. Also start pathing immediately so there's no 0.2s PathRecalcDelay lag
--]]
function SquadBehavior:OnSquadAlert(target: any, broadcaster: any)
	local entity = self.Entity

	-- Step 1: enter hunt mode FIRST so CanEnterCombat() = true
	self._huntMode  = true
	self._huntTimer = CFG.AlertDuration

	-- Step 2: register threat and unignore (so TargetSys can pick them up next tick)
	if entity.TargetSys and target then
		entity.TargetSys:UnignorePlayer(target)
		entity.TargetSys:RegisterThreat(target, CFG.AlertThreatBoost)
	end

	-- Step 3: seed LastKnownPos so Chase has a valid destination right now
	-- Priority: target's actual position > broadcaster's position
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local knownPos   = nil

	if targetRoot then
		knownPos = targetRoot.Position
	elseif broadcaster and broadcaster.RootPart then
		-- We don't have LoS to target — at least walk toward the ally who does
		knownPos = broadcaster.RootPart.Position
	end

	if knownPos then
		entity.TargetSys.LastKnownPos  = knownPos
		entity.TargetSys.TimeSinceSeen = 0
	end

	-- Step 4: transition to Chase and kick off pathfinding immediately
	local state = entity.FSM:GetState()
	if state == "Idle" or state == "Patrol" then
		entity.FSM:Transition("Chase")

		-- Start moving right now — don't wait for Chase.OnUpdate's recalc timer
		if knownPos and entity.Pathfinder then
			entity.Pathfinder:MoveTo(knownPos)
		end
	end

	print(("[SquadBehavior] %s received ALERT from %s — hunting %s"):format(
		entity.NPC.Name,
		broadcaster and broadcaster.NPC.Name or "?",
		tostring(target)))
end

-- ─── Update ────────────────────────────────────────────────────────────────

function SquadBehavior:OnUpdate(dt: number)
	self._alertCooldown  -= dt
	self._formationTimer += dt

	-- Hunt mode: keep CanEnterCombat() = true until timer expires
	if self._huntMode then
		self._huntTimer -= dt
		if self._huntTimer <= 0 then
			self._huntMode = false
			-- Only go idle if we truly lost the target
			if not self.Entity.TargetSys.CurrentTarget
				and not self.Entity.TargetSys.LastKnownPos then
				self.Entity.FSM:Transition("Idle")
			end
		end
	end

	-- Formation (every 0.3s, only during Chase)
	if self._formationTimer >= 0.3 then
		self._formationTimer = 0
		self:_applyFormation()
	end

	self._base:OnUpdate(dt)
end

-- ─── Formation ─────────────────────────────────────────────────────────────

function SquadBehavior:_applyFormation()
	local entity = self.Entity
	if entity.FSM:GetState() ~= "Chase" then return end
	if self:IsLeader() then return end  -- leader chases directly, no offset

	local offset = SquadManager.getFormationOffset(entity)

	-- Get target position — prefer live target, fall back to shared/last known
	local target     = entity.TargetSys.CurrentTarget
		or SquadManager.getSharedTarget(entity)
	local targetRoot = target and target.Character
		and target.Character:FindFirstChild("HumanoidRootPart")
	local targetPos  = targetRoot and targetRoot.Position
		or entity.TargetSys.LastKnownPos

	if not targetPos then return end

	local dest     = targetPos + offset
	local slotDist = (entity.RootPart.Position - dest).Magnitude

	if slotDist > CFG.FormationSnapDist then
		entity.Pathfinder:MoveTo(dest)
	end
end

-- ─── Cleanup ───────────────────────────────────────────────────────────────

function SquadBehavior:Destroy()
	SquadManager.unregister(self.Entity)
	self._base:Destroy()
end

return SquadBehaviors