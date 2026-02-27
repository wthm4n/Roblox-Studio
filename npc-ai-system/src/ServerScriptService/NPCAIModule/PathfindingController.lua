--[[
	PathfindingController.lua
	Wraps PathfindingService with:
	  - Jump / Climb / Swim support via AgentParameters
	  - Dynamic recalculation on block
	  - Stuck detection & recovery
	  - NoPath spam prevention (cooldown before retry)
	  - Debug path visualization
--]]

local PathfindingService = game:GetService("PathfindingService")
local RunService         = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)

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
		part.Size = Vector3.new(0.5, 0.5, 0.5)
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
			local beam = Instance.new("Part")
			beam.Size = Vector3.new(0.1, 0.1, dist)
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

-- ─── Constructor ───────────────────────────────────────────────────────────

function PathfindingController.new(npc: Model)
	local self = setmetatable({}, PathfindingController)

	self.NPC        = npc
	self.Humanoid   = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.RootPart   = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	self.NpcId      = npc.Name .. "_" .. tostring(npc:GetAttribute("NPCID") or math.random(1000, 9999))

	-- Smaller radius fits trusses. AgentCanClimb MUST be true for truss support.
	-- Low Climb cost = NPC prefers climbing over long detours.
	self._path = PathfindingService:CreatePath({
		AgentRadius     = 1.5,
		AgentHeight     = 5,
		AgentCanJump    = true,
		AgentCanClimb   = true,
		WaypointSpacing = 3,
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
	self._connections    = {}
	self._noPathAt       = -999   -- timestamp of last NoPath failure
	self._noPathCooldown = 3      -- seconds before retrying after NoPath

	-- Recalculate when something blocks the current path
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
	-- Respect NoPath cooldown — stop hammering a failed path
	if (tick() - self._noPathAt) < self._noPathCooldown then
		return
	end

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

	-- Stuck detection
	if movedDist > Config.Movement.StuckThreshold then
		self._lastPos     = currentPos
		self._lastMovedAt = now
	elseif (now - self._lastMovedAt) > Config.Movement.StuckTimeout then
		self._lastMovedAt = now
		if (now - self._noPathAt) >= self._noPathCooldown then
			self:_recalculate()
		end
		return
	end

	-- Advance to next waypoint when close enough
	local wp = self._waypoints[self._wpIndex]
	if not wp then
		self:_onPathComplete()
		return
	end

	local dist = (self.RootPart.Position - wp.Position).Magnitude
	if dist <= Config.Movement.WaypointReachDist then
		self._wpIndex += 1
		wp = self._waypoints[self._wpIndex]
		if not wp then
			self:_onPathComplete()
			return
		end
	end

	-- Trigger jump for jump waypoints
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
		-- Only warn once per cooldown window — no spam
		if (tick() - self._noPathAt) >= self._noPathCooldown then
			warn("[PathfindingController] NoPath —", err or self._path.Status,
				"— retrying in", self._noPathCooldown .. "s")
			self._noPathAt = tick()
		end

		-- Fallback: direct move for short distances (open flat areas)
		local directDist = (self.RootPart.Position - destination).Magnitude
		if directDist < 20 then
			self.Humanoid:MoveTo(destination)
		end
		return
	end

	self._waypoints   = self._path:GetWaypoints()
	self._wpIndex     = 2
	self._lastPos     = self.RootPart.Position
	self._lastMovedAt = tick()

	drawWaypoints(self.NpcId, self._waypoints)

	local first = self._waypoints[self._wpIndex]
	if first then
		self.Humanoid:MoveTo(first.Position)
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
		self._onComplete()
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