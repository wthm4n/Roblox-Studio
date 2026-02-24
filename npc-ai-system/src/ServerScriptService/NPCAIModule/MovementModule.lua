--[[
	MovementModule.lua
	Handles all NPC locomotion:
	  - Smart pathfinding with material costs + kill part avoidance
	  - Walk / Run / Swim / Climb / Crawl transitions
	  - Animation state management
	  - Wander logic

	ARCHITECTURE:
	  Path following runs in its own persistent thread (_pathLoop).
	  The heartbeat tick only sets a _goalPosition target.
	  _pathLoop wakes up, computes path, walks all waypoints, then idles.
	  For chasing, a recompute timer (chaseRecomputeInterval) refreshes
	  the path every N seconds so the NPC tracks a moving player.
--]]

local PathfindingService = game:GetService("PathfindingService")
local Workspace          = game:GetService("Workspace")

local CHASE_RECOMPUTE    = 1.2   -- seconds between path recomputes when chasing
local WAYPOINT_TIMEOUT   = 4     -- max seconds per waypoint before stuck
local STUCK_MOVE_MIN     = 0.8   -- studs moved in WAYPOINT_TIMEOUT to not be "stuck"
local REACH_DIST         = 2.5   -- studs to count a waypoint as reached

-- ─────────────────────────────────────────────
--  ANIMATION IDs  — replace with your asset IDs
-- ─────────────────────────────────────────────
local ANIM_IDS = {
	idle   = "rbxassetid://180435571",
	walk   = "rbxassetid://180426354",
	run    = "rbxassetid://180426354",
	swim   = "rbxassetid://180435571",
	climb  = "rbxassetid://180435571",
	crawl  = "rbxassetid://180435571",
	attack = "rbxassetid://129967390",
	death  = "rbxassetid://180436148",
}

-- ─────────────────────────────────────────────
--  ANIMATION SETUP  (static helper, called once by NPCService)
-- ─────────────────────────────────────────────

local function SetupAnimator(model: Model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChildOfClass("Animator")
		or Instance.new("Animator", humanoid)

	local tracks = {}
	for name, id in pairs(ANIM_IDS) do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then
			if name == "attack" or name == "death" then
				track.Priority = Enum.AnimationPriority.Action
			elseif name == "run" or name == "walk" then
				track.Priority = Enum.AnimationPriority.Movement
			else
				track.Priority = Enum.AnimationPriority.Core
			end
			tracks[name] = track
		end
	end

	return { animator = animator, tracks = tracks }
end

-- ─────────────────────────────────────────────
--  MODULE CLASS
-- ─────────────────────────────────────────────

local MovementModule = {}
MovementModule.__index = MovementModule
MovementModule.SetupAnimator = SetupAnimator   -- expose to NPCService

function MovementModule.new(npc)
	local self         = setmetatable({}, MovementModule)
	self._npc          = npc
	self._currentAnim  = nil

	-- Goal management
	self._goalPosition  = nil    -- Vector3 | nil  set by behavior tick
	self._goalIsChase   = false  -- true = moving target, recompute on timer
	self._chaseTimer    = 0

	-- Path thread: one persistent coroutine
	self._running       = true
	self._pathThread    = task.spawn(function() self:_pathLoop() end)

	return self
end

-- ─────────────────────────────────────────────
--  PUBLIC API  (called from behavior tick — non-blocking)
-- ─────────────────────────────────────────────

-- Call every tick while chasing/fleeing a moving target
function MovementModule:Chase(position: Vector3)
	self._goalPosition = position
	self._goalIsChase  = true
end

-- Call once for a fixed destination (wander, patrol waypoint)
function MovementModule:MoveTo(position: Vector3)
	-- Only restart if destination changed meaningfully
	if self._goalPosition and (self._goalPosition - position).Magnitude < 2
		and not self._goalIsChase then
		return
	end
	self._goalPosition = position
	self._goalIsChase  = false
	self._chaseTimer   = 0
end

function MovementModule:Stop()
	self._goalPosition = nil
	self._goalIsChase  = false
	local ok = pcall(function() self._npc.Humanoid:MoveTo(self._npc.HRP.Position) end)
end

function MovementModule:Destroy()
	self._running = false
	if self._pathThread then
		task.cancel(self._pathThread)
		self._pathThread = nil
	end
end

-- ─────────────────────────────────────────────
--  WANDER  (picks random reachable point, calls MoveTo)
-- ─────────────────────────────────────────────

function MovementModule:Wander(radius: number)
	local npc    = self._npc
	local origin = npc.HRP.Position

	local angle  = math.random() * math.pi * 2
	local dist   = math.random(math.floor(radius * 0.3), radius)
	local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	local goal   = origin + offset

	-- Ground snap
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { npc.Model }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local hit = Workspace:Raycast(goal + Vector3.new(0, 15, 0), Vector3.new(0, -30, 0), rayParams)
	if hit then
		goal = hit.Position + Vector3.new(0, 0.1, 0)
	end

	self:MoveTo(goal)
end

-- ─────────────────────────────────────────────
--  PATH LOOP  (runs in its own thread, always alive)
-- ─────────────────────────────────────────────

function MovementModule:_pathLoop()
	local npc = self._npc

	while self._running do
		local goal = self._goalPosition

		if not goal or not npc.Alive then
			task.wait(0.1)
			continue
		end

		-- For chasing: recompute on interval
		if self._goalIsChase then
			self._chaseTimer = self._chaseTimer - 0   -- will count in _walkPath
		end

		-- Compute and walk the path
		self:_computeAndWalk(goal)

		-- Small yield before next iteration
		task.wait(0.05)
	end
end

-- ─────────────────────────────────────────────
--  COMPUTE + WALK  (runs inside the path loop thread)
-- ─────────────────────────────────────────────

function MovementModule:_computeAndWalk(goal: Vector3)
	local npc    = self._npc
	local cfg    = npc.Config
	local hum    = npc.Humanoid
	local hrp    = npc.HRP
	local sensor = npc.Sensor

	-- Agent params
	local costs = {}
	for mat, cost in pairs(cfg.materialCosts) do
		costs[mat.Name] = cost
	end

	local agentParams = {
		AgentRadius  = cfg.agentRadius,
		AgentHeight  = cfg.agentHeight,
		AgentCanJump = cfg.agentCanJump,
		AgentCanClimb= cfg.agentCanClimb,
		WaypointSpacing = 2,
		Costs        = costs,
	}

	local path = PathfindingService:CreatePath(agentParams)

	local ok, err = pcall(function()
		path:ComputeAsync(hrp.Position, goal)
	end)

	if not ok then
		if cfg.debugMode then warn("[Movement] ComputeAsync error:", err) end
		-- Direct fallback
		pcall(function() hum:MoveTo(goal) end)
		task.wait(0.5)
		return
	end

	if path.Status == Enum.PathStatus.NoPath then
		if cfg.debugMode then warn("[Movement] No path found to", goal) end
		task.wait(0.5)
		return
	end

	local waypoints = path:GetWaypoints()
	if not waypoints or #waypoints == 0 then
		task.wait(0.1)
		return
	end

	-- Track blocked signal
	local pathBlocked = false
	local blockedConn = path.Blocked:Connect(function()
		pathBlocked = true
	end)

	for i, wp in ipairs(waypoints) do
		-- Always check these before each waypoint
		if not npc.Alive or not self._running then break end
		if pathBlocked then break end

		-- If chasing, break out early to recompute toward updated target
		if self._goalIsChase then
			local currentGoal = self._goalPosition
			if currentGoal and (goal - currentGoal).Magnitude > 4 then
				-- Target moved significantly, recompute
				break
			end
		end

		-- Skip kill part waypoints
		if sensor:IsDangerous(wp.Position) then
			if cfg.debugMode then warn("[Movement] Dangerous waypoint skipped") end
			pathBlocked = true
			break
		end

		-- Jump if needed
		if wp.Action == Enum.PathWaypointAction.Jump then
			hum.Jump = true
			task.wait(0.1)
		end

		-- Set environment-appropriate speed
		self:_applyEnvironmentSpeed()

		-- Issue MoveTo for this waypoint
		hum:MoveTo(wp.Position)

		-- Wait for arrival
		local startPos = hrp.Position
		local elapsed  = 0
		local reached  = false

		while elapsed < WAYPOINT_TIMEOUT do
			task.wait(0.1)
			elapsed = elapsed + 0.1

			if not npc.Alive or not self._running or pathBlocked then break end

			local dist = (hrp.Position - wp.Position).Magnitude
			if dist <= REACH_DIST then
				reached = true
				break
			end

			-- Stuck check: every second see how far we've moved
			if elapsed >= 1.5 then
				local moved = (hrp.Position - startPos).Magnitude
				if moved < STUCK_MOVE_MIN then
					if cfg.debugMode then warn("[Movement] Stuck at waypoint", i) end
					-- Try jumping to unstick
					hum.Jump = true
					task.wait(0.3)
					-- If still barely moved, break and recompute
					if (hrp.Position - startPos).Magnitude < STUCK_MOVE_MIN then
						pathBlocked = true
						break
					end
					startPos = hrp.Position
					elapsed  = 0
				end
			end
		end

		if pathBlocked then break end
	end

	blockedConn:Disconnect()
end

-- ─────────────────────────────────────────────
--  ENVIRONMENT SPEED
-- ─────────────────────────────────────────────

function MovementModule:_applyEnvironmentSpeed()
	local npc    = self._npc
	local cfg    = npc.Config
	local hum    = npc.Humanoid
	local sensor = npc.Sensor

	if sensor.InWater then
		hum.WalkSpeed = cfg.swimSpeed
		hum.HipHeight = 0.2
	elseif sensor.CanCrawl then
		hum.WalkSpeed = cfg.crawlSpeed
		hum.HipHeight = -0.5
	elseif sensor.NearClimbable then
		hum.WalkSpeed = cfg.climbSpeed
		hum.HipHeight = 0
	else
		hum.HipHeight = 0
		-- Speed is set by behavior (moveSpeed / runSpeed) — don't override here
	end
end

-- ─────────────────────────────────────────────
--  ANIMATIONS
-- ─────────────────────────────────────────────

function MovementModule:UpdateAnimations(state: string)
	local npc    = self._npc
	local sensor = npc.Sensor
	local hum    = npc.Humanoid
	local animData = npc.Animator
	if not animData then return end

	local moving = hum.MoveDirection.Magnitude > 0.1

	local target
	if sensor.InWater then
		target = "swim"
	elseif sensor.CanCrawl then
		target = "crawl"
	elseif not moving then
		target = "idle"
	elseif state == "aggressive" or state == "scared" then
		target = "run"
	else
		target = "walk"
	end

	self:_switchAnim(target)
end

function MovementModule:PlayAnimation(name: string)
	self:_switchAnim(name)
end

function MovementModule:_switchAnim(name: string)
	local animData = self._npc.Animator
	if not animData or not animData.tracks then return end
	if self._currentAnim == name then return end

	for animName, track in pairs(animData.tracks) do
		if animName ~= name and track.IsPlaying then
			track:Stop(0.15)
		end
	end

	local track = animData.tracks[name]
	if track and not track.IsPlaying then
		track:Play(0.15)
	end
	self._currentAnim = name
end

return MovementModule