--[[
	TargetSystem.lua

	DETECTION FIXES:
	  1. Multi-point LoS — fires rays at 3 heights on the player (ankles, torso,
	     head). Detected if ANY one ray clears. Previously a single ray to root
	     was blocked by props, terrain bumps, or the player's own base geometry.
	  2. FOV check uses flattened (Y=0) direction vectors so vertical height
	     difference between NPC and player doesn't shrink the effective cone.
	  3. Ray origin raised to +2.8 (eye level) and also tries +1.0 (chest)
	     as fallback, preventing the NPC's own collider from blocking its vision.
	  4. RaycastParams now also excludes all player characters so player
	     parts don't accidentally block the ray to that same player.
--]]

local Players = game:GetService("Players")
local Config  = require(game.ReplicatedStorage.Shared.Config)

local TargetSystem = {}
TargetSystem.__index = TargetSystem

-- Heights to sample on the TARGET (player) for LoS checks
local TARGET_SAMPLE_HEIGHTS = { 0.3, 2.0, 4.8 }  -- ankles, torso, head (studs above root.Y)
-- Heights to cast FROM on the NPC
local ORIGIN_HEIGHTS = { 2.8, 1.0 }               -- eye level, chest

function TargetSystem.new(npc: Model)
	local self = setmetatable({}, TargetSystem)

	self.NPC      = npc
	self.RootPart = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	self.Humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid

	self._threatTable    = {}
	self._losCache       = {}
	self._ignoredPlayers = {}

	self.CurrentTarget  = nil :: Player?
	self.LastKnownPos   = nil :: Vector3?
	self.TimeSinceSeen  = 0

	-- FIX 3+4: exclude NPC itself AND all player characters from raycasts
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self:_rebuildRayFilter()

	-- Keep filter up to date as players join/leave
	Players.PlayerAdded:Connect(function() self:_rebuildRayFilter() end)
	Players.PlayerRemoving:Connect(function() self:_rebuildRayFilter() end)

	return self
end

-- ─── Public API ────────────────────────────────────────────────────────────

function TargetSystem:RegisterThreat(player: Player, amount: number)
	if not player or not player:IsA("Player") then return end
	self._threatTable[player] = (self._threatTable[player] or 0) + amount
end

function TargetSystem:ClearThreat()
	self._threatTable = {}
end

function TargetSystem:ClearTarget()
	self.CurrentTarget  = nil
	self.LastKnownPos   = nil
	self.TimeSinceSeen  = 0
end

function TargetSystem:IgnorePlayer(player: Player)
	self._ignoredPlayers[player] = true
end

function TargetSystem:UnignorePlayer(player: Player)
	self._ignoredPlayers[player] = nil
end

function TargetSystem:IgnoreAll()
	for _, player in ipairs(Players:GetPlayers()) do
		self._ignoredPlayers[player] = true
	end
end

function TargetSystem:UnignoreAll()
	self._ignoredPlayers = {}
end

function TargetSystem:Update(dt: number): (Player?, Vector3?)
	self:_decayThreats(dt)

	local best         = self:_selectBestTarget()
	self.CurrentTarget = best

	if best then
		local char = best.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			self.LastKnownPos  = root.Position
			self.TimeSinceSeen = 0
		end
	else
		if self.LastKnownPos then
			self.TimeSinceSeen += dt
			if self.TimeSinceSeen >= Config.Detection.LoseTargetTime then
				self.LastKnownPos  = nil
				self.TimeSinceSeen = 0
			end
		end
	end

	return self.CurrentTarget, self.LastKnownPos
end

--[[
	HasLineOfSight — FIX 1+3: multi-origin, multi-target-height raycast.
	Tries each combination of origin height and target height.
	Returns true as soon as ANY ray clears — much more reliable than a
	single root-to-root ray that any small prop can block.
--]]
function TargetSystem:HasLineOfSight(targetPos: Vector3): boolean
	local npcBase = self.RootPart.Position

	for _, originY in ipairs(ORIGIN_HEIGHTS) do
		local origin = Vector3.new(npcBase.X, npcBase.Y + originY, npcBase.Z)

		for _, targetOffsetY in ipairs(TARGET_SAMPLE_HEIGHTS) do
			local samplePos = Vector3.new(targetPos.X, targetPos.Y + targetOffsetY, targetPos.Z)
			local direction = samplePos - origin
			local result    = workspace:Raycast(origin, direction, self._rayParams)
			if result == nil then
				return true  -- at least one ray got through
			end
		end
	end

	return false
end

-- ─── Private ───────────────────────────────────────────────────────────────

function TargetSystem:_selectBestTarget(): Player?
	local highestThreat = 0
	local threatTarget  = nil :: Player?
	local nearestDist   = math.huge
	local nearestTarget = nil :: Player?

	for _, player in ipairs(Players:GetPlayers()) do
		if not self:_isValidTarget(player) then continue end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not root then continue end

		local dist        = (self.RootPart.Position - root.Position).Magnitude
		local inHearRange = dist <= Config.Detection.HearRange
		local inSight     = dist <= Config.Detection.SightRange
			and self:_inFOV(root.Position)
			and self:_checkLoS(player, root.Position)

		if not (inHearRange or inSight) then continue end

		local threat = self._threatTable[player] or 0
		if threat > highestThreat then
			highestThreat = threat
			threatTarget  = player
		end

		if dist < nearestDist then
			nearestDist   = dist
			nearestTarget = player
		end
	end

	return threatTarget or nearestTarget
end

function TargetSystem:_isValidTarget(player: Player): boolean
	if self._ignoredPlayers[player] then return false end
	if not player.Character then return false end
	local hum = player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	if not hum or hum.Health <= 0 then return false end
	if player.Character:GetAttribute("InSafeZone") then return false end
	return true
end

--[[
	_inFOV — FIX 2: flatten both vectors to Y=0 before computing the dot
	product. Without this, a player standing on a hill or platform above/below
	the NPC has their angle artificially inflated by the vertical component,
	making them appear "outside" the cone even when directly ahead horizontally.
--]]
function TargetSystem:_inFOV(targetPos: Vector3): boolean
	local npcPos   = self.RootPart.Position

	-- Flatten to horizontal plane
	local toTarget = Vector3.new(
		targetPos.X - npcPos.X,
		0,
		targetPos.Z - npcPos.Z
	)
	if toTarget.Magnitude < 0.01 then return true end  -- player is right on top of NPC
	toTarget = toTarget.Unit

	local lookVec = self.RootPart.CFrame.LookVector
	local flatLook = Vector3.new(lookVec.X, 0, lookVec.Z)
	if flatLook.Magnitude < 0.01 then return true end
	flatLook = flatLook.Unit

	local dot       = flatLook:Dot(toTarget)
	local halfAngle = math.rad(Config.Detection.SightAngle / 2)
	return dot >= math.cos(halfAngle)
end

function TargetSystem:_checkLoS(player: Player, targetPos: Vector3): boolean
	local now   = tick()
	local cache = self._losCache[player]
	if cache and (now - cache.time) < Config.Detection.RaycastCooldown then
		return cache.result
	end
	local result = self:HasLineOfSight(targetPos)
	self._losCache[player] = { result = result, time = now }
	return result
end

function TargetSystem:_decayThreats(dt: number)
	for player, threat in pairs(self._threatTable) do
		local newThreat = threat - Config.Combat.ThreatDecayRate * dt
		if newThreat <= 0 or not player.Parent then
			self._threatTable[player] = nil
		else
			self._threatTable[player] = newThreat
		end
	end
end

-- Rebuild the raycast exclusion list: NPC model + all current player characters
function TargetSystem:_rebuildRayFilter()
	local exclude = { self.NPC }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	self._rayParams.FilterDescendantsInstances = exclude
end

function TargetSystem:Destroy()
	self._threatTable    = {}
	self._losCache       = {}
	self._ignoredPlayers = {}
	self.CurrentTarget   = nil
end

return TargetSystem