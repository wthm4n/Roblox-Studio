-- NPCAIService.lua
-- ModuleScript → ServerScriptService
-- require(NPCAIService).new(npcModel, targetPlayer, settings?)
-- OR shorthand: require(NPCAIService)(npcModel, targetPlayer, settings?)

local PathfindingService = game:GetService("PathfindingService")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")

-- ════════════════════════════════════════════════════
--  MODULE
-- ════════════════════════════════════════════════════
local AI = {}
AI.__index = AI

-- ════════════════════════════════════════════════════
--  DEFAULT SETTINGS
-- ════════════════════════════════════════════════════
AI.Defaults = {
	-- Follow
	FollowRange      = 999,   -- start chasing within this many studs
	StopDistance     = 5,     -- stop when this close to player
	LoseRange        = 999,   -- give up if player goes beyond this

	-- Speed
	WalkSpeed        = 16,
	RunSpeed         = 26,
	RunThreshold     = 30,    -- studs: switch to RunSpeed past this distance
	CrouchSpeed      = 6,
	SwimSpeed        = 10,

	-- Abilities
	CanJump          = true,
	JumpPower        = 50,
	CanSwim          = true,
	SwimStrokeRate   = 0.65,  -- seconds between swim jump-strokes
	CanCrouch        = true,
	CrouchGap        = 4,     -- studs of clearance overhead that triggers crouch

	-- Pathfinding
	RecalcRate       = 0.2,   -- seconds between path recalculations
	WpReach          = 3.5,   -- studs to count waypoint as reached
	AgentHeight      = 5,
	AgentRadius      = 2,

	-- Stuck recovery
	StuckTime        = 2,     -- seconds before NPC is considered stuck
	StuckJumpMax     = 3,     -- jump attempts before forcing a repath

	-- Path balls (purple glow)
	ShowPath         = true,
	BallColor        = Color3.fromRGB(160, 0, 255),
	BallGlow         = Color3.fromRGB(200, 90, 255),
	BallSize         = 0.5,
	BallPulse        = 0.5,   -- pulse animation duration
	GlowBright       = 5,
	GlowRange        = 10,
}

-- ════════════════════════════════════════════════════
--  CONSTRUCTOR
-- ════════════════════════════════════════════════════
function AI.new(npcModel, targetPlayer, customSettings)
	assert(npcModel and npcModel:IsA("Model"),  "NPCAIService: npcModel must be a Model")
	assert(npcModel.PrimaryPart,                "NPCAIService: PrimaryPart must be set (HumanoidRootPart)")
	local hum = npcModel:FindFirstChildOfClass("Humanoid")
	assert(hum,                                 "NPCAIService: Model needs a Humanoid")

	-- Merge defaults + custom
	local S = {}
	for k, v in pairs(AI.Defaults) do S[k] = v end
	if customSettings then
		for k, v in pairs(customSettings) do S[k] = v end
	end

	local self          = setmetatable({}, AI)
	self.npc            = npcModel
	self.root           = npcModel.PrimaryPart
	self.hum            = hum
	self.target         = targetPlayer
	self.S              = S
	self.active         = true
	self.state          = "idle"

	-- Internal
	self._wps           = {}
	self._wpi           = 1
	self._balls         = {}
	self._folder        = nil
	self._t             = 0
	self._swimT         = 0
	self._stuckT        = 0
	self._stuckJ        = 0
	self._lastPos       = self.root.Position
	self._conns         = {}

	-- KEY: these three lines make truss climbing work.
	-- Roblox auto-climbs TrussParts when the Humanoid touches one
	-- while facing it and walking. We just need to make sure these are set.
	hum.WalkSpeed       = S.WalkSpeed
	hum.JumpPower       = S.JumpPower
	hum.AutoRotate      = true   -- must be true for engine climb to engage

	-- Visualizer folder
	local f = Instance.new("Folder")
	f.Name   = "AIPath_" .. npcModel.Name
	f.Parent = workspace
	self._folder = f

	self:_run()
	return self
end

-- ════════════════════════════════════════════════════
--  VISUALIZER
-- ════════════════════════════════════════════════════
function AI:_clearBalls()
	for _, b in ipairs(self._balls) do
		if b and b.Parent then b:Destroy() end
	end
	self._balls = {}
end

function AI:_fadeBall(b)
	if not b or not b.Parent then return end
	local tw = TweenService:Create(b, TweenInfo.new(self.S.BallPulse),
		{ Transparency = 1, Size = Vector3.new(0.05,0.05,0.05) })
	tw.Completed:Connect(function() if b.Parent then b:Destroy() end end)
	tw:Play()
end

function AI:_makeBalls(wps)
	self:_clearBalls()
	if not self.S.ShowPath then return end
	local S = self.S
	for i = 2, #wps do
		local b = Instance.new("Part")
		b.Name        = "AIWaypoint"
		b.Shape       = Enum.PartType.Ball
		b.Size        = Vector3.new(S.BallSize, S.BallSize, S.BallSize)
		b.Position    = wps[i].Position
		b.Anchored    = true
		b.CanCollide  = false
		b.CastShadow  = false
		b.Material    = Enum.Material.Neon
		b.Color       = S.BallColor
		b.Parent      = self._folder

		local pl = Instance.new("PointLight")
		pl.Color      = S.BallGlow
		pl.Brightness = S.GlowBright
		pl.Range      = S.GlowRange
		pl.Parent     = b

		-- Pulse tween
		TweenService:Create(b,
			TweenInfo.new(S.BallPulse, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Size = Vector3.new(S.BallSize*1.7, S.BallSize*1.7, S.BallSize*1.7) }
		):Play()

		self._balls[i-1] = b
	end
end

-- ════════════════════════════════════════════════════
--  ENVIRONMENT SENSING
-- ════════════════════════════════════════════════════
function AI:_rp()
	local p = RaycastParams.new()
	p.FilterDescendantsInstances = { self.npc }
	p.FilterType = Enum.RaycastFilterType.Exclude
	return p
end

function AI:_swimming()
	-- Check humanoid state first (most reliable)
	if self.hum:GetState() == Enum.HumanoidStateType.Swimming then return true end
	if self.hum.FloorMaterial == Enum.Material.Water then return true end
	local hit = workspace:Raycast(self.root.Position, Vector3.new(0,-2.5,0), self:_rp())
	return hit ~= nil and hit.Material == Enum.Material.Water
end

function AI:_crouching()
	if not self.S.CanCrouch then return false end
	return workspace:Raycast(self.root.Position, Vector3.new(0, self.S.CrouchGap, 0), self:_rp()) ~= nil
end

-- ════════════════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════════════════
function AI:_set(s)
	if self.state == s then return end
	self.state = s
	local S = self.S
	self.hum.HipHeight  = (s == "crouch") and 0.5 or 2
	local spd = { idle=S.WalkSpeed, walk=S.WalkSpeed, run=S.RunSpeed,
		swim=S.SwimSpeed, crouch=S.CrouchSpeed }
	self.hum.WalkSpeed = spd[s] or S.WalkSpeed
end

-- ════════════════════════════════════════════════════
--  STUCK CHECK
-- ════════════════════════════════════════════════════
function AI:_stuck(dt)
	local moved = (self.root.Position - self._lastPos).Magnitude
	self._lastPos = self.root.Position
	local S = self.S

	if moved < 0.25 and #self._wps > 0 then
		self._stuckT += dt
		if self._stuckT >= S.StuckTime then
			self._stuckT  = 0
			self._stuckJ += 1
			if S.CanJump then self.hum.Jump = true end
			if self._stuckJ >= S.StuckJumpMax then
				self._stuckJ = 0
				self._wps    = {}
				self:_clearBalls()
			end
		end
	else
		self._stuckT = 0
		self._stuckJ = 0
	end
end

-- ════════════════════════════════════════════════════
--  PATHFINDING
-- ════════════════════════════════════════════════════
function AI:_goal()
	if not self.target then return nil end
	local ch = self.target.Character
	if not ch then return nil end
	local r = ch:FindFirstChild("HumanoidRootPart")
	return r and r.Position or nil
end

function AI:_path(goal)
	local S = self.S
	local p = PathfindingService:CreatePath({
		AgentHeight      = S.AgentHeight,
		AgentRadius      = S.AgentRadius,
		AgentCanJump     = S.CanJump,
		AgentCanClimb    = true,   -- always on so truss nodes generate
		WaypointSpacing  = 1.5,   -- tighter spacing = smoother truss approach
	})
	local ok = pcall(function() p:ComputeAsync(self.root.Position, goal) end)
	if ok and p.Status == Enum.PathStatus.Success then return p end
	return nil
end

function AI:_follow()
	local wps = self._wps
	if self._wpi > #wps then return end

	local wp   = wps[self._wpi]
	local dist = (self.root.Position - wp.Position).Magnitude

	if dist <= self.S.WpReach then
		if self._balls[self._wpi - 1] then
			self:_fadeBall(self._balls[self._wpi - 1])
			self._balls[self._wpi - 1] = nil
		end
		self._wpi += 1
		if self._wpi > #wps then self._wps = {} return end
		wp = wps[self._wpi]
	end

	-- Jump waypoints AND climb waypoints both use hum.Jump
	-- For Climb waypoints the engine also expects the NPC to
	-- be facing/touching the climbable — MoveTo handles that.
	local action = wp.Action
	if action == Enum.PathWaypointAction.Jump then
		self.hum.Jump = true
	end

	self.hum:MoveTo(wp.Position)
end

-- ════════════════════════════════════════════════════
--  MAIN LOOP
-- ════════════════════════════════════════════════════
function AI:_run()
	local conn = RunService.Heartbeat:Connect(function(dt)
		if not self.active then return end
		if not self.npc.Parent or self.hum.Health <= 0 then
			self:destroy(); return
		end

		self._t      += dt
		self._swimT  += dt

		local S    = self.S
		local swim = S.CanSwim and self:_swimming()
		local duck = not swim  and self:_crouching()

		-- Swim strokes (periodic jump so NPC doesn't sink)
		if swim and self._swimT >= S.SwimStrokeRate then
			self._swimT = 0
			self.hum.Jump = true
		end

		self:_stuck(dt)

		-- Path recalc
		if self._t >= S.RecalcRate then
			self._t = 0
			local goal = self:_goal()

			if not goal then
				self:_set("idle")
				self._wps = {}
				self:_clearBalls()
				return
			end

			local d = (self.root.Position - goal).Magnitude

			if d > S.LoseRange then
				self:_set("idle")
				self._wps = {}
				self:_clearBalls()
				self.hum:MoveTo(self.root.Position)

			elseif d <= S.StopDistance then
				self:_set("idle")
				self._wps = {}
				self:_clearBalls()
				self.hum:MoveTo(self.root.Position)

			elseif d <= S.FollowRange then
				-- Pick state
				if swim then        self:_set("swim")
				elseif duck then    self:_set("crouch")
				elseif d >= S.RunThreshold then self:_set("run")
				else                self:_set("walk")
				end

				local p = self:_path(goal)
				if p then
					self._wps = p:GetWaypoints()
					self._wpi = 2
					self:_makeBalls(self._wps)
				else
					-- Direct fallback (no path found, e.g. open water)
					self.hum:MoveTo(goal)
					self:_clearBalls()
				end
			else
				self:_set("idle")
				self._wps = {}
				self:_clearBalls()
			end
		end

		self:_follow()
	end)

	table.insert(self._conns, conn)
end

-- ════════════════════════════════════════════════════
--  PUBLIC API
-- ════════════════════════════════════════════════════

--- Change follow target at any time
function AI:setTarget(player)
	self.target = player
end

--- Tweak settings at runtime, e.g. ai:configure({ WalkSpeed = 20 })
function AI:configure(t)
	for k, v in pairs(t) do self.S[k] = v end
	self.hum.WalkSpeed = self.S.WalkSpeed
	self.hum.JumpPower = self.S.JumpPower
end

--- Pause movement
function AI:pause()
	self.active = false
	self.hum:MoveTo(self.root.Position)
	self:_clearBalls()
end

--- Resume movement
function AI:resume()
	self.active = true
end

--- Returns "idle" | "walk" | "run" | "swim" | "crouch"
function AI:getState()
	return self.state
end

--- Full cleanup
function AI:destroy()
	self.active = false
	for _, c in ipairs(self._conns) do c:Disconnect() end
	self._conns = {}
	self:_clearBalls()
	if self._folder and self._folder.Parent then self._folder:Destroy() end
end

-- ════════════════════════════════════════════════════
--  SHORTHAND CALL
-- ════════════════════════════════════════════════════
return setmetatable(AI, {
	__call = function(_, ...) return AI.new(...) end,
})