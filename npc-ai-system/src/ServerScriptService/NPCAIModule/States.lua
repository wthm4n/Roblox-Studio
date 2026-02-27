--[[
	States.lua
	Defines all FSM states for the NPC.
	Each state is a table with Name, OnEnter, OnExit, OnUpdate.
	The `entity` passed into each callback is the NPCController instance.
--]]

local Config = require(game.ReplicatedStorage.Shared.Config)

-- ─── Utility ───────────────────────────────────────────────────────────────

local function setSpeed(entity, speed: number)
	if entity.Humanoid then
		entity.Humanoid.WalkSpeed = speed
	end
end

local function distanceTo(entity, pos: Vector3): number
	return (entity.RootPart.Position - pos).Magnitude
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

		-- Transition: target found → Chase
		if entity.TargetSys.CurrentTarget then
			entity.FSM:Transition("Chase")
			return
		end

		-- After a short idle, begin patrolling
		if entity._idleTimer >= 1.5 then
			entity.FSM:Transition("Patrol")
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
		entity._patrolWaiting  = false
		entity._patrolWaitTimer = 0
		entity._patrolIndex    = entity._patrolIndex or 1
		entity:_beginNextPatrol()
	end,

	OnUpdate = function(entity, dt)
		-- Transition: target found → Chase
		if entity.TargetSys.CurrentTarget then
			entity.FSM:Transition("Chase")
			return
		end

		-- Flee if low health
		if entity:_shouldFlee() then
			entity.FSM:Transition("Flee")
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
		setSpeed(entity, Config.Movement.ChaseSpeed)
		entity._chaseRecalcTimer = 0
	end,

	OnUpdate = function(entity, dt)
		local target, lastKnown = entity.TargetSys.CurrentTarget, entity.TargetSys.LastKnownPos

		-- Lost target entirely
		if not target and not lastKnown then
			entity.FSM:Transition("Idle")
			return
		end

		-- Flee if low health
		if entity:_shouldFlee() then
			entity.FSM:Transition("Flee")
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

		-- In attack range → Attack
		if distanceTo(entity, targetPos) <= Config.Combat.AttackRange then
			entity.FSM:Transition("Attack")
			return
		end

		-- Recalculate path periodically toward target
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
		-- Face the target immediately
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
		local target = entity.TargetSys.CurrentTarget

		-- Target gone → Idle
		if not target or not target.Character then
			entity.FSM:Transition("Idle")
			return
		end

		-- Flee if low health
		if entity:_shouldFlee() then
			entity.FSM:Transition("Flee")
			return
		end

		local root = target.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			entity.FSM:Transition("Chase")
			return
		end

		local dist = distanceTo(entity, root.Position)

		-- Target moved out of attack range → Chase
		if dist > Config.Combat.AttackRange + 2 then -- +2 hysteresis buffer
			entity.FSM:Transition("Chase")
			return
		end

		-- Perform attack on cooldown
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
		setSpeed(entity, Config.Movement.FleeSpeed)
		entity._fleeTimer = 0
		entity:_beginFlee()
	end,

	OnUpdate = function(entity, dt)
		entity._fleeTimer += dt

		-- Recovered enough → go back to Idle
		local hum = entity.Humanoid
		if hum and hum.Health / hum.MaxHealth >= Config.Combat.FleeHealthPercent + 0.15 then
			entity.FSM:Transition("Idle")
			return
		end

		-- Re-pick flee destination every few seconds
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
