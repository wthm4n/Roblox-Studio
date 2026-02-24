--[[
	MovementModule.lua
	Handles all NPC locomotion:
	  - Smart pathfinding with material costs + kill part avoidance
	  - Walk / Run / Swim / Climb / Crawl transitions
	  - Animation state management
	  - Wander logic
--]]

local PathfindingService = game:GetService("PathfindingService")
local Workspace          = game:GetService("Workspace")

-- ─────────────────────────────────────────────
--  ANIMATION IDs
--  Replace with your actual animation asset IDs
-- ─────────────────────────────────────────────
local ANIM_IDS = {
	idle   = "rbxassetid://180435571",
	walk   = "rbxassetid://180426354",
	run    = "rbxassetid://180426354",
	swim   = "rbxassetid://180435571",   -- replace with swim anim
	climb  = "rbxassetid://180435571",   -- replace with climb anim
	crawl  = "rbxassetid://180435571",   -- replace with crawl anim
	attack = "rbxassetid://129967390",
	death  = "rbxassetid://180436148",
}

-- ─────────────────────────────────────────────
--  ANIMATION SETUP (static, called once)
-- ─────────────────────────────────────────────

function MovementModule_SetupAnimator(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
		or Instance.new("Animator", humanoid)

	local tracks = {}
	for name, id in pairs(ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local track = animator:LoadAnimation(anim)
		-- Set priorities
		if name == "attack" or name == "death" then
			track.Priority = Enum.AnimationPriority.Action
		elseif name == "run" then
			track.Priority = Enum.AnimationPriority.Movement
		else
			track.Priority = Enum.AnimationPriority.Core
		end
		tracks[name] = track
	end

	return { animator = animator, tracks = tracks }
end

-- ─────────────────────────────────────────────
--  MODULE CLASS
-- ─────────────────────────────────────────────

local MovementModule = {}
MovementModule.__index = MovementModule

-- expose static helper
MovementModule.SetupAnimator = MovementModule_SetupAnimator

function MovementModule.new(npc)
	local self = setmetatable({}, MovementModule)
	self._npc          = npc
	self._currentAnim  = nil
	self._pathThread   = nil
	self._blocked      = false
	self._lastGoal     = nil
	self._pathRetries  = 0
	return self
end

-- ─────────────────────────────────────────────
--  PATHFINDING
-- ─────────────────────────────────────────────

function MovementModule:MoveTo(goal: Vector3)
	-- Debounce: don't restart path if goal hasn't changed much
	if self._lastGoal and (self._lastGoal - goal).Magnitude < 2 and self._pathThread then
		return
	end
	self._lastGoal = goal

	-- Cancel existing path thread
	self:Stop()

	self._pathThread = task.spawn(function()
		self:_followPath(goal)
	end)
end

function MovementModule:Stop()
	if self._pathThread then
		task.cancel(self._pathThread)
		self._pathThread = nil
	end
	self._npc.Humanoid:MoveTo(self._npc.HRP.Position)
	self._lastGoal = nil
end

function MovementModule:_followPath(goal: Vector3)
	local npc    = self._npc
	local cfg    = npc.Config
	local hum    = npc.Humanoid
	local hrp    = npc.HRP
	local sensor = npc.Sensor

	-- Build AgentParameters with material costs
	local agentParams = {
		AgentRadius      = cfg.agentRadius,
		AgentHeight      = cfg.agentHeight,
		AgentCanJump     = cfg.agentCanJump,
		AgentCanClimb    = cfg.agentCanClimb,
		WaypointSpacing  = 3,
		Costs            = {},
	}

	-- Convert Enum.Material costs to string keys (Roblox API requires strings)
	for mat, cost in pairs(cfg.materialCosts) do
		agentParams.Costs[mat.Name] = cost
	end

	local path = PathfindingService:CreatePath(agentParams)

	local success, err = pcall(function()
		path:ComputeAsync(hrp.Position, goal)
	end)

	if not success or path.Status ~= Enum.PathStatus.Success then
		if cfg.debugMode then
			warn(("[Movement] Path failed for %s: %s"):format(npc.Model.Name, tostring(err)))
		end
		-- Fallback: direct MoveTo (might fail over obstacles)
		hum:MoveTo(goal)
		return
	end

	local waypoints = path:GetWaypoints()

	-- Blocked connection: recompute path if NPC gets stuck
	local blockedConn = path.Blocked:Connect(function(waypointIdx)
		self._blocked = true
	end)

	for i, wp in ipairs(waypoints) do
		if not npc.Alive then break end

		-- Skip waypoint if it's a kill part
		if sensor:IsDangerous(wp.Position) then
			if cfg.debugMode then
				warn(("[Movement] Skipping dangerous waypoint at"):format(), wp.Position)
			end
			-- Try to recompute around it
			break
		end

		-- Jump action waypoints
		if wp.Action == Enum.PathWaypointAction.Jump then
			hum.Jump = true
		end

		-- Adjust speed for environment
		self:_setEnvironmentSpeed()

		hum:MoveTo(wp.Position)

		-- Wait until waypoint reached or timeout
		local reached = false
		local timeout = 5
		local elapsed = 0
		local startPos = hrp.Position

		repeat
			task.wait(0.1)
			elapsed = elapsed + 0.1

			local dist = (hrp.Position - wp.Position).Magnitude

			-- Stuck detection: barely moved after 2s
			if elapsed > 2 then
				local moved = (hrp.Position - startPos).Magnitude
				if moved < 0.5 then
					if cfg.debugMode then
						warn(("[Movement] %s stuck, recomputing..."):format(npc.Model.Name))
					end
					self._blocked = true
					break
				end
			end

			reached = dist <= cfg.waypointReachedDist
		until reached or elapsed >= timeout or not npc.Alive or self._blocked

		if self._blocked then
			self._blocked = false
			blockedConn:Disconnect()
			-- Recompute path
			task.wait(0.2)
			self:_followPath(goal)
			return
		end
	end

	blockedConn:Disconnect()
end

-- ─────────────────────────────────────────────
--  ENVIRONMENT SPEED ADJUSTMENT
-- ─────────────────────────────────────────────

function MovementModule:_setEnvironmentSpeed()
	local npc    = self._npc
	local cfg    = npc.Config
	local hum    = npc.Humanoid
	local sensor = npc.Sensor

	if sensor.InWater then
		hum.WalkSpeed = cfg.swimSpeed
		-- Enable swimming: set HipHeight lower
		hum.HipHeight = 0.5
	elseif sensor.CanCrawl then
		hum.WalkSpeed = cfg.crawlSpeed
		hum.HipHeight = -0.5  -- makes character crouch
	elseif sensor.NearClimbable then
		hum.WalkSpeed = cfg.climbSpeed
		-- Climbing is handled by Roblox engine if agentCanClimb = true
		hum.HipHeight = 0     -- reset
	else
		-- Normal: speed is set by behavior (walk/run)
		hum.HipHeight = 0
	end
end

-- ─────────────────────────────────────────────
--  WANDER
-- ─────────────────────────────────────────────

function MovementModule:Wander(radius: number)
	local npc = self._npc
	local origin = npc.HRP.Position

	-- Pick random point within radius
	local angle  = math.random() * math.pi * 2
	local dist   = math.random() * radius
	local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	local goal   = origin + offset

	-- Ground snap: raycast down to find floor
	local result = Workspace:Raycast(
		goal + Vector3.new(0, 10, 0),
		Vector3.new(0, -20, 0)
	)
	if result then
		goal = result.Position + Vector3.new(0, 0.1, 0)
	end

	self:MoveTo(goal)
end

-- ─────────────────────────────────────────────
--  ANIMATIONS
-- ─────────────────────────────────────────────

function MovementModule:UpdateAnimations(state: string)
	local npc     = self._npc
	local sensor  = npc.Sensor
	local hum     = npc.Humanoid
	local anim    = npc.Animator
	if not anim then return end

	local speed   = hum.MoveDirection.Magnitude  -- 0 if idle, >0 if moving

	local targetAnim

	if sensor.InWater then
		targetAnim = "swim"
	elseif sensor.CanCrawl then
		targetAnim = "crawl"
	elseif speed < 0.1 then
		targetAnim = "idle"
	elseif state == "aggressive" or state == "scared" then
		targetAnim = "run"
	else
		targetAnim = "walk"
	end

	self:_switchAnim(targetAnim)
end

function MovementModule:PlayAnimation(name: string)
	self:_switchAnim(name)
end

function MovementModule:_switchAnim(name: string)
	local anim = self._npc.Animator
	if not anim then return end
	if self._currentAnim == name then return end

	-- Stop all
	for animName, track in pairs(anim.tracks) do
		if track.IsPlaying and animName ~= name then
			track:Stop(0.2)
		end
	end

	local track = anim.tracks[name]
	if track and not track.IsPlaying then
		track:Play(0.2)
		self._currentAnim = name
	end
end

return MovementModule
