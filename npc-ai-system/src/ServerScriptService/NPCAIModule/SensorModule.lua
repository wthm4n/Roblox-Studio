--[[
	SensorModule.lua
	Handles all perception: nearest player detection,
	line-of-sight raycasting, environment scanning
	(water, low ceilings for crawl, climbable surfaces)
--]]

local Players    = game:GetService("Players")
local Workspace  = game:GetService("Workspace")

local SensorModule = {}
SensorModule.__index = SensorModule

-- Raycast params that ignore the NPC model itself
local function makeRayParams(model: Model)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { model }
	params.FilterType = Enum.RaycastFilterType.Exclude
	return params
end

function SensorModule.new(npc)
	local self = setmetatable({}, SensorModule)
	self._npc       = npc
	self._rayParams = makeRayParams(npc.Model)

	-- Cached results (updated each tick)
	self.NearestPlayer   = nil
	self.NearestDist     = math.huge
	self.HasLOS          = false     -- line-of-sight to nearest player
	self.InWater         = false
	self.CanCrawl        = false     -- low ceiling detected
	self.NearClimbable   = false
	return self
end

function SensorModule:Update()
	self:_scanPlayers()
	self:_scanEnvironment()
end

-- ─────────────────────────────────────────────
--  PLAYER SCAN
-- ─────────────────────────────────────────────

function SensorModule:_scanPlayers()
	local npc          = self._npc
	local origin       = npc.HRP.Position
	local aggroRange   = npc.Config.aggroRange
	local bestPlayer   = nil
	local bestDist     = math.huge

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not hrp then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local dist = (origin - hrp.Position).Magnitude
		if dist < aggroRange and dist < bestDist then
			bestDist   = dist
			bestPlayer = player
		end
	end

	self.NearestPlayer = bestPlayer
	self.NearestDist   = bestDist

	-- Line-of-sight check for nearest player
	if bestPlayer and bestPlayer.Character then
		local targetHRP = bestPlayer.Character:FindFirstChild("HumanoidRootPart")
		if targetHRP then
			self.HasLOS = self:_raycastLOS(origin, targetHRP.Position)
		else
			self.HasLOS = false
		end
	else
		self.HasLOS = false
	end
end

function SensorModule:_raycastLOS(from: Vector3, to: Vector3): boolean
	local dir    = to - from
	local result = Workspace:Raycast(from, dir, self._rayParams)
	-- If nothing hit (or hit target area), we have LOS
	if not result then return true end
	-- If hit something before reaching target, no LOS
	return result.Distance >= dir.Magnitude - 0.5
end

-- ─────────────────────────────────────────────
--  ENVIRONMENT SCAN
-- ─────────────────────────────────────────────

function SensorModule:_scanEnvironment()
	local npc    = self._npc
	local pos    = npc.HRP.Position

	-- Water check: raycast slightly below feet
	local downResult = Workspace:Raycast(pos, Vector3.new(0, -2, 0), self._rayParams)
	if downResult and downResult.Material == Enum.Material.Water then
		self.InWater = true
	else
		-- Also check if HRP is submerged
		local region = Region3.new(pos - Vector3.new(1,1,1), pos + Vector3.new(1,1,1))
		self.InWater = Workspace.Terrain:ReadVoxels(
			region, 4
		) ~= nil and downResult and downResult.Material == Enum.Material.Water
		-- Simple fallback
		self.InWater = downResult and downResult.Material == Enum.Material.Water or false
	end

	-- Low ceiling check: short upward ray → crawl needed
	local upResult = Workspace:Raycast(pos, Vector3.new(0, 2.5, 0), self._rayParams)
	self.CanCrawl = upResult ~= nil  -- something above within 2.5 studs

	-- Climbable surface: sideways raycast (all 4 dirs, short range)
	self.NearClimbable = false
	local dirs = {
		Vector3.new(1,0,0), Vector3.new(-1,0,0),
		Vector3.new(0,0,1), Vector3.new(0,0,-1),
	}
	for _, dir in ipairs(dirs) do
		local result = Workspace:Raycast(pos, dir * 1.5, self._rayParams)
		if result then
			local part = result.Instance
			if part:IsA("BasePart") and part.Size.Y > 4 then
				self.NearClimbable = true
				break
			end
		end
	end
end

-- ─────────────────────────────────────────────
--  KILL PART DETECTION
--  Returns true if a position is "dangerous"
-- ─────────────────────────────────────────────

function SensorModule:IsDangerous(position: Vector3): boolean
	-- Check for parts tagged "KillPart" or with CanTouch scripts
	-- that deal damage. We use a bounding overlap approach.
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { self._npc.Model }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local parts = Workspace:GetPartBoundsInBox(
		CFrame.new(position),
		Vector3.new(2, 2, 2),
		params
	)
	for _, part in ipairs(parts) do
		if part.Name == "KillPart"
		   or part:GetAttribute("IsKillPart")
		   or part:FindFirstChild("KillScript")
		then
			return true
		end
	end
	return false
end

return SensorModule
