-- NPCAIService.lua
-- ModuleScript → Place inside ServerScriptService
-- Usage: local AI = require(NPCAIService).new(npcModel, targetPlayer, settingsTable)

local PathfindingService = game:GetService("PathfindingService")
local RunService          = game:GetService("RunService")
local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")

local NPCAIService = {}
NPCAIService.__index = NPCAIService

--[[
╔══════════════════════════════════════════════════════════════════════╗
║                       DEFAULT SETTINGS                               ║
║  Pass a custom table into .new() to override any of these.           ║
╚══════════════════════════════════════════════════════════════════════╝
]]
NPCAIService.DefaultSettings = {

	-- ┌─ FOLLOW RANGE ──────────────────────────────────────────────────┐
	FollowRange       = 100,   -- studs: NPC starts chasing within this range
	StopDistance      = 4,     -- studs: NPC stops when this close to player
	LoseTargetRange   = 130,   -- studs: NPC gives up chasing past this range

	-- ┌─ SPEEDS ────────────────────────────────────────────────────────┐
	WalkSpeed         = 16,    -- normal follow speed
	RunSpeed          = 28,    -- speed when player is far (past RunThreshold)
	RunThreshold      = 30,    -- studs away to trigger run speed
	CrouchSpeed       = 6,     -- speed while crouching under obstacle
	SwimSpeed         = 10,    -- speed while swimming
	ClimbSpeed        = 8,     -- speed on steep slopes

	-- ┌─ JUMP ──────────────────────────────────────────────────────────┐
	CanJump           = true,
	JumpPower         = 50,

	-- ┌─ SWIM ──────────────────────────────────────────────────────────┐
	CanSwim           = true,
	SwimStrokeRate    = 0.6,   -- seconds between swim strokes (jump pulses)

	-- ┌─ CLIMB ─────────────────────────────────────────────────────────┐
	CanClimb          = true,
	ClimbAngleMin     = 42,    -- degrees of incline to trigger climb mode

	-- ┌─ CROUCH ────────────────────────────────────────────────────────┐
	CanCrouch         = true,
	CrouchTriggerGap  = 4,     -- studs above NPC head that triggers crouch

	-- ┌─ PATHFINDING ───────────────────────────────────────────────────┐
	RecalcRate        = 0.15,  -- seconds between path recalculations
	WaypointRadius    = 3,     -- studs to count a waypoint as reached
	AgentHeight       = 5,
	AgentRadius       = 2,

	-- ┌─ STUCK RECOVERY ────────────────────────────────────────────────┐
	StuckTimeout      = 2.0,   -- seconds motionless before "stuck"
	StuckJumpMax      = 3,     -- jumps before force-repath

	-- ┌─ PATH VISUALIZER ───────────────────────────────────────────────┐
	ShowPath          = true,
	BallColor         = Color3.fromRGB(168, 0, 255),   -- core purple
	BallGlow          = Color3.fromRGB(210, 100, 255), -- glow tint
	BallSize          = 0.55,
	BallFadeTime      = 0.25,
	GlowBrightness    = 4,
	GlowRange         = 9,
}

-- ══════════════════════════════════════════════════════════════════════
--  CONSTRUCTOR
-- ══════════════════════════════════════════════════════════════════════
function NPCAIService.new(npcModel, targetPlayer, customSettings)
	assert(npcModel and npcModel:IsA("Model"), "[NPCAIService] npcModel must be a Model")
	assert(npcModel.PrimaryPart,               "[NPCAIService] npcModel must have a PrimaryPart set")
	local hum = npcModel:FindFirstChildOfClass("Humanoid")
	assert(hum,                                "[NPCAIService] npcModel must have a Humanoid")

	-- Merge settings
	local S = {}
	for k, v in pairs(NPCAIService.DefaultSettings) do S[k] = v end
	if customSettings then
		for k, v in pairs(customSettings) do S[k] = v end
	end

	local self      = setmetatable({}, NPCAIService)
	self.npc        = npcModel
	self.root       = npcModel.PrimaryPart
	self.humanoid   = hum
	self.target     = targetPlayer
	self.settings   = S
	self.active     = true
	self.state      = "idle"

	self._waypoints  = {}
	self._wpIndex    = 1
	self._balls      = {}
	self._pathFolder = nil
	self._timer      = 0
	self._swimTimer  = 0
	self._stuckSecs  = 0
	self._stuckJumps = 0
	self._lastPos    = self.root.Position
	self._conns      = {}

	hum.WalkSpeed = S.WalkSpeed
	hum.JumpPower = S.JumpPower

	-- Folder to hold visualizer parts
	local folder = Instance.new("Folder")
	folder.Name   = "NPC_Path_" .. npcModel.Name
	folder.Parent = workspace
	self._pathFolder = folder

	self:_loop()
	return self
end

-- ══════════════════════════════════════════════════════════════════════
--  PATH VISUALIZER
-- ══════════════════════════════════════════════════════════════════════
function NPCAIService:_clearBalls()
	for _, b in ipairs(self._balls) do
		if b and b.Parent then b:Destroy() end
	end
	self._balls = {}
end

function NPCAIService:_fadeBall(ball)
	if not ball or not ball.Parent then return end
	local tw = TweenService:Create(ball, TweenInfo.new(self.settings.BallFadeTime), { Transparency = 1, Size = Vector3.new(0.05, 0.05, 0.05) })
	tw.Completed:Connect(function() if ball.Parent then ball:Destroy() end end)
	tw:Play()
end

function NPCAIService:_buildBalls(waypoints)
	self:_clearBalls()
	if not self.settings.ShowPath then return end
	local S = self.settings
	for i = 2, #waypoints do
		local pos = waypoints[i].Position

		local ball = Instance.new("Part")
		ball.Name        = "NPCWaypoint"
		ball.Shape       = Enum.PartType.Ball
		ball.Size        = Vector3.new(S.BallSize, S.BallSize, S.BallSize)
		ball.Position    = pos
		ball.Anchored    = true
		ball.CanCollide  = false
		ball.CastShadow  = false
		ball.Material    = Enum.Material.Neon
		ball.Color       = S.BallColor
		ball.Transparency = 0
		ball.Parent      = self._pathFolder

		-- Point light for glow
		local light = Instance.new("PointLight")
		light.Color      = S.BallGlow
		light.Brightness = S.GlowBrightness
		light.Range      = S.GlowRange
		light.Parent     = ball

		-- Pulse animation
		TweenService:Create(ball,
			TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = Vector3.new(S.BallSize * 1.6, S.BallSize * 1.6, S.BallSize * 1.6) }
		):Play()

		self._balls[i - 1] = ball
	end
end

-- ══════════════════════════════════════════════════════════════════════
--  ENVIRONMENT DETECTION
-- ══════════════════════════════════════════════════════════════════════
function NPCAIService:_inWater()
	if self.humanoid.FloorMaterial == Enum.Material.Water then return true end
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = { self.npc }
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(self.root.Position, Vector3.new(0, -3, 0), rp)
	return hit ~= nil and hit.Material == Enum.Material.Water
end

function NPCAIService:_lowCeiling()
	if not self.settings.CanCrouch then return false end
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = { self.npc }
	rp.FilterType = Enum.RaycastFilterType.Exclude
	return workspace:Raycast(self.root.Position, Vector3.new(0, self.settings.CrouchTriggerGap, 0), rp) ~= nil
end

function NPCAIService:_steepSlope()
	if not self.settings.CanClimb then return false end
	local rp = RaycastParams.new()
	rp.FilterDescendantsInstances = { self.npc }
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local hit = workspace:Raycast(self.root.Position, Vector3.new(0, -3, 0), rp)
	if hit then
		local ang = math.deg(math.acos(math.clamp(hit.Normal:Dot(Vector3.new(0,1,0)), -1, 1)))
		return ang >= self.settings.ClimbAngleMin
	end
	return false
end

-- ══════════════════════════════════════════════════════════════════════
--  STATE APPLICATION
-- ══════════════════════════════════════════════════════════════════════
local HipHeights = { crouch = 0.5, default = 2 }
function NPCAIService:_setState(new)
	if self.state == new then return end
	self.state = new
	local hum = self.humanoid
	local S   = self.settings

	-- Reset hip height
	hum.HipHeight = (new == "crouch") and HipHeights.crouch or HipHeights.default

	local speeds = {
		idle   = S.WalkSpeed,
		walk   = S.WalkSpeed,
		run    = S.RunSpeed,
		crouch = S.CrouchSpeed,
		swim   = S.SwimSpeed,
		climb  = S.ClimbSpeed,
	}
	hum.WalkSpeed = speeds[new] or S.WalkSpeed
end

-- ══════════════════════════════════════════════════════════════════════
--  STUCK RECOVERY
-- ══════════════════════════════════════════════════════════════════════
function NPCAIService:_checkStuck(dt)
	local moved = (self.root.Position - self._lastPos).Magnitude
	self._lastPos = self.root.Position
	local S = self.settings

	if moved < 0.3 and #self._waypoints > 0 then
		self._stuckSecs += dt
		if self._stuckSecs >= S.StuckTimeout then
			self._stuckSecs  = 0
			self._stuckJumps += 1
			if S.CanJump then self.humanoid.Jump = true end
			if self._stuckJumps >= S.StuckJumpMax then
				self._stuckJumps = 0
				self._waypoints  = {}
				self:_clearBalls()
			end
		end
	else
		self._stuckSecs  = 0
		self._stuckJumps = 0
	end
end

-- ══════════════════════════════════════════════════════════════════════
--  PATHFINDING
-- ══════════════════════════════════════════════════════════════════════
function NPCAIService:_getGoal()
	if not self.target then return nil end
	local ch = self.target.Character
	if not ch then return nil end
	local r = ch:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

function NPCAIService:_computePath(goal)
	local S = self.settings
	local p = PathfindingService:CreatePath({
		AgentHeight    = S.AgentHeight,
		AgentRadius    = S.AgentRadius,
		AgentCanJump   = S.CanJump,
		AgentCanClimb  = S.CanClimb,
		WaypointSpacing = 2,
	})
	local ok = pcall(function() p:ComputeAsync(self.root.Position, goal) end)
	if ok and p.Status == Enum.PathStatus.Success then return p end
	return nil
end

function NPCAIService:_followWaypoints()
	local wps = self._waypoints
	if self._wpIndex > #wps then return end
	local wp   = wps[self._wpIndex]
	local dist = (self.root.Position - wp.Position).Magnitude

	if dist <= self.settings.WaypointRadius then
		-- Fade out the ball we just reached
		if self._balls[self._wpIndex - 1] then
			self:_fadeBall(self._balls[self._wpIndex - 1])
			self._balls[self._wpIndex - 1] = nil
		end
		self._wpIndex += 1
		if self._wpIndex > #wps then self._waypoints = {} return end
		wp = wps[self._wpIndex]
	end

	if wp.Action == Enum.PathWaypointAction.Jump and self.settings.CanJump then
		self.humanoid.Jump = true
	end

	self.humanoid:MoveTo(wp.Position)
end

-- ══════════════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ══════════════════════════════════════════════════════════════════════
function NPCAIService:_loop()
	local c = RunService.Heartbeat:Connect(function(dt)
		if not self.active then return end
		if not self.npc.Parent or self.humanoid.Health <= 0 then
			self:destroy()
			return
		end

		self._timer     += dt
		self._swimTimer += dt

		local S       = self.settings
		local water   = S.CanSwim   and self:_inWater()
		local ceiling = S.CanCrouch and not water and self:_lowCeiling()
		local slope   = S.CanClimb  and not water and not ceiling and self:_steepSlope()

		self:_checkStuck(dt)

		-- Swim strokes
		if water and self._swimTimer >= S.SwimStrokeRate then
			self._swimTimer = 0
			if S.CanJump then self.humanoid.Jump = true end
		end

		-- Recalc path on interval
		if self._timer >= S.RecalcRate then
			self._timer = 0
			local goal = self:_getGoal()

			if not goal then
				self:_setState("idle")
				self._waypoints = {}
				self:_clearBalls()
			else
				local dist = (self.root.Position - goal).Magnitude

				if dist > S.LoseTargetRange or dist < S.StopDistance then
					-- Idle / too close
					self:_setState("idle")
					self.humanoid:MoveTo(self.root.Position)
					self._waypoints = {}
					self:_clearBalls()
				elseif dist <= S.FollowRange then
					-- Determine movement state
					local newState = "walk"
					if water   then newState = "swim"
					elseif ceiling then newState = "crouch"
					elseif slope    then newState = "climb"
					elseif dist >= S.RunThreshold then newState = "run"
					end
					self:_setState(newState)

					local path = self:_computePath(goal)
					if path then
						self._waypoints = path:GetWaypoints()
						self._wpIndex   = 2
						self:_buildBalls(self._waypoints)
					else
						-- Direct fallback
						self.humanoid:MoveTo(goal)
						self:_clearBalls()
					end
				else
					self:_setState("idle")
					self._waypoints = {}
					self:_clearBalls()
				end
			end
		end

		self:_followWaypoints()
	end)

	table.insert(self._conns, c)
end

-- ══════════════════════════════════════════════════════════════════════
--  PUBLIC API
-- ══════════════════════════════════════════════════════════════════════

--- Change the follow target at runtime
function NPCAIService:setTarget(player)
	self.target = player
end

--- Update settings at runtime
--- Example: ai:configure({ WalkSpeed = 20, ShowPath = false, FollowRange = 50 })
function NPCAIService:configure(tbl)
	for k, v in pairs(tbl) do self.settings[k] = v end
	self.humanoid.WalkSpeed = self.settings.WalkSpeed
	self.humanoid.JumpPower = self.settings.JumpPower
end

--- Pause all AI logic
function NPCAIService:pause()
	self.active = false
	self.humanoid:MoveTo(self.root.Position)
	self:_clearBalls()
end

--- Resume AI logic
function NPCAIService:resume()
	self.active = true
end

--- Get current AI state ("idle" | "walk" | "run" | "swim" | "climb" | "crouch")
function NPCAIService:getState()
	return self.state
end

--- Destroy and clean up everything
function NPCAIService:destroy()
	self.active = false
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}
	self:_clearBalls()
	if self._pathFolder and self._pathFolder.Parent then
		self._pathFolder:Destroy()
	end
end

-- Callable shorthand: require(NPCAIService)(npc, player, settings)
return setmetatable(NPCAIService, {
	__call = function(_, ...)
		return NPCAIService.new(...)
	end,
})