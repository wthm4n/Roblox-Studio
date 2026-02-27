--[[
	NPCController.lua
	The main "brain" of each NPC.
	Wires together:
	  - StateMachine
	  - PathfindingController
	  - TargetSystem
	  - State definitions
	
	Usage (from NPCSpawner or manually):
		local NPCController = require(path.to.NPCController)
		local brain = NPCController.new(npcModel, patrolPoints)
		-- brain updates itself via RunService
		-- brain:Destroy() to clean up
--]]

local RunService = game:GetService("RunService")

local StateMachine          = require(game.ReplicatedStorage.Shared.StateMachine)
local Config                = require(game.ReplicatedStorage.Shared.Config)
local PathfindingController = require(game.ServerScriptService.NPCAIModule.PathfindingController)
local TargetSystem          = require(game.ServerScriptService.NPCAIModule.TargetSystem)
local States                = require(game.ServerScriptService.NPCAIModule.States)

local NPCController = {}
NPCController.__index = NPCController

-- ─── Debug label ───────────────────────────────────────────────────────────

local function makeStateLabel(npc: Model): BillboardGui?
	if not Config.Debug.Enabled or not Config.Debug.ShowStateLabel then return nil end

	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return nil end

	local gui   = Instance.new("BillboardGui")
	gui.Size    = UDim2.new(0, 120, 0, 30)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = false

	local label = Instance.new("TextLabel")
	label.Size            = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3      = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font            = Enum.Font.GothamBold
	label.TextSize        = 14
	label.Text            = "Idle"
	label.Parent          = gui

	gui.Parent = root
	return gui
end

-- ─── Constructor ───────────────────────────────────────────────────────────

--[[
	@param npc           Model — the NPC character
	@param patrolPoints  { BasePart | Vector3 }? — optional patrol waypoints
--]]
function NPCController.new(npc: Model, patrolPoints: { BasePart | Vector3 }?)
	local self = setmetatable({}, NPCController)

	self.NPC        = npc
	self.Humanoid   = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.RootPart   = npc:FindFirstChild("HumanoidRootPart") :: BasePart

	assert(self.Humanoid, "[NPCController] No Humanoid found in " .. npc.Name)
	assert(self.RootPart, "[NPCController] No HumanoidRootPart found in " .. npc.Name)

	-- Sub-systems
	self.Pathfinder = PathfindingController.new(npc)
	self.TargetSys  = TargetSystem.new(npc)

	-- Patrol data
	self._patrolPoints = patrolPoints or {}
	self._patrolIndex  = 1

	-- State machine
	self.FSM = StateMachine.new(self, {
		Idle   = States.Idle,
		Patrol = States.Patrol,
		Chase  = States.Chase,
		Attack = States.Attack,
		Flee   = States.Flee,
	}, "Idle")

	-- Debug label
	self._stateLabel = makeStateLabel(npc)

	-- Wire damage detection
	self._connections = {}
	self:_setupDamageTracking()

	-- Main update loop
	local updateConn = RunService.Heartbeat:Connect(function(dt)
		self:_update(dt)
	end)
	table.insert(self._connections, updateConn)

	-- Clean up on NPC death
	local diedConn = self.Humanoid.Died:Connect(function()
		self:_onDied()
	end)
	table.insert(self._connections, diedConn)

	return self
end

-- ─── Public ────────────────────────────────────────────────────────────────

function NPCController:Destroy()
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	self._connections = {}
	self.Pathfinder:Destroy()
	self.TargetSys:Destroy()
	if self._stateLabel then
		self._stateLabel:Destroy()
	end
end

-- ─── Private update ────────────────────────────────────────────────────────

function NPCController:_update(dt: number)
	if not self.NPC.Parent then
		self:Destroy()
		return
	end

	-- Update target system
	self.TargetSys:Update(dt)

	-- Update pathfinder each frame
	self.Pathfinder:Update(dt)

	-- Tick FSM
	self.FSM:Update(dt)

	-- Sync debug label
	if self._stateLabel then
		local label = self._stateLabel:FindFirstChildOfClass("TextLabel")
		if label then
			label.Text = "[ " .. self.FSM:GetState() .. " ]"
		end
	end
end

-- ─── Helpers called by States ──────────────────────────────────────────────

function NPCController:_shouldFlee(): boolean
	return self.Humanoid.Health / self.Humanoid.MaxHealth < Config.Combat.FleeHealthPercent
end

function NPCController:_performAttack(target: Player)
	if not target.Character then return end
	local hum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	if hum and hum.Health > 0 then
		hum:TakeDamage(Config.Combat.Damage)
	end

	-- Play attack animation if present
	local anim = self.NPC:FindFirstChild("AttackAnim") :: Animation
	if anim and self.Humanoid then
		local track = self.Humanoid.Animator:LoadAnimation(anim)
		track:Play()
	end
end

function NPCController:_beginNextPatrol()
	if #self._patrolPoints == 0 then
		-- No patrol points: random wander
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
	else
		return
	end

	self.Pathfinder:MoveTo(dest, function()
		self._patrolWaiting   = true
		self._patrolWaitTimer = 0
		-- Advance index (loop)
		self._patrolIndex = (self._patrolIndex % #self._patrolPoints) + 1
	end)
end

function NPCController:_beginFlee()
	-- Pick a point directly away from the nearest threat
	local target = self.TargetSys.CurrentTarget
	local awayDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit

	if target and target.Character then
		local root = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			awayDir = (self.RootPart.Position - root.Position).Unit
		end
	end

	local fleePos = self.RootPart.Position + awayDir * Config.Patrol.WanderRadius
	self.Pathfinder:MoveTo(fleePos)
end

-- ─── Damage tracking ───────────────────────────────────────────────────────

function NPCController:_setupDamageTracking()
	-- Track HP changes and attribute attackers as threats
	local lastHp = self.Humanoid.Health

	local hpConn = self.Humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		local newHp   = self.Humanoid.Health
		local damage  = lastHp - newHp
		lastHp        = newHp

		if damage <= 0 then return end

		-- Try to attribute to closest player (simple heuristic)
		-- For proper attribution, use a custom damage system that passes attacker
		local closest     = nil
		local closestDist = math.huge

		local Players = game:GetService("Players")
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
			if root then
				local dist = (self.RootPart.Position - root.Position).Magnitude
				if dist < closestDist then
					closestDist = dist
					closest = player
				end
			end
		end

		if closest and closestDist < 20 then
			self.TargetSys:RegisterThreat(closest, damage)
		end
	end)

	table.insert(self._connections, hpConn)
end

-- ─── Death ─────────────────────────────────────────────────────────────────

function NPCController:_onDied()
	self.Pathfinder:Stop()
	-- Let the spawner handle respawn; just clean up connections here
	task.delay(5, function()
		self:Destroy()
	end)
end

return NPCController
