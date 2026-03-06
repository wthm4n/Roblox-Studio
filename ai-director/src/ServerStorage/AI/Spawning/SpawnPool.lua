-- SpawnPool.lua
-- Manages a collection of SpawnPoints.
-- Handles registration, filtering, and weighted selection.

local SpawnPool = {}
SpawnPool.__index = SpawnPool

-- Import SpawnPoint type (runtime reference optional — used for type checks)
-- local SpawnPoint = require(script.Parent.SpawnPoint)

function SpawnPool.new()
	local self = setmetatable({}, SpawnPool)
	self._points = {}   -- array of SpawnPoint instances
	return self
end

-- ──────────────────────────────────────────────
--  Registration
-- ──────────────────────────────────────────────

function SpawnPool:Register(spawnPoint)
	assert(spawnPoint and spawnPoint.IsReady, "[SpawnPool] Invalid SpawnPoint")
	table.insert(self._points, spawnPoint)
end

function SpawnPool:Unregister(spawnPoint)
	for i, pt in ipairs(self._points) do
		if pt == spawnPoint then
			table.remove(self._points, i)
			return
		end
	end
end

-- Toggle a point's active state without removing it from the pool
function SpawnPool:SetActive(spawnPoint, active: boolean)
	spawnPoint.IsActive = active
end

-- ──────────────────────────────────────────────
--  Querying
-- ──────────────────────────────────────────────

--[[
	GetValidPoints(playerPositions, requiredTags?) -> {SpawnPoint}
	Returns all points that pass IsValidFor() and optionally match tags.
]]
function SpawnPool:GetValidPoints(playerPositions: {Vector3}, requiredTags: {string}?): table
	local valid = {}
	for _, pt in ipairs(self._points) do
		if pt:IsValidFor(playerPositions) then
			if requiredTags == nil or pt:HasTags(requiredTags) then
				table.insert(valid, pt)
			end
		end
	end
	return valid
end

--[[
	PickWeightedRandom(points) -> SpawnPoint | nil
	Selects a spawn point using weighted probability.
	Higher Weight values are proportionally more likely to be chosen.
]]
function SpawnPool:PickWeightedRandom(points: table)
	if #points == 0 then return nil end

	local totalWeight = 0
	for _, pt in ipairs(points) do
		totalWeight += pt.Weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0

	for _, pt in ipairs(points) do
		cumulative += pt.Weight
		if roll <= cumulative then
			return pt
		end
	end

	-- Fallback: return last valid point
	return points[#points]
end

--[[
	GetBestSpawnPoint(playerPositions, requiredTags?) -> SpawnPoint | nil
	Convenience: filter then weighted-pick in one call.
]]
function SpawnPool:GetBestSpawnPoint(playerPositions: {Vector3}, requiredTags: {string}?): table
	local valid = self:GetValidPoints(playerPositions, requiredTags)
	return self:PickWeightedRandom(valid)
end

-- Returns total registered points
function SpawnPool:Count(): number
	return #self._points
end

-- Returns count of currently ready (off-cooldown, active) points
function SpawnPool:ReadyCount(playerPositions: {Vector3}?): number
	local n = 0
	for _, pt in ipairs(self._points) do
		if playerPositions then
			if pt:IsValidFor(playerPositions) then n += 1 end
		else
			if pt:IsReady() then n += 1 end
		end
	end
	return n
end

function SpawnPool:GetAllPoints(): table
	return self._points
end

function SpawnPool:GetDebugInfo(): table
	return {
		TotalPoints  = self:Count(),
		ReadyPoints  = self:ReadyCount(),
	}
end

return SpawnPool
