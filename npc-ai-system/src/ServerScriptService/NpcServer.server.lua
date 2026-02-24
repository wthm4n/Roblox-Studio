--[[
	NPCService.lua
	Main module — require this from your ServerScript
	
	Usage:
		local NPCService = require(path.to.NPCService)
		local npc = NPCService.new(npcModel, config)
		npc:Start()
--]]

local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")

-- Sub-modules (place these in the same folder)
local BehaviorModule = require(script.Parent.BehaviorModule)
local MovementModule = require(script.Parent.MovementModule)
local SensorModule   = require(script.Parent.SensorModule)
local StateModule    = require(script.Parent.StateModule)

-- ─────────────────────────────────────────────
--  DEFAULT CONFIG  (override per-NPC in config)
-- ─────────────────────────────────────────────
local DEFAULT_CONFIG = {
	-- Behavior
	defaultState        = "passive",   -- "passive" | "aggressive" | "scared" | "patrol"
	dynamicBehavior     = true,        -- allow state to change at runtime

	-- Ranges (studs)
	aggroRange          = 30,
	fleeRange           = 20,
	attackRange         = 5,
	waypointReachedDist = 3,

	-- Stats
	maxHealth           = 100,
	attackDamage        = 10,
	attackCooldown      = 1.5,         -- seconds
	moveSpeed           = 16,
	runSpeed            = 24,
	swimSpeed           = 10,
	climbSpeed          = 8,
	crawlSpeed          = 6,

	-- Wander
	wanderRadius        = 20,
	wanderInterval      = { 4, 8 },    -- random between these seconds

	-- Patrol
	patrolWaypoints     = {},          -- Vector3 list; set in config
	patrolLoop          = true,

	-- Pathfinding costs (higher = avoid)
	agentRadius         = 2,
	agentHeight         = 5,
	agentCanJump        = true,
	agentCanClimb       = true,
	materialCosts       = {
		[Enum.Material.Water]     = 5,
		[Enum.Material.Sand]      = 2,
		[Enum.Material.Mud]       = 3,
		[Enum.Material.Ice]       = 2,
		-- NOTE: Lava avoidance is handled via KillPart detection in SensorModule
		-- not via material cost (Enum.Material.Lava does not exist in Roblox)
	},

	-- Health-based dynamic behavior thresholds (% of maxHealth)
	fearHealthThreshold = 0.3,         -- flee when HP < 30%

	-- Debug
	debugMode           = false,
}

-- ─────────────────────────────────────────────
--  NPC CLASS
-- ─────────────────────────────────────────────
local NPCService = {}
NPCService.__index = NPCService

function NPCService.new(model: Model, config: table?)
	assert(model and model:IsA("Model"), "[NPCService] model must be a Model")
	assert(model.PrimaryPart, "[NPCService] model must have a PrimaryPart (HumanoidRootPart)")
	assert(model:FindFirstChildOfClass("Humanoid"), "[NPCService] model must have a Humanoid")

	local cfg = {}
	for k, v in pairs(DEFAULT_CONFIG) do cfg[k] = v end
	if config then
		for k, v in pairs(config) do cfg[k] = v end
	end

	local self = setmetatable({}, NPCService)

	-- Core refs
	self.Model     = model
	self.HRP       = model.PrimaryPart
	self.Humanoid  = model:FindFirstChildOfClass("Humanoid")
	self.Config    = cfg
	self.Animator  = MovementModule.SetupAnimator(model)

	-- Runtime state
	self.State          = StateModule.new(cfg.defaultState)
	self.Target         = nil     -- Player | nil
	self.Alive          = true
	self._connections   = {}
	self._attackTimer   = 0
	self._wanderTimer   = 0
	self._patrolIndex   = 1
	self._currentPath   = nil
	self._moving        = false

	-- Init sub-systems
	self.Sensor    = SensorModule.new(self)
	self.Behavior  = BehaviorModule.new(self)
	self.Movement  = MovementModule.new(self)

	-- Humanoid setup
	self.Humanoid.MaxHealth = cfg.maxHealth
	self.Humanoid.Health    = cfg.maxHealth
	self.Humanoid.WalkSpeed = cfg.moveSpeed
	self.Humanoid.AutoJumpEnabled = cfg.agentCanJump

	return self
end

-- ─────────────────────────────────────────────
--  LIFECYCLE
-- ─────────────────────────────────────────────

function NPCService:Start()
	assert(self.Alive, "[NPCService] Cannot start a dead NPC")

	-- Death handler
	local deadConn = self.Humanoid.Died:Connect(function()
		self:_onDeath()
	end)
	table.insert(self._connections, deadConn)

	-- Damage → possible flee trigger
	local healthConn = self.Humanoid.HealthChanged:Connect(function(hp)
		self:_onHealthChanged(hp)
	end)
	table.insert(self._connections, healthConn)

	-- Main loop
	local loopConn = RunService.Heartbeat:Connect(function(dt)
		if not self.Alive then return end
		self:_tick(dt)
	end)
	table.insert(self._connections, loopConn)

	if self.Config.debugMode then
		print(("[NPCService] Started NPC: %s | State: %s"):format(self.Model.Name, self.State:Get()))
	end
end

function NPCService:Stop()
	self.Alive = false
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
	if self.Movement then
		self.Movement:Destroy()
	end
end

function NPCService:Destroy()
	self:Stop()
	self.Model:Destroy()
end

-- ─────────────────────────────────────────────
--  MAIN TICK
-- ─────────────────────────────────────────────

function NPCService:_tick(dt)
	-- 1. Update sensors (find nearest player, detect environment)
	self.Sensor:Update()

	-- 2. Evaluate + possibly change state
	if self.Config.dynamicBehavior then
		self.Behavior:Evaluate()
	end

	-- 3. Execute current state behavior
	local state = self.State:Get()

	if state == "aggressive" then
		self:_tickAggressive(dt)
	elseif state == "scared" then
		self:_tickScared(dt)
	elseif state == "passive" then
		self:_tickPassive(dt)
	elseif state == "patrol" then
		self:_tickPatrol(dt)
	end

	-- 4. Update movement animations
	self.Movement:UpdateAnimations(state)
end

-- ─────────────────────────────────────────────
--  STATE BEHAVIORS
-- ─────────────────────────────────────────────

function NPCService:_tickAggressive(dt)
	local target = self.Target
	if not target or not target.Character then
		self.State:Set("passive")
		return
	end

	local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end

	local dist = (self.HRP.Position - targetHRP.Position).Magnitude

	if dist <= self.Config.attackRange then
		-- Stop moving and attack
		self.Movement:Stop()
		self:_tryAttack(target, dt)
	else
		-- Chase — uses recomputing path tracker
		self.Humanoid.WalkSpeed = self.Config.runSpeed
		self.Movement:Chase(targetHRP.Position)
	end
end

function NPCService:_tickScared(dt)
	local target = self.Target
	if not target or not target.Character then
		self.State:Set("passive")
		return
	end

	local targetHRP = target.Character:FindFirstChild("HumanoidRootPart")
	if not targetHRP then return end

	local dist = (self.HRP.Position - targetHRP.Position).Magnitude

	if dist > self.Config.fleeRange * 2 then
		-- Far enough, calm down
		self.State:Set("passive")
		return
	end

	-- Flee: move in opposite direction of target
	self.Humanoid.WalkSpeed = self.Config.runSpeed
	local fleeDir = (self.HRP.Position - targetHRP.Position).Unit
	local fleeGoal = self.HRP.Position + fleeDir * 30
	self.Movement:Chase(fleeGoal)
end

function NPCService:_tickPassive(dt)
	self._wanderTimer = self._wanderTimer - dt
	if self._wanderTimer <= 0 then
		self.Humanoid.WalkSpeed = self.Config.moveSpeed
		self.Movement:Wander(self.Config.wanderRadius)
		local min, max = self.Config.wanderInterval[1], self.Config.wanderInterval[2]
		self._wanderTimer = math.random() * (max - min) + min
	end
end

function NPCService:_tickPatrol(dt)
	local waypoints = self.Config.patrolWaypoints
	if not waypoints or #waypoints == 0 then
		self:_tickPassive(dt)
		return
	end

	local goal = waypoints[self._patrolIndex]
	local dist = (self.HRP.Position - goal).Magnitude

	if dist <= self.Config.waypointReachedDist then
		-- Advance waypoint
		if self._patrolIndex >= #waypoints then
			if self.Config.patrolLoop then
				self._patrolIndex = 1
			else
				self.State:Set("passive")
				return
			end
		else
			self._patrolIndex = self._patrolIndex + 1
		end
	end

	self.Humanoid.WalkSpeed = self.Config.moveSpeed
	self.Movement:MoveTo(waypoints[self._patrolIndex])
end

-- ─────────────────────────────────────────────
--  COMBAT
-- ─────────────────────────────────────────────

function NPCService:_tryAttack(target, dt)
	self._attackTimer = self._attackTimer - dt
	if self._attackTimer > 0 then return end

	self._attackTimer = self.Config.attackCooldown

	local hum = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		hum:TakeDamage(self.Config.attackDamage)
		self.Movement:PlayAnimation("attack")
		if self.Config.debugMode then
			print(("[NPCService] %s attacked %s for %d dmg"):format(
				self.Model.Name, target.Name, self.Config.attackDamage))
		end
	end
end

-- ─────────────────────────────────────────────
--  EVENT HANDLERS
-- ─────────────────────────────────────────────

function NPCService:_onHealthChanged(hp)
	if not self.Config.dynamicBehavior then return end
	local pct = hp / self.Config.maxHealth
	if pct < self.Config.fearHealthThreshold and self.State:Get() ~= "scared" then
		self.State:Set("scared")
	end
end

function NPCService:_onDeath()
	self.Alive = false
	self.Movement:PlayAnimation("death")
	self:Stop()
	-- Optional: destroy after death anim
	task.delay(3, function()
		if self.Model and self.Model.Parent then
			self.Model:Destroy()
		end
	end)
end

-- ─────────────────────────────────────────────
--  PUBLIC API
-- ─────────────────────────────────────────────

-- Force a state change from outside
function NPCService:SetState(state: string)
	self.State:Set(state)
end

function NPCService:GetState(): string
	return self.State:Get()
end

-- Set patrol waypoints at runtime
function NPCService:SetWaypoints(waypoints: { Vector3 })
	self.Config.patrolWaypoints = waypoints
	self._patrolIndex = 1
end

-- Force target
function NPCService:SetTarget(player)
	self.Target = player
end

return NPCService