-- NPCAIService.lua
-- Place as a ModuleScript in ServerScriptService or ReplicatedStorage
-- Usage: require(this)(npcModel, targetPlayer)

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local NPCAIService = {}
NPCAIService.__index = NPCAIService

-- ─── CONFIG ───────────────────────────────────────────────────────────────────
local CFG = {
	UPDATE_RATE        = 0.1,   -- seconds between path recalculates
	WAYPOINT_REACH_R   = 3,     -- studs to consider waypoint reached
	STUCK_TIMEOUT      = 2,     -- seconds before considered "stuck"
	STUCK_JUMP_TRIES   = 3,     -- jump attempts before full repath
	SWIM_DETECT_DIST   = 2,     -- studs below surface to detect water
	CROUCH_HEIGHT_MAX  = 4,     -- if obstacle gap < this, crouch
	CLIMB_ANGLE_MIN    = 45,    -- degrees incline before climb mode
	FOLLOW_STOP_DIST   = 5,     -- studs from target to stop following
	AGENT_HEIGHT       = 5,
	AGENT_RADIUS       = 2,
	AGENT_JUMP         = 7.2,
}

-- ─── CONSTRUCTOR ──────────────────────────────────────────────────────────────
function NPCAIService.new(npcModel, targetPlayer)
	assert(npcModel and npcModel:IsA("Model"), "NPCAIService: npcModel must be a Model")
	assert(npcModel.PrimaryPart,               "NPCAIService: npcModel needs a PrimaryPart (HumanoidRootPart)")

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "NPCAIService: npcModel needs a Humanoid")

	local self = setmetatable({}, NPCAIService)
	self.npc          = npcModel
	self.root         = npcModel.PrimaryPart
	self.humanoid     = humanoid
	self.target       = targetPlayer   -- Player instance
	self.active       = true
	self._path        = nil
	self._waypoints   = {}
	self._wpIndex     = 1
	self._lastPos     = self.root.Position
	self._stuckTimer  = 0
	self._stuckJumps  = 0
	self._isCrouching = false
	self._isClimbing  = false
	self._isSwimming  = false
	self._connections = {}

	-- Pathfinding agent params
	self._agentParams = {
		AgentHeight    = CFG.AGENT_HEIGHT,
		AgentRadius    = CFG.AGENT_RADIUS,
		AgentCanJump   = true,
		AgentCanClimb  = true,
		WaypointSpacing = 2,
	}

	self:_start()
	return self
end

-- ─── INTERNAL ─────────────────────────────────────────────────────────────────

function NPCAIService:_getTargetPosition()
	if not self.target then return nil end
	local char = self.target.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

function NPCAIService:_computePath(goal)
	local path = PathfindingService:CreatePath(self._agentParams)
	local ok, err = pcall(function()
		path:ComputeAsync(self.root.Position, goal)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		return path
	end
	return nil
end

function NPCAIService:_followWaypoints()
	local wps = self._waypoints
	if not wps or #wps == 0 then return end

	local wp = wps[self._wpIndex]
	if not wp then return end

	local dist = (self.root.Position - wp.Position).Magnitude

	-- Reached waypoint
	if dist <= CFG.WAYPOINT_REACH_R then
		self._wpIndex += 1
		if self._wpIndex > #wps then
			self._waypoints = {}
			return
		end
		wp = wps[self._wpIndex]
	end

	-- Jump action waypoints
	if wp.Action == Enum.PathWaypointAction.Jump then
		self.humanoid.Jump = true
	end

	-- Move toward waypoint
	self.humanoid:MoveTo(wp.Position)
end

-- Detect if NPC is in water via terrain material
function NPCAIService:_detectSwimming()
	local pos = self.root.Position
	local regionSize = Vector3.new(1, 1, 1)
	local region = Region3.new(pos - regionSize/2, pos + regionSize/2)
	local materials = workspace.Terrain:ReadVoxels(region, 4)
	-- Simple check: look slightly above feet
	local rayOrigin = pos + Vector3.new(0, 1, 0)
	local rayDir = Vector3.new(0, -CFG.SWIM_DETECT_DIST, 0)
	local result = workspace:Raycast(rayOrigin, rayDir, RaycastParams.new())
	if result and result.Material == Enum.Material.Water then
		return true
	end
	-- fallback: check humanoid FloorMaterial
	return self.humanoid.FloorMaterial == Enum.Material.Water
end

-- Detect if something is low overhead → crouch
function NPCAIService:_detectCrouchNeeded()
	local ray = workspace:Raycast(
		self.root.Position,
		Vector3.new(0, CFG.CROUCH_HEIGHT_MAX, 0),
		RaycastParams.new()
	)
	return ray ~= nil -- something above within crouch height
end

-- Detect steep incline → climbing
function NPCAIService:_detectClimbing()
	local floorRay = workspace:Raycast(
		self.root.Position,
		Vector3.new(0, -3, 0),
		RaycastParams.new()
	)
	if floorRay then
		local normal = floorRay.Normal
		local angle = math.deg(math.acos(normal:Dot(Vector3.new(0,1,0))))
		return angle >= CFG.CLIMB_ANGLE_MIN
	end
	return false
end

function NPCAIService:_applySwimming(swimming)
	if swimming == self._isSwimming then return end
	self._isSwimming = swimming
	if swimming then
		-- Increase speed slightly, make humanoid "float"
		self.humanoid.WalkSpeed = 10
		-- Jump to "swim stroke"
		self.humanoid.Jump = true
	else
		self.humanoid.WalkSpeed = 16
	end
end

function NPCAIService:_applyCrouch(crouch)
	if crouch == self._isCrouching then return end
	self._isCrouching = crouch
	if crouch then
		-- Scale humanoid down to simulate crouch
		self.humanoid.HipHeight = 0.5
		self.humanoid.WalkSpeed = 8
	else
		self.humanoid.HipHeight = 2
		self.humanoid.WalkSpeed = 16
	end
end

function NPCAIService:_stuckCheck(dt)
	local moved = (self.root.Position - self._lastPos).Magnitude
	self._lastPos = self.root.Position

	if moved < 0.3 and #self._waypoints > 0 then
		self._stuckTimer += dt
		if self._stuckTimer >= CFG.STUCK_TIMEOUT then
			self._stuckJumps += 1
			self.humanoid.Jump = true
			self._stuckTimer = 0
			if self._stuckJumps >= CFG.STUCK_JUMP_TRIES then
				-- Force full repath
				self._waypoints = {}
				self._stuckJumps = 0
			end
		end
	else
		self._stuckTimer = 0
	end
end

-- ─── MAIN LOOP ────────────────────────────────────────────────────────────────

function NPCAIService:_start()
	local timer = 0

	local conn = RunService.Heartbeat:Connect(function(dt)
		if not self.active then return end
		if not self.npc.Parent then self:destroy(); return end
		if self.humanoid.Health <= 0 then self:destroy(); return end

		timer += dt

		-- Environment sensing every frame
		local swimming = self:_detectSwimming()
		local crouch   = self:_detectCrouchNeeded()
		self:_applySwimming(swimming)
		self:_applyCrouch(crouch)
		self:_stuckCheck(dt)

		-- Repath at fixed interval
		if timer >= CFG.UPDATE_RATE then
			timer = 0
			local goal = self:_getTargetPosition()
			if goal then
				local distToTarget = (self.root.Position - goal).Magnitude
				if distToTarget <= CFG.FOLLOW_STOP_DIST then
					-- Close enough, stop
					self.humanoid:MoveTo(self.root.Position)
					self._waypoints = {}
				else
					local path = self:_computePath(goal)
					if path then
						self._waypoints = path:GetWaypoints()
						self._wpIndex   = 2 -- skip first (NPC's own position)
					else
						-- Fallback: direct move
						self.humanoid:MoveTo(goal)
					end
				end
			end
		end

		-- Follow waypoints every frame
		self:_followWaypoints()

		-- Swimming stroke (periodic jump to stay afloat)
		if self._isSwimming then
			if timer % 0.8 < dt then
				self.humanoid.Jump = true
			end
		end
	end)

	table.insert(self._connections, conn)
end

-- ─── PUBLIC API ───────────────────────────────────────────────────────────────

--- Change the follow target
function NPCAIService:setTarget(player)
	self.target = player
end

--- Pause AI
function NPCAIService:pause()
	self.active = false
	self.humanoid:MoveTo(self.root.Position)
end

--- Resume AI
function NPCAIService:resume()
	self.active = true
end

--- Destroy the AI and clean up
function NPCAIService:destroy()
	self.active = false
	for _, c in ipairs(self._connections) do
		c:Disconnect()
	end
	self._connections = {}
end

-- ─── MODULE CALL SHORTCUT ─────────────────────────────────────────────────────
-- Lets you do: require(NPCAIService)(npcModel, player)
return setmetatable(NPCAIService, {
	__call = function(_, npcModel, targetPlayer)
		return NPCAIService.new(npcModel, targetPlayer)
	end
})