--[[
	States.lua

	Clean architecture: This file is the ONLY place FSM:Transition is called.
	Personalities are queried via:
	  entity.Personality:CanEnterCombat()  — should we chase/attack?
	  entity.Personality:ShouldForceFlee() — should we flee regardless of HP?
	  entity.Personality:GetFleeSpeed()    — personality-specific flee speed

	FIXED:
	  - Chase.OnUpdate now exits to Idle if CanEnterCombat() is false.
	    Previously if a Passive NPC somehow entered Chase (via the threat
	    table bug), it would stay there forever since there was no exit guard.
	  - Attack.OnUpdate same fix — gates on CanEnterCombat().
	  - This means even if a personality-less bug gets an NPC into Chase/Attack,
	    the state itself will kick it back out if the personality says no.
--]]

local Config = require(game.ReplicatedStorage.Shared.Config)

local function setSpeed(entity, speed: number)
	if entity.Humanoid then
		entity.Humanoid.WalkSpeed = speed
	end
end

local function distanceTo(entity, pos: Vector3): number
	return (entity.RootPart.Position - pos).Magnitude
end

-- Shared flee check: HP-based OR personality-forced
local function shouldFlee(entity): boolean
	if entity:_shouldFlee() then return true end
	if entity.Personality:ShouldForceFlee() then return true end
	return false
end

-- ─── IDLE ──────────────────────────────────────────────────────────────────

local Idle = {
	Name = "Idle",

	OnEnter = function(entity)
		setSpeed(entity, Config.Movement.WalkSpeed)
		entity.Pathfinder:Stop()
		entity._idleTimer = 0
	end,

	OnUpdate = function(entity, dt)
		entity._idleTimer += dt

		if shouldFlee(entity) then
			entity.FSM:Transition("Flee")
			return
		end

		if entity.TargetSys.CurrentTarget and entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Chase")
			return
		end

		if entity._idleTimer >= 1.5 then
			entity.FSM:Transition("Patrol")
			return
		end
	end,

	OnExit = function(entity)
		entity._idleTimer = 0
	end,
}

-- ─── PATROL ────────────────────────────────────────────────────────────────

local Patrol = {
	Name = "Patrol",

	OnEnter = function(entity)
		setSpeed(entity, Config.Movement.WalkSpeed)
		entity._patrolWaiting   = false
		entity._patrolWaitTimer = 0
		entity._patrolIndex     = entity._patrolIndex or 1
		entity:_beginNextPatrol()
	end,

	OnUpdate = function(entity, dt)
		if shouldFlee(entity) then
			entity.FSM:Transition("Flee")
			return
		end

		if entity.TargetSys.CurrentTarget and entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Chase")
			return
		end

		if entity._patrolWaiting then
			entity._patrolWaitTimer += dt
			if entity._patrolWaitTimer >= Config.Patrol.WaitTime then
				entity._patrolWaiting   = false
				entity._patrolWaitTimer = 0
				entity:_beginNextPatrol()
			end
		end
	end,

	OnExit = function(entity)
		entity.Pathfinder:Stop()
	end,
}

-- ─── CHASE ─────────────────────────────────────────────────────────────────

local Chase = {
	Name = "Chase",

	OnEnter = function(entity)
		-- Safety: if this NPC can't enter combat, immediately bail back to Idle.
		-- This acts as a second line of defense in case something bypasses the
		-- Idle/Patrol guards above (e.g. Aggressive retreat re-entry).
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Idle")
			return
		end
		setSpeed(entity, Config.Movement.ChaseSpeed)
		entity._chaseRecalcTimer = 0
	end,

	OnUpdate = function(entity, dt)
		-- FIXED: if personality revokes combat mid-chase (e.g. Passive calmed down)
		-- kick back to Idle immediately rather than continuing to chase.
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Idle")
			return
		end

		if shouldFlee(entity) then
			entity.FSM:Transition("Flee")
			return
		end

		local target, lastKnown = entity.TargetSys.CurrentTarget, entity.TargetSys.LastKnownPos

		if not target and not lastKnown then
			entity.FSM:Transition("Idle")
			return
		end

		local targetPos = nil
		if target and target.Character then
			local root = target.Character:FindFirstChild("HumanoidRootPart")
			if root then targetPos = root.Position end
		end
		targetPos = targetPos or lastKnown

		if not targetPos then
			entity.FSM:Transition("Idle")
			return
		end

		if distanceTo(entity, targetPos) <= Config.Combat.AttackRange then
			entity.FSM:Transition("Attack")
			return
		end

		entity._chaseRecalcTimer += dt
		if entity._chaseRecalcTimer >= Config.Movement.PathRecalcDelay then
			entity._chaseRecalcTimer = 0
			entity.Pathfinder:MoveTo(targetPos)
		end
	end,

	OnExit = function(entity)
		entity.Pathfinder:Stop()
		entity._chaseRecalcTimer = 0
	end,
}

-- ─── ATTACK ────────────────────────────────────────────────────────────────

local Attack = {
	Name = "Attack",

	OnEnter = function(entity)
		-- Safety: same guard as Chase
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Idle")
			return
		end
		setSpeed(entity, Config.Movement.WalkSpeed)
		entity._attackTimer = 0
		local target = entity.TargetSys.CurrentTarget
		if target and target.Character then
			local root = target.Character:FindFirstChild("HumanoidRootPart")
			if root then
				entity.RootPart.CFrame = CFrame.lookAt(
					entity.RootPart.Position,
					root.Position * Vector3.new(1, 0, 1) + entity.RootPart.Position * Vector3.new(0, 1, 0)
				)
			end
		end
	end,

	OnUpdate = function(entity, dt)
		-- FIXED: same guard
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Idle")
			return
		end

		if shouldFlee(entity) then
			entity.FSM:Transition("Flee")
			return
		end

		local target = entity.TargetSys.CurrentTarget

		if not target or not target.Character then
			entity.FSM:Transition("Idle")
			return
		end

		local root = target.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			entity.FSM:Transition("Chase")
			return
		end

		if distanceTo(entity, root.Position) > Config.Combat.AttackRange + 2 then
			entity.FSM:Transition("Chase")
			return
		end

		entity._attackTimer += dt
		if entity._attackTimer >= Config.Combat.AttackCooldown then
			entity._attackTimer = 0
			entity:_performAttack(target)
		end
	end,

	OnExit = function(entity)
		entity._attackTimer = 0
	end,
}

-- ─── FLEE ──────────────────────────────────────────────────────────────────

local Flee = {
	Name = "Flee",

	OnEnter = function(entity)
		local speed = entity.Personality:GetFleeSpeed() or Config.Movement.FleeSpeed
		setSpeed(entity, speed)
		entity._fleeRecalcTimer = 0
	end,

	OnUpdate = function(entity, dt)
		local speed = entity.Personality:GetFleeSpeed() or Config.Movement.FleeSpeed
		setSpeed(entity, speed)

		-- Exit condition
		local hpOk          = not entity:_shouldFlee()
		local personalityOk = not entity.Personality:ShouldForceFlee()

		if hpOk and personalityOk then
			entity.FSM:Transition("Idle")
			return
		end

		entity._fleeRecalcTimer += dt
		if entity._fleeRecalcTimer >= 0.5 then -- recalc faster (0.5 instead of 3)
			entity._fleeRecalcTimer = 0

			local threat = entity.TargetSys.CurrentTarget
			if threat and threat.Character then
				local root = threat.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local npcPos = entity.RootPart.Position
					local threatPos = root.Position

					local awayDir = (npcPos - threatPos)
					awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)

					if awayDir.Magnitude < 0.1 then
						awayDir = Vector3.new(math.random()-0.5,0,math.random()-0.5)
					end

					awayDir = awayDir.Unit

					-- Dynamic flee distance (stronger escape)
					local fleeDistance = math.clamp(
						(npcPos - threatPos).Magnitude * 1.5,
						20,
						80
					)

					local dest = npcPos + awayDir * fleeDistance

					entity.Pathfinder:MoveTo(dest)
				end
			end
		end
	end,

	OnExit = function(entity)
		entity.Pathfinder:Stop()
		entity._fleeRecalcTimer = 0
	end,
}
-- ─── Export ────────────────────────────────────────────────────────────────

return {
	Idle   = Idle,
	Patrol = Patrol,
	Chase  = Chase,
	Attack = Attack,
	Flee   = Flee,
}