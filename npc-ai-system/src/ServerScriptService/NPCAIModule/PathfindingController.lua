--[[
	PathfindingController.lua
	Fixed for:
	  - Maze / wall navigation
	  - Tighter agent size for narrow corridors
	  - Smarter stuck recovery (tries intermediate points)
	  - Jump / Climb / Swim support
	  - NoPath spam prevention
	  - Debug visualization
--]]

local PathfindingService = game:GetService("PathfindingService")

local Config = require(script.Parent.Parent.Shared.Config)

local PathfindingController = {}
PathfindingController.__index = PathfindingController

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

	--[[
		AgentRadius 1.0 — tight enough to fit through doorways and maze corridors.
		Roblox default character is ~1 stud wide each side.
		Using 2.0 was causing NoPath in any corridor < 4 studs wide.

		WaypointSpacing 2 — more waypoints = smoother cornering around walls.
		Dense waypoints mean the NPC turns earlier instead of walking into corners.
	--]]
	self._path = PathfindingService:CreatePath({
		AgentRadius     = 1.0,
		AgentHeight     = 5,
		AgentCanJump    = true,
		AgentCanClimb   = true,
		WaypointSpacing = 2,
		Costs = {
			Water = 20,
			Climb = 0.5,
		},
	})

	self._waypoints      = {}
	self._wpIndex        = 1
	self._active         = false
	self._destination    = nil
	self._lastPos        = Vector3.zero
	self._lastMovedAt    = 0
	self._stuckCount     = 0       -- how many times stuck in a row
	self._connections    = {}
	self._noPathAt       = -999
	self._noPathCooldown = 2

	local blockedConn = self._path.Blocked:Connect(function(blockedIdx)
		if blockedIdx >= self._wpIndex then
			self:_recalculate()
		end
	end)
	table.insert(self._connections, blockedConn)

	return self
end

-- ─── Public API ────────────────────────────────────────────────────────────

function PathfindingController:MoveTo(destination: Vector3, onComplete: (() -> ())?)
	if (tick() - self._noPathAt) < self._noPathCooldown then return end

	self._destination = destination
	self._onComplete  = onComplete
	self._active      = true
	self:_computeAndMove(destination)
end

function PathfindingController:Stop()
	self._active      = false
	self._destination = nil
	self._waypoints   = {}
	self._wpIndex     = 1
	self._stuckCount  = 0
	if self.Humanoid then
		self.Humanoid:MoveTo(self.RootPart.Position)
	end
	clearDebugParts(self.NpcId)
end

function PathfindingController:Update(dt: number)
	if not self._active or #self._waypoints == 0 then return end

	local now        = tick()
	local currentPos = self.RootPart.Position

	-- ── Stuck detection ──────────────────────────────────────────────────
	local movedDist = (currentPos - self._lastPos).Magnitude

	if movedDist > Config.Movement.StuckThreshold then
		self._lastPos     = currentPos
		self._lastMovedAt = now
		self._stuckCount  = 0
	elseif (now - self._lastMovedAt) > Config.Movement.StuckTimeout then
		self._lastMovedAt = now
		self._stuckCount += 1

		if (now - self._noPathAt) >= self._noPathCooldown then
			if self._stuckCount >= 3 then
				-- Stuck repeatedly → try a random nearby intermediate point
				-- to "unstick" from the wall before pathing to target
				self._stuckCount = 0
				self:_unstick()
			else
				self:_recalculate()
			end
		end
		return
	end

	-- ── Waypoint advancement ─────────────────────────────────────────────
	local wp = self._waypoints[self._wpIndex]
	if not wp then
		self:_onPathComplete()
		return
	end

	-- Use tighter reach distance so NPC properly turns corners
	-- instead of cutting through walls
	local reachDist = Config.Movement.WaypointReachDist
	local dist = (Vector3.new(currentPos.X, 0, currentPos.Z)
		- Vector3.new(wp.Position.X, 0, wp.Position.Z)).Magnitude

	if dist <= reachDist then
		self._wpIndex += 1
		wp = self._waypoints[self._wpIndex]
		if not wp then
			self:_onPathComplete()
			return
		end
	end

	if wp.Action == Enum.PathWaypointAction.Jump then
		self.Humanoid.Jump = true
	end

	self.Humanoid:MoveTo(wp.Position)
end

-- ─── Private ───────────────────────────────────────────────────────────────

function PathfindingController:_computeAndMove(destination: Vector3)
	local success, err = pcall(function()
		self._path:ComputeAsync(self.RootPart.Position, destination)
	end)

	if not success or self._path.Status ~= Enum.PathStatus.Success then
		if (tick() - self._noPathAt) >= self._noPathCooldown then
			warn("[Pathfinding] NoPath to destination —", err or self._path.Status)
			self._noPathAt = tick()
		end
		-- Direct fallback only for very short open distances
		local d = (self.RootPart.Position - destination).Magnitude
		if d < 15 then
			self.Humanoid:MoveTo(destination)
		end
		return
	end

	self._waypoints   = self._path:GetWaypoints()
	self._wpIndex     = 2
	self._lastPos     = self.RootPart.Position
	self._lastMovedAt = tick()
	self._stuckCount  = 0

	drawWaypoints(self.NpcId, self._waypoints)

	local first = self._waypoints[self._wpIndex]
	if first then
		self.Humanoid:MoveTo(first.Position)
	end
end

-- Unstick: path to a random point nearby, then resume original destination
function PathfindingController:_unstick()
	if not self._destination then return end

	local root   = self.RootPart.Position
	local angle  = math.random() * math.pi * 2
	-- Try a point 6 studs away in a random direction
	local midPoint = root + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
	local dest     = self._destination

	-- Path to midpoint first
	local success, _ = pcall(function()
		self._path:ComputeAsync(root, midPoint)
	end)

	if success and self._path.Status == Enum.PathStatus.Success then
		self._waypoints   = self._path:GetWaypoints()
		self._wpIndex     = 2
		self._lastPos     = root
		self._lastMovedAt = tick()
		drawWaypoints(self.NpcId, self._waypoints)

		local first = self._waypoints[self._wpIndex]
		if first then
			self.Humanoid:MoveTo(first.Position)
		end

		-- After reaching midpoint, re-path to original destination
		self._onComplete = function()
			self:MoveTo(dest)
		end
	else
		-- Even midpoint failed — just try the destination again
		self:_computeAndMove(dest)
	end
end

function PathfindingController:_recalculate()
	if not self._destination then return end
	self:_computeAndMove(self._destination)
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