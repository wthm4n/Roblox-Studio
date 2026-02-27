--[[
	States.lua

	Fix: Chase and Attack states now check entity.Personality:CanEnterCombat()
	before transitioning. This stops Scared/Passive NPCs from ever entering
	combat states — no task.defer races, no transition loops, no flood.
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

		if entity.TargetSys.CurrentTarget then
			if entity.Personality:CanEnterCombat() then
				entity.FSM:Transition("Chase")
			else
				entity.FSM:Transition("Flee")
			end
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
		if entity.TargetSys.CurrentTarget then
			if entity.Personality:CanEnterCombat() then
				entity.FSM:Transition("Chase")
			else
				entity.FSM:Transition("Flee")
			end
			return
		end

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
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Flee")
			return
		end
		setSpeed(entity, Config.Movement.ChaseSpeed)
		entity._chaseRecalcTimer = 0
	end,

	OnUpdate = function(entity, dt)
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Flee")
			return
		end

		local target, lastKnown = entity.TargetSys.CurrentTarget, entity.TargetSys.LastKnownPos

		if not target and not lastKnown then
			entity.FSM:Transition("Idle")
			return
		end

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
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Flee")
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
		if not entity.Personality:CanEnterCombat() then
			entity.FSM:Transition("Flee")
			return
		end

		local target = entity.TargetSys.CurrentTarget

		if not target or not target.Character then
			entity.FSM:Transition("Idle")
			return
		end

		if entity:_shouldFlee() then
			entity.FSM:Transition("Flee")
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
		setSpeed(entity, Config.Movement.FleeSpeed)
		entity._fleeTimer = 0
		local hum = entity.Humanoid
		entity._fleeIsHPTriggered = hum and
			(hum.Health / hum.MaxHealth) < Config.Combat.FleeHealthPercent
		entity:_beginFlee()
	end,

	OnUpdate = function(entity, dt)
		entity._fleeTimer += dt

		-- Only auto-exit Flee if it was triggered by low HP and HP recovered
		-- Personality-driven Flee (Scared/Passive at full HP) never auto-exits
		if entity._fleeIsHPTriggered then
			local hum = entity.Humanoid
			if hum and hum.Health / hum.MaxHealth >= Config.Combat.FleeHealthPercent + 0.15 then
				entity._fleeIsHPTriggered = false
				entity.FSM:Transition("Idle")
				return
			end
		end

		if entity._fleeTimer >= 3 then
			entity._fleeTimer = 0
			entity:_beginFlee()
		end
	end,

	OnExit = function(entity)
		entity.Pathfinder:Stop()
		entity._fleeTimer = 0
		entity._fleeIsHPTriggered = false
	end,
}

return {
	Idle   = Idle,
	Patrol = Patrol,
	Chase  = Chase,
	Attack = Attack,
	Flee   = Flee,
}