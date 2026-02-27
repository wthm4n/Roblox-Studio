--[[
	NPCController.lua
	Fixed:
	  - _setupDamageTracking no longer calls TargetSys:RegisterThreat directly.
	    That was the root cause of Passive/Scared chasing — it was writing
	    nearby players into the threat table even without being hit, which
	    caused TargetSys to unignore and track them.
	  - RegisterThreat is now ONLY called by Personality:OnDamaged, so each
	    personality fully controls whether a threat is registered.
	  - Passive and Scared never call RegisterThreat, so their TargetSys
	    stays blind unless the personality explicitly unignores someone.

	Phase 6 additions:
	  - Debug label now shows squad ID, leader crown (★), and formation slot.
	  - _squadOffset field used by SquadBehavior for formation positioning.
--]]

local RunService = game:GetService("RunService")

local StateMachine          = require(game.ReplicatedStorage.Shared.StateMachine)
local Config                = require(game.ReplicatedStorage.Shared.Config)
local PathfindingController = require(game.ServerScriptService.NPCAIModule.PathfindingController)
local TargetSystem          = require(game.ServerScriptService.NPCAIModule.TargetSystem)
local AnimationController   = require(game.ServerScriptService.NPCAIModule.AnimationController)
local States                = require(game.ServerScriptService.NPCAIModule.States)
local PersonalityManager    = require(game.ServerScriptService.NPCAIModule.PersonalityManager)

local NPCController = {}
NPCController.__index = NPCController

local function makeStateLabel(npc: Model): BillboardGui?
	if not Config.Debug.Enabled or not Config.Debug.ShowStateLabel then return nil end
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	if not root then return nil end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 220, 0, 50)
	gui.StudsOffset = Vector3.new(0, 4, 0)
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextScaled = false
	label.Text = "..."
	label.Parent = gui
	gui.Parent = root
	return gui
end

function NPCController.new(npc: Model, patrolPoints: { BasePart | Vector3 }?)
	local self = setmetatable({}, NPCController)

	self.NPC      = npc
	self.Humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.RootPart = npc:FindFirstChild("HumanoidRootPart") :: BasePart

	assert(self.Humanoid, "[NPCController] No Humanoid in " .. npc.Name)
	assert(self.RootPart, "[NPCController] No HumanoidRootPart in " .. npc.Name)

	self.Pathfinder  = PathfindingController.new(npc)
	self.TargetSys   = TargetSystem.new(npc)
	self.Anim        = AnimationController.new(npc)
	self.Personality = PersonalityManager.create(self)

	-- Squad offset — written by SquadBehavior, read by SquadBehavior formation logic
	self._squadOffset = Vector3.zero

	self._patrolPoints = patrolPoints or {}
	self._patrolIndex  = 1

	self.FSM = StateMachine.new(self, {
		Idle   = States.Idle,
		Patrol = States.Patrol,
		Chase  = States.Chase,
		Attack = States.Attack,
		Flee   = States.Flee,
	}, "Idle")

	self._stateLabel  = makeStateLabel(npc)
	self._connections = {}
	self._prevTarget  = nil
	self._prevState   = "Idle"
	self._coneParts   = Config.Debug.Enabled and Config.Debug.ShowSightCone and self:_createConeParts() or nil
	self._coneTimer   = 0

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

function NPCController:Destroy()
	for _, c in ipairs(self._connections) do c:Disconnect() end
	self._connections = {}
	self.Pathfinder:Destroy()
	self.TargetSys:Destroy()
	self.Anim:Destroy()
	self.Personality:Destroy()
	if self._stateLabel then self._stateLabel:Destroy() end
	if self._coneParts then
		for _, p in ipairs(self._coneParts) do p:Destroy() end
		self._coneParts = nil
	end
end

function NPCController:_update(dt: number)
	if not self.NPC.Parent then self:Destroy() return end

	self.TargetSys:Update(dt)
	self.Pathfinder:Update(dt)
	self.FSM:Update(dt)

	-- Notify personality of state changes (safe — outside FSM lock)
	local currentState = self.FSM:GetState()
	if currentState ~= self._prevState then
		self.Personality:OnStateChanged(currentState, self._prevState)
		self._prevState = currentState
	end

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

	self.Personality:OnUpdate(dt)
	self:_updateLocomotionAnim()
	self:_updateSightCone(dt)

	-- ── Debug label ────────────────────────────────────────────────────────
	if self._stateLabel then
		local label = self._stateLabel:FindFirstChildOfClass("TextLabel")
		if label then
			local pName   = self.Personality.Name ~= "None"
				and (" [" .. self.Personality.Name .. "]") or ""
			local role    = self.NPC:GetAttribute("TacticalRole")
			local roleStr = role and (" · " .. role) or ""

			-- Squad info
			local squadId   = self.NPC:GetAttribute("SquadId")
			local isLeader  = self.NPC:GetAttribute("SquadLeader") == true
			local slot      = self.NPC:GetAttribute("FormationSlot")
			local squadStr  = ""
			if squadId then
				local short   = string.sub(squadId, -5)  -- last 5 chars of ID
				local crown   = isLeader and "★ " or ""
				local slotStr = slot and ("#" .. tostring(slot)) or ""
				squadStr = (" | " .. crown .. short .. slotStr)
			end

			label.Text = currentState .. pName .. roleStr .. squadStr
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

function NPCController:_shouldFlee(): boolean
	return self.Humanoid.Health / self.Humanoid.MaxHealth < Config.Combat.FleeHealthPercent
end

function NPCController:_performAttack(target: Player)
	if not target.Character then return end
	local hum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	if not hum or hum.Health <= 0 then return end
	local track = self.Anim:PlayAction("Attack")
	if track then
		local halfTime = math.max(track.Length * 0.4, 0.3)
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
		if root then awayDir = (self.RootPart.Position - root.Position).Unit end
	end
	self.Pathfinder:MoveTo(self.RootPart.Position + awayDir * Config.Patrol.WanderRadius)
end

function NPCController:_setupDamageTracking()
	local lastHp = self.Humanoid.Health
	local hpConn = self.Humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		local newHp  = self.Humanoid.Health
		local damage = lastHp - newHp
		lastHp = newHp
		if damage <= 0 then return end

		self.Anim:PlayAction("Hurt")

		-- Find the closest player to attribute damage to
		local Players = game:GetService("Players")
		local closest, closestDist = nil, math.huge
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

		-- CRITICAL FIX: Do NOT call TargetSys:RegisterThreat here.
		-- RegisterThreat writes into _threatTable which causes TargetSys to
		-- track the player even if they're on the ignore list — because
		-- _selectBestTarget picks the highest threat regardless of ignore.
		-- Instead, let Personality:OnDamaged decide whether to register
		-- a threat. Aggressive will; Passive and Scared will not.
		local attacker = (closest and closestDist < 20) and closest or nil
		self.Personality:OnDamaged(damage, attacker)
	end)
	table.insert(self._connections, hpConn)
end

function NPCController:_onDied()
	self.Pathfinder:Stop()
	self.Anim:OnDeath()
	task.delay(5, function() self:Destroy() end)
end

-- ─── Sight Cone Debug ─────────────────────────────────────────────────────

--[[
	Draws the sight cone as a fan of thin wedge parts in the _NPCDebug folder.
	Segments = 8 wedges covering the full FOV angle.
	Color changes: grey = idle/no target, green = has target, red = in attack range.
	Updates at 15fps (every 0.066s) to avoid per-frame part moves being expensive.
--]]

local CONE_SEGMENTS  = 8
local CONE_UPDATE_HZ = 0.066  -- ~15fps for cone updates

function NPCController:_createConeParts()
	local folder = workspace:FindFirstChild("_NPCDebug")
		or (function()
			local f = Instance.new("Folder")
			f.Name = "_NPCDebug"
			f.Parent = workspace
			return f
		end)()

	local sub = Instance.new("Folder")
	sub.Name   = "Cone_" .. self.NPC.Name
	sub.Parent = folder

	local parts = {}
	for i = 1, CONE_SEGMENTS do
		local w = Instance.new("WedgePart")
		w.Anchored    = true
		w.CanCollide  = false
		w.CastShadow  = false
		w.Material    = Enum.Material.Neon
		w.Transparency = 0.9
		w.Color 	   = Color3.fromRGB(165, 0, 3)
		w.Size         = Vector3.new(0.1, 0.1, 0.1)
		w.Parent       = sub
		table.insert(parts, w)
	end
	self._coneFolder = sub
	return parts
end

function NPCController:_updateSightCone(dt: number)
	if not self._coneParts then return end

	self._coneTimer += dt
	if self._coneTimer < CONE_UPDATE_HZ then return end
	self._coneTimer = 0

	local root      = self.RootPart
	local origin    = root.Position + Vector3.new(0, 0.5, 0)
	local lookVec   = root.CFrame.LookVector
	local range     = Config.Detection.SightRange
	local halfAngle = math.rad(Config.Detection.SightAngle / 2)

	-- Color: red if attacking, green if has target, grey otherwise
	local state  = self.FSM:GetState()
	local hasTarget = self.TargetSys.CurrentTarget ~= nil
	local color
	if state == "Attack" then
		color = Config.Debug.SightConeColorAlert or Color3.fromRGB(255, 50, 50)
	elseif hasTarget then
		color = Config.Debug.SightConeColorTarget or Color3.fromRGB(80, 255, 80)
	else
		color = Config.Debug.SightConeColor or Color3.fromRGB(165, 0, 3)
	end

	local segAngle = (halfAngle * 2) / CONE_SEGMENTS

	for i, part in ipairs(self._coneParts) do
		-- Angle of the LEFT edge of this segment
		local leftAngle  = -halfAngle + (i - 1) * segAngle
		local rightAngle = leftAngle + segAngle
		local midAngle   = (leftAngle + rightAngle) / 2

		-- Direction of this segment (rotated around Y)
		local cosM, sinM = math.cos(midAngle), math.sin(midAngle)
		local dir = Vector3.new(
			lookVec.X * cosM - lookVec.Z * sinM,
			0,
			lookVec.X * sinM + lookVec.Z * cosM
		).Unit

		-- Wedge: length = range, width = 2 * range * tan(segAngle/2)
		local segWidth = 2 * range * math.tan(segAngle / 2)
		part.Size  = Vector3.new(segWidth, 0.15, range)
		part.Color = color

		-- WedgePart tapers toward its local -Z (the pointed end is at -Z).
		-- We want the tip at the NPC and the wide base at range distance.
		-- So: place center at origin + dir*(range/2), face dir (base forward).
		local midPos = origin + dir * (range / 2)
		part.CFrame  = CFrame.lookAt(midPos, midPos + dir)
	end
end

return NPCController