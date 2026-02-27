--[[
	States.lua

	Clean architecture: This file is the ONLY place FSM:Transition is called.
	Personalities are queried via:
	  entity.Personality:CanEnterCombat()  — should we chase/attack?
	  entity.Personality:ShouldForceFlee() — should we flee regardless of HP?
	  entity.Personality:GetFleeSpeed()    — personality-specific flee speed

	Personalities never call FSM:Transition themselves. No fighting, no spam.
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

		if entity.TargetSys.CurrentTarget then
    if entity.Personality:CanEnterCombat() then
        entity.FSM:Transition("Chase")
        return
    end
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

		if entity.TargetSys.CurrentTarget then
    if entity.Personality:CanEnterCombat() then
        entity.FSM:Transition("Chase")
        return
    end
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
		setSpeed(entity, Config.Movement.ChaseSpeed)
		entity._chaseRecalcTimer = 0
	end,

	OnUpdate = function(entity, dt)
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
		-- Use personality flee speed if provided, else default
		local speed = entity.Personality:GetFleeSpeed() or Config.Movement.FleeSpeed
		setSpeed(entity, speed)
		entity._fleeTimer = 0
		entity:_beginFlee()
	end,

	OnUpdate = function(entity, dt)
		entity._fleeTimer += dt

		-- Update speed each frame (Scared may change it due to freeze/trip)
		local speed = entity.Personality:GetFleeSpeed() or Config.Movement.FleeSpeed
		setSpeed(entity, speed)

		-- Exit Flee only when BOTH conditions are clear:
		-- 1. HP is no longer critically low
		-- 2. Personality no longer forcing flee
		local hpOk = not entity:_shouldFlee()
		local personalityOk = not entity.Personality:ShouldForceFlee()

		if hpOk and personalityOk then
			entity.FSM:Transition("Idle")
			return
		end

		if entity._fleeTimer >= 3 then
			entity._fleeTimer = 0
			entity:_beginFlee()
		end
	end,

	OnExit = function(entity)
		entity.Pathfinder:Stop()
		entity._fleeTimer = 0
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