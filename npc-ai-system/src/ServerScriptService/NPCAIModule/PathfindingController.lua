--[[
	PathfindingController.lua

	FIXES for slowdown / stutter during chase:

	1. ASYNC COMPUTE — ComputeAsync runs in a task.spawn() so it never
	   blocks the Heartbeat. The NPC keeps following its current waypoints
	   while the new path is being computed in the background.

	2. DESTINATION THRESHOLD — MoveTo only triggers a recompute when the
	   new destination is >MinRecomputeDist studs from the last computed one.
	   Previously Chase called MoveTo every 0.2s even if the player barely moved,
	   causing constant path restarts that zeroed out velocity each time.

	3. WAYPOINT CONTINUITY — _computeAndMove no longer resets _wpIndex to 2
	   immediately. Instead it keeps following old waypoints until the new
	   path is ready, then swaps atomically.

	4. NOPATH COOLDOWN reduced 2s → 0.8s. 2s full freeze was too punishing.

	5. STUCK THRESHOLD tuned: StuckTimeout 1.2s is fine but we now skip
	   recalculate if a fresh path was computed less than 0.5s ago (prevents
	   the recalculate → reset → "stuck" → recalculate feedback loop).

	6. Humanoid.MoveToFinished is connected to auto-advance waypoints so the
	   NPC doesn't wait for Update() to tick before moving to the next point.
--]]

local PathfindingService = game:GetService("PathfindingService")
local Config             = require(game.ReplicatedStorage.Shared.Config)

local PathfindingController = {}
PathfindingController.__index = PathfindingController

-- How close the new destination must be to the last computed one
-- before we skip recomputing entirely (studs)
local MIN_RECOMPUTE_DIST = 3.0

-- ─── Debug helpers ─────────────────────────────────────────────────────────

local debugFolder: Folder?

local function getDebugFolder(): Folder
	if not debugFolder then
		debugFolder = workspace:FindFirstChild("_NPCDebug") or Instance.new("Folder")
		debugFolder.Name = "_NPCDebug"
		debugFolder.Parent = workspace
	end
	return debugFolder
end

local function clearDebugParts(npcId: string)
	local folder = getDebugFolder()
	local sub = folder:FindFirstChild(npcId)
	if sub then sub:ClearAllChildren() end
end
-- ─── Config references ────────────────────────────────────────────────────
-- These are just for easy reference while coding. Adjust values in Config.lua.
local function drawWaypoints(npcId: string, waypoints: { PathWaypoint })
	if not Config.Debug.Enabled or not Config.Debug.ShowPath then return end
	local folder = getDebugFolder()
	local sub = folder:FindFirstChild(npcId) or Instance.new("Folder")
	sub.Name = npcId
	sub.Parent = folder
	sub:ClearAllChildren()

	for i, wp in ipairs(waypoints) do
		local part = Instance.new("Part")
		part.Size = Vector3.new(0.6, 0.6, 0.6)
		part.Shape = Enum.PartType.Ball
		part.Material = Enum.Material.Neon
		part.Color = (i == 1) and Config.Debug.WaypointColor or Config.Debug.PathColor
		part.CFrame = CFrame.new(wp.Position)
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Parent = sub

		if i > 1 then
			local prev = waypoints[i - 1].Position
			local dist = (wp.Position - prev).Magnitude
			if dist > 0.1 then
				local beam = Instance.new("Part")
				beam.Size = Vector3.new(0.08, 0.08, dist)
				beam.CFrame = CFrame.lookAt(prev, wp.Position) * CFrame.new(0, 0, -dist / 2)
				beam.Anchored = true
				beam.CanCollide = false
				beam.CastShadow = false
				beam.Material = Enum.Material.Neon
				beam.Color = Config.Debug.PathColor
				beam.Parent = sub
			end
		end
	end
end

-- ─── Constructor ───────────────────────────────────────────────────────────

function PathfindingController.new(npc: Model)
	local self = setmetatable({}, PathfindingController)

	self.NPC      = npc
	self.Humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.RootPart = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	self.NpcId    = npc.Name .. "_" .. tostring(npc:GetAttribute("NPCID") or math.random(1000, 9999))

	self._path = PathfindingService:CreatePath({
		AgentRadius     = 1.0,
		AgentHeight     = 5,
		AgentCanJump    = true,
		AgentCanClimb   = true,
		WaypointSpacing = 2,
		Costs           = { Water = 20, Climb = 0.5 },
	})

	self._waypoints       = {}
	self._wpIndex         = 1
	self._active          = false
	self._destination     = nil
	self._lastComputedDest = nil   -- FIX 2: last destination we actually computed
	self._lastComputedAt  = -999  -- FIX 5: when we last finished computing
	self._lastPos         = Vector3.zero
	self._lastMovedAt     = 0
	self._stuckCount      = 0
	self._computing       = false  -- FIX 1: async guard
	self._connections     = {}
	self._noPathAt        = -999
	self._noPathCooldown  = 0.8    -- FIX 4: was 2.0s

	local blockedConn = self._path.Blocked:Connect(function(blockedIdx)
		if blockedIdx >= self._wpIndex then
			self:_requestCompute(self._destination)
		end
	end)
	table.insert(self._connections, blockedConn)

	-- FIX 6: auto-advance waypoints on MoveToFinished so we don't wait for
	-- the next Update() tick (eliminates the brief pause between waypoints)
	local finishedConn = self.Humanoid.MoveToFinished:Connect(function(reached)
		if not self._active or #self._waypoints == 0 then return end
		if reached then
			self._wpIndex += 1
			local wp = self._waypoints[self._wpIndex]
			if wp then
				if wp.Action == Enum.PathWaypointAction.Jump then
					self.Humanoid.Jump = true
				end
				self.Humanoid:MoveTo(wp.Position)
			else
				self:_onPathComplete()
			end
		end
	end)
	table.insert(self._connections, finishedConn)

	return self
end

-- ─── Public API ────────────────────────────────────────────────────────────

--[[
	MoveTo is called frequently (every 0.2s from Chase, every 0.3s from formation).
	FIX 2: Only recompute if destination moved more than MIN_RECOMPUTE_DIST.
	This means the NPC keeps smoothly following its current path while the
	player moves small amounts, rather than restarting the path from scratch.
--]]
function PathfindingController:MoveTo(destination: Vector3, onComplete: (() -> ())?)
	self._destination = destination
	self._onComplete  = onComplete
	self._active      = true

	-- Skip recompute if destination hasn't moved much
	if self._lastComputedDest then
		local delta = (destination - self._lastComputedDest).Magnitude
		if delta < MIN_RECOMPUTE_DIST then return end
	end

	-- Skip if inside noPath cooldown
	if (tick() - self._noPathAt) < self._noPathCooldown then return end

	self:_requestCompute(destination)
end

function PathfindingController:Stop()
	self._active           = false
	self._destination      = nil
	self._lastComputedDest = nil
	self._waypoints        = {}
	self._wpIndex          = 1
	self._stuckCount       = 0
	self._computing        = false
	if self.Humanoid then
		self.Humanoid:MoveTo(self.RootPart.Position)
	end
	clearDebugParts(self.NpcId)
end

function PathfindingController:Update(dt: number)
	if not self._active or #self._waypoints == 0 then return end

	local now        = tick()
	local currentPos = self.RootPart.Position
	local movedDist  = (currentPos - self._lastPos).Magnitude

	-- ── Stuck detection ──────────────────────────────────────────────────
	if movedDist > Config.Movement.StuckThreshold then
		self._lastPos     = currentPos
		self._lastMovedAt = now
		self._stuckCount  = 0
	elseif (now - self._lastMovedAt) > Config.Movement.StuckTimeout then
		self._lastMovedAt = now
		self._stuckCount += 1

		-- FIX 5: don't recalculate if we just computed a fresh path
		local freshPath = (now - self._lastComputedAt) < 0.5
		local inCooldown = (now - self._noPathAt) < self._noPathCooldown

		if not freshPath and not inCooldown and not self._computing then
			if self._stuckCount >= 3 then
				self._stuckCount = 0
				self:_unstick()
			else
				self:_requestCompute(self._destination)
			end
		end
		return
	end

	-- ── Waypoint advancement (backup — MoveToFinished handles most of this) ──
	local wp = self._waypoints[self._wpIndex]
	if not wp then
		self:_onPathComplete()
		return
	end

	local reachDist = Config.Movement.WaypointReachDist
	local flatDist  = Vector3.new(
		currentPos.X - wp.Position.X, 0, currentPos.Z - wp.Position.Z
	).Magnitude

	if flatDist <= reachDist then
		self._wpIndex += 1
		wp = self._waypoints[self._wpIndex]
		if not wp then
			self:_onPathComplete()
			return
		end
		if wp.Action == Enum.PathWaypointAction.Jump then
			self.Humanoid.Jump = true
		end
		self.Humanoid:MoveTo(wp.Position)
	end
end

-- ─── Private ───────────────────────────────────────────────────────────────

--[[
	FIX 1: Async compute — runs ComputeAsync in a task.spawn so it never
	blocks Heartbeat. The NPC keeps walking its old path during compute.
	Guard _computing prevents overlapping computes.
--]]
function PathfindingController:_requestCompute(destination: Vector3?)
	if not destination then return end
	if self._computing then return end  -- already computing, skip
	self._computing = true

	local startPos = self.RootPart.Position

	task.spawn(function()
		local success, err = pcall(function()
			self._path:ComputeAsync(startPos, destination)
		end)

		self._computing = false

		-- Guard: NPC might have died or stopped while we were computing
		if not self._active then return end

		if not success or self._path.Status ~= Enum.PathStatus.Success then
			if (tick() - self._noPathAt) >= self._noPathCooldown then
				-- Only warn occasionally, not every 0.2s
				warn("[Pathfinding] NoPath —", err or tostring(self._path.Status))
				self._noPathAt = tick()
			end
			-- Direct fallback for short open distances only
			local d = (self.RootPart.Position - destination).Magnitude
			if d < 15 then
				self.Humanoid:MoveTo(destination)
			end
			return
		end

		-- FIX 3: atomic swap — get new waypoints then swap in one step
		-- NPC was following old waypoints right up until this point
		local newWaypoints = self._path:GetWaypoints()
		if #newWaypoints < 2 then return end

		self._waypoints        = newWaypoints
		self._wpIndex          = 2
		self._lastComputedDest = destination
		self._lastComputedAt   = tick()
		self._lastPos          = self.RootPart.Position
		self._lastMovedAt      = tick()
		self._stuckCount       = 0

		drawWaypoints(self.NpcId, self._waypoints)

		local first = self._waypoints[self._wpIndex]
		if first then
			if first.Action == Enum.PathWaypointAction.Jump then
				self.Humanoid.Jump = true
			end
			self.Humanoid:MoveTo(first.Position)
		end
	end)
end

-- Unstick: path to a random point nearby, then resume original de.Debugstination
function PathfindingController:_unstick()
	if not self._destination then return end

	local root     = self.RootPart.Position
	local angle    = math.random() * math.pi * 2
	local midPoint = root + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
	local dest     = self._destination

	task.spawn(function()
		local success, _ = pcall(function()
			self._path:ComputeAsync(root, midPoint)
		end)

		if not self._active then return end

		if success and self._path.Status == Enum.PathStatus.Success then
			local wps = self._path:GetWaypoints()
			if #wps >= 2 then
				self._waypoints        = wps
				self._wpIndex          = 2
				self._lastComputedAt   = tick()
				self._lastPos          = root
				self._lastMovedAt      = tick()
				drawWaypoints(self.NpcId, self._waypoints)

				local first = self._waypoints[self._wpIndex]
				if first then self.Humanoid:MoveTo(first.Position) end

				-- After reaching midpoint, re-path to original destination
				self._onComplete = function()
					self._lastComputedDest = nil  -- force full recompute
					self:MoveTo(dest)
				end
			end
		else
			self._lastComputedDest = nil
			self:_requestCompute(dest)
		end

		self._computing = false
	end)
end

function PathfindingController:_onPathComplete()
	self._active    = false
	self._waypoints = {}
	clearDebugParts(self.NpcId)
	if self._onComplete then
		local cb = self._onComplete
		self._onComplete = nil
		cb()
	end
end

function PathfindingController:Destroy()
	self:Stop()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	self._connections = {}
end

return PathfindingController