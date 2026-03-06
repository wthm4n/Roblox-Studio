-- SpawnPoint.lua
-- Represents a single spawn location in the world.
-- Tracks cooldown, usage stats, and validity checks.

local SpawnPoint = {}
SpawnPoint.__index = SpawnPoint

local DEFAULT_COOLDOWN   = 12   -- seconds between uses
local PROXIMITY_BLOCK_RADIUS = 20  -- studs; won't spawn if player too close

export type SpawnPointConfig = {
	part: BasePart,            -- the Part in the world
	cooldown: number?,         -- override default cooldown
	tags: {string}?,           -- e.g. {"indoor","flank","elite_only"}
	weight: number?,           -- higher = preferred by SpawnPool
}

function SpawnPoint.new(config: SpawnPointConfig)
	assert(config and config.part, "[SpawnPoint] config.part is required")

	local self = setmetatable({}, SpawnPoint)

	self.Part         = config.part
	self.Cooldown     = config.cooldown or DEFAULT_COOLDOWN
	self.Tags         = config.tags or {}
	self.Weight       = config.weight or 1
	self.IsActive     = true

	-- Internal state
	self._lastUsedAt  = -math.huge   -- tick() timestamp
	self._spawnCount  = 0

	return self
end

-- ──────────────────────────────────────────────
--  Validity
-- ──────────────────────────────────────────────

-- Returns true if this point is off cooldown
function SpawnPoint:IsReady(): boolean
	if not self.IsActive then return false end
	return (tick() - self._lastUsedAt) >= self.Cooldown
end

--[[
	IsValidFor(playerPositions: {Vector3}) -> boolean
	Returns false if any player is within PROXIMITY_BLOCK_RADIUS.
	Prevents enemies from spawning in the player's face.
]]
function SpawnPoint:IsValidFor(playerPositions: {Vector3}): boolean
	if not self:IsReady() then return false end
	if not self.Part or not self.Part.Parent then return false end

	local origin = self.Part.Position

	for _, pos in ipairs(playerPositions) do
		if (origin - pos).Magnitude <= PROXIMITY_BLOCK_RADIUS then
			return false
		end
	end

	return true
end

-- ──────────────────────────────────────────────
--  Usage
-- ──────────────────────────────────────────────

-- Call this after spawning an enemy at this point
function SpawnPoint:MarkUsed()
	self._lastUsedAt = tick()
	self._spawnCount += 1
end

function SpawnPoint:GetPosition(): Vector3
	return self.Part.Position
end

function SpawnPoint:GetCFrame(): CFrame
	return self.Part.CFrame
end

-- Returns true if this point has all of the given tags
function SpawnPoint:HasTags(required: {string}): boolean
	local tagSet = {}
	for _, t in ipairs(self.Tags) do tagSet[t] = true end
	for _, t in ipairs(required) do
		if not tagSet[t] then return false end
	end
	return true
end

function SpawnPoint:GetDebugInfo(): table
	return {
		Position   = self.Part.Position,
		IsReady    = self:IsReady(),
		Weight     = self.Weight,
		Tags       = table.concat(self.Tags, ", "),
		SpawnCount = self._spawnCount,
		Cooldown   = string.format("%.1fs remaining",
			math.max(0, self.Cooldown - (tick() - self._lastUsedAt))),
	}
end

return SpawnPoint
