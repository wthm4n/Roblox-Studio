--[[
	TargetSystem.lua
	Handles:
	  - Nearest-player detection within sight range/cone
	  - Threat tracking (who attacked me?)
	  - Line-of-sight raycasting
	  - Safe-zone & dead player filtering
	  - Returns the highest-priority target each tick
--]]

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local TargetSystem = {}
TargetSystem.__index = TargetSystem

-- ─── Constructor ───────────────────────────────────────────────────────────

function TargetSystem.new(npc: Model)
	local self = setmetatable({}, TargetSystem)

	self.NPC         = npc
	self.RootPart    = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	self.Humanoid    = npc:FindFirstChildOfClass("Humanoid") :: Humanoid

	-- { [Player]: number }  threat score
	self._threatTable   = {}
	-- Last time LoS was checked per player
	self._losCache      = {}  -- { [Player]: { result: bool, time: number } }

	self.CurrentTarget  = nil :: Player?
	self.LastKnownPos   = nil :: Vector3?
	self.TimeSinceSeen  = 0

	-- Ignore parts for raycasting (this NPC itself)
	self._rayParams = RaycastParams.new()
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self._rayParams.FilterDescendantsInstances = { npc }

	return self
end

-- ─── Public API ────────────────────────────────────────────────────────────

-- Call this when the NPC takes damage from a player (pass the Player object)
function TargetSystem:RegisterThreat(player: Player, amount: number)
	if not player or not player:IsA("Player") then return end
	self._threatTable[player] = (self._threatTable[player] or 0) + amount
end

-- Main update — call each tick or on a timer
-- Returns the best target Player or nil
function TargetSystem:Update(dt: number): (Player?, Vector3?)
	self:_decayThreats(dt)

	local best      = self:_selectBestTarget()
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

-- Check if an arbitrary position can be seen (used externally if needed)
function TargetSystem:HasLineOfSight(targetPos: Vector3): boolean
	local origin    = self.RootPart.Position + Vector3.new(0, 1.5, 0) -- eye level
	local direction = targetPos - origin
	local result    = workspace:Raycast(origin, direction, self._rayParams)
	-- If nothing was hit, LoS is clear (open air to target)
	return result == nil
end

-- ─── Private ───────────────────────────────────────────────────────────────

function TargetSystem:_selectBestTarget(): Player?
	-- Priority: highest threat first, then nearest visible
	local highestThreat  = 0
	local threatTarget   = nil :: Player?
	local nearestDist    = math.huge
	local nearestTarget  = nil :: Player?

	for _, player in ipairs(Players:GetPlayers()) do
		if not self:_isValidTarget(player) then continue end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not root then continue end

		local dist = (self.RootPart.Position - root.Position).Magnitude

		-- Check hear range (no LoS needed)
		local inHearRange = dist <= Config.Detection.HearRange

		-- Check sight cone + LoS
		local inSight = dist <= Config.Detection.SightRange
			and self:_inFOV(root.Position)
			and self:_checkLoS(player, root.Position)

		if not (inHearRange or inSight) then continue end

		-- Threat priority
		local threat = self._threatTable[player] or 0
		if threat > highestThreat then
			highestThreat = threat
			threatTarget  = player
		end

		-- Nearest fallback
		if dist < nearestDist then
			nearestDist   = dist
			nearestTarget = player
		end
	end

	return threatTarget or nearestTarget
end

function TargetSystem:_isValidTarget(player: Player): boolean
	if not player.Character then return false end

	local hum = player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	if not hum or hum.Health <= 0 then return false end

	-- Safe zone: check attribute on character or zone tag
	if player.Character:GetAttribute("InSafeZone") then return false end

	return true
end

function TargetSystem:_inFOV(targetPos: Vector3): boolean
	local toTarget = (targetPos - self.RootPart.Position).Unit
	local lookVec  = self.RootPart.CFrame.LookVector
	local dot      = lookVec:Dot(toTarget)
	local halfAngle = math.rad(Config.Detection.SightAngle / 2)
	return dot >= math.cos(halfAngle)
end

function TargetSystem:_checkLoS(player: Player, targetPos: Vector3): boolean
	local now   = tick()
	local cache = self._losCache[player]

	-- Use cached result within cooldown window
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

function TargetSystem:Destroy()
	self._threatTable = {}
	self._losCache    = {}
	self.CurrentTarget = nil
end

return TargetSystem
