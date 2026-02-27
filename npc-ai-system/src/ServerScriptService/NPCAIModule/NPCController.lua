--[[
	NPCController.lua
	Main NPC brain — wires together:
	  StateMachine + PathfindingController + TargetSystem + AnimationController + Personality
--]]

local RunService = game:GetService("RunService")

local StateMachine          = require(game.ReplicatedStorage.Shared.StateMachine)
local Config                = require(game.ReplicatedStorage.Shared.Config)
local PathfindingController = require(game.ServerScriptService.NPCAIModule.PathfindingController)
local TargetSystem          = require(game.ServerScriptService.NPCAIModule.TargetSystem)
local AnimationController   = require(game.ServerScriptService.NPCAIModule.AnimationController)
local States                = require(game.ServerScriptService.NPCAIModule.States)
local PersonalityManager    = require(game.ServerScriptService.NPCAIModule.Personalities.PersonalityManager)

local NPCController = {}
NPCController.__index = NPCController

-- ─── Debug label ───────────────────────────────────────────────────────────

local function makeStateLabel(npc: Model): BillboardGui?
	if not Config.Debug.Enabled or not Config.Debug.ShowStateLabel then return nil end
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return nil end

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 180, 0, 40)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.Text = "..."
	label.Parent = gui

	gui.Parent = root
	return gui
end

-- ─── Constructor ───────────────────────────────────────────────────────────

function NPCController.new(npc: Model, patrolPoints: { BasePart | Vector3 }?)
	local self = setmetatable({}, NPCController)

	self.NPC        = npc
	self.Humanoid   = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.RootPart   = npc:FindFirstChild("HumanoidRootPart") :: BasePart

	assert(self.Humanoid,  "[NPCController] No Humanoid in "         .. npc.Name)
	assert(self.RootPart,  "[NPCController] No HumanoidRootPart in " .. npc.Name)

	-- Core sub-systems
	self.Pathfinder = PathfindingController.new(npc)
	self.TargetSys  = TargetSystem.new(npc)
	self.Anim       = AnimationController.new(npc)

	-- Personality layer (created AFTER core systems so it can reference them)
	self.Personality = PersonalityManager.create(self)

	-- Patrol
	self._patrolPoints = patrolPoints or {}
	self._patrolIndex  = 1

	-- Hook FSM so personality gets state change callbacks
	self.FSM = StateMachine.new(self, {
		Idle   = States.Idle,
		Patrol = States.Patrol,
		Chase  = States.Chase,
		Attack = States.Attack,
		Flee   = States.Flee,
	}, "Idle")

	-- Wrap FSM transition to notify personality
	local originalTransition = self.FSM.Transition
	self.FSM.Transition = function(fsm, newState)
		local oldState = fsm:GetState()
		originalTransition(fsm, newState)
		self.Personality:OnStateChanged(newState, oldState)
	end

	self._stateLabel  = makeStateLabel(npc)
	self._connections = {}
	self._prevTarget  = nil

	self:_setupDamageTracking()

	local updateConn = RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)
	table.insert(self._connections, updateConn)

	local diedConn = self.Humanoid.Died:Connect(function()
		self:_onDied()
	end)
	table.insert(self._connections, diedConn)

	return self
end

-- ─── Public ────────────────────────────────────────────────────────────────

function NPCController:Destroy()
	for _, c in ipairs(self._connections) do c:Disconnect() end
	self._connections = {}
	self.Pathfinder:Destroy()
	self.TargetSys:Destroy()
	self.Anim:Destroy()
	self.Personality:Destroy()
	if self._stateLabel then self._stateLabel:Destroy() end
end

-- ─── Private update ────────────────────────────────────────────────────────

function NPCController:_update(dt: number)
	if not self.NPC.Parent then self:Destroy() return end

	-- Core systems
	self.TargetSys:Update(dt)
	self.Pathfinder:Update(dt)
	self.FSM:Update(dt)

	-- Notify personality of target changes
	local currentTarget = self.TargetSys.CurrentTarget
	if currentTarget ~= self._prevTarget then
		if currentTarget then
			self.Personality:OnTargetFound(currentTarget)
		else
			self.Personality:OnTargetLost()
		end
		self._prevTarget = currentTarget
	end

	-- Personality gets its own update tick
	self.Personality:OnUpdate(dt)

	-- Locomotion animation
	self:_updateLocomotionAnim()

	-- Debug label
	if self._stateLabel then
		local label = self._stateLabel:FindFirstChildOfClass("TextLabel")
		if label then
			local personality = self.Personality.Name ~= "None"
				and (" [" .. self.Personality.Name .. "]") or ""
			local role = self.NPC:GetAttribute("TacticalRole")
			local roleStr = role and (" · " .. role) or ""
			label.Text = self.FSM:GetState() .. personality .. roleStr
		end
	end
end

function NPCController:_updateLocomotionAnim()
	local state = self.FSM:GetState()
	if state == "Attack" then return end

	local vel   = self.RootPart.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	local waterResult = workspace:Raycast(self.RootPart.Position, Vector3.new(0, 3, 0))
	local inWater = (self.RootPart.Position.Y < 0) and (waterResult == nil)

	if inWater then
		self.Anim:SetLocomotion("swim")
	elseif state == "Chase" or state == "Flee" then
		self.Anim:SetLocomotion(speed > 0.5 and "run" or "idle")
	elseif state == "Patrol" then
		self.Anim:SetLocomotion(speed > 0.5 and "walk" or "idle")
	else
		self.Anim:SetLocomotion("idle")
	end
end

-- ─── Helpers called by States ──────────────────────────────────────────────

function NPCController:_shouldFlee(): boolean
	return self.Humanoid.Health / self.Humanoid.MaxHealth < Config.Combat.FleeHealthPercent
end

function NPCController:_performAttack(target: Player)
	if not target.Character then return end
	local hum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	if not hum or hum.Health <= 0 then return end

	local track = self.Anim:PlayAction("Attack")
	if track then
		local halfTime = track.Length * 0.4
		if halfTime <= 0 then halfTime = 0.3 end
		task.delay(halfTime, function()
			if hum and hum.Health > 0 then
				hum:TakeDamage(Config.Combat.Damage)
			end
		end)
	else
		hum:TakeDamage(Config.Combat.Damage)
	end
end

function NPCController:_beginNextPatrol()
	if #self._patrolPoints == 0 then
		if Config.Patrol.RandomWander then
			local angle  = math.random() * math.pi * 2
			local radius = math.random(5, Config.Patrol.WanderRadius)
			local dest   = self.RootPart.Position
				+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			self.Pathfinder:MoveTo(dest, function()
				self._patrolWaiting = true
			end)
		end
		return
	end

	local point = self._patrolPoints[self._patrolIndex]
	local dest: Vector3

	if typeof(point) == "Instance" and point:IsA("BasePart") then
		dest = point.Position
	elseif typeof(point) == "Vector3" then
		dest = point
	else return end

	self.Pathfinder:MoveTo(dest, function()
		self._patrolWaiting   = true
		self._patrolWaitTimer = 0
		self._patrolIndex     = (self._patrolIndex % #self._patrolPoints) + 1
	end)
end

function NPCController:_beginFlee()
	local awayDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
	local target  = self.TargetSys.CurrentTarget

	if target and target.Character then
		local root = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			awayDir = (self.RootPart.Position - root.Position).Unit
		end
	end

	self.Pathfinder:MoveTo(self.RootPart.Position + awayDir * Config.Patrol.WanderRadius)
end

-- ─── Damage tracking ───────────────────────────────────────────────────────

function NPCController:_setupDamageTracking()
	local lastHp = self.Humanoid.Health

	local hpConn = self.Humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		local newHp  = self.Humanoid.Health
		local damage = lastHp - newHp
		lastHp = newHp
		if damage <= 0 then return end

		self.Anim:PlayAction("Hurt")

		-- Find attacker
		local Players     = game:GetService("Players")
		local closest, closestDist = nil, math.huge
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
			if root then
				local dist = (self.RootPart.Position - root.Position).Magnitude
				if dist < closestDist then closestDist = dist; closest = player end
			end
		end

		if closest and closestDist < 20 then
			self.TargetSys:RegisterThreat(closest, damage)
			self.Personality:OnDamaged(damage, closest)  -- ← notify personality
		else
			self.Personality:OnDamaged(damage, nil)
		end
	end)

	table.insert(self._connections, hpConn)
end

-- ─── Death ─────────────────────────────────────────────────────────────────

function NPCController:_onDied()
	self.Pathfinder:Stop()
	self.Anim:OnDeath()
	task.delay(5, function() self:Destroy() end)
end

return NPCController
