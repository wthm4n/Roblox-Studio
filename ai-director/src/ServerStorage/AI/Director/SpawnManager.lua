-- SpawnManager.lua
-- Handles enemy spawning: point selection, cooldowns, NPC instantiation.
-- Works with SpawnPool to pick valid spawn points.

local SpawnManager = {}
SpawnManager.__index = SpawnManager

-- ──────────────────────────────────────────────
--  Config
-- ──────────────────────────────────────────────

-- Base seconds between any spawn event (before modifiers)
local BASE_SPAWN_INTERVAL   = 8
local ELITE_SPAWN_INTERVAL  = 25
local MAX_ACTIVE_ENEMIES    = 20
local MAX_ACTIVE_ELITES     = 3

-- NPC model names inside ReplicatedStorage/Enemies (example)
local ENEMY_TEMPLATES = {
	standard = "EnemyGrunt",
	heavy    = "EnemyHeavy",
	flanker  = "EnemyFlanker",
}
local ELITE_TEMPLATES = {
	"EnemyElite",
	"EnemyBoss",
}

-- ──────────────────────────────────────────────
--  Constructor
-- ──────────────────────────────────────────────
function SpawnManager.new(spawnPool)
	assert(spawnPool, "[SpawnManager] spawnPool is required")

	local self = setmetatable({}, SpawnManager)

	self._pool             = spawnPool
	self._activeEnemies    = {}    -- {model, type, spawnedAt}
	self._lastSpawnTime    = -math.huge
	self._lastEliteTime    = -math.huge
	self._spawnRateModifier = 1.0  -- from DifficultyScaler

	-- Callback hooks (set by Director)
	self.OnEnemySpawned    = nil   -- fn(model, spawnType, position)
	self.OnEnemyDied       = nil   -- fn(model)

	return self
end

-- ──────────────────────────────────────────────
--  Internal Helpers
-- ──────────────────────────────────────────────

function SpawnManager:_getPlayerPositions(): {Vector3}
	local positions = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then table.insert(positions, root.Position) end
		end
	end
	return positions
end

function SpawnManager:_countByType(enemyType: string): number
	local n = 0
	for _, entry in ipairs(self._activeEnemies) do
		if entry.type == enemyType then n += 1 end
	end
	return n
end

function SpawnManager:_cleanupDead()
	local alive = {}
	for _, entry in ipairs(self._activeEnemies) do
		local hum = entry.model and entry.model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			table.insert(alive, entry)
		else
			if self.OnEnemyDied then
				pcall(self.OnEnemyDied, entry.model)
			end
		end
	end
	self._activeEnemies = alive
end

-- Clones an NPC template from ReplicatedStorage and places it at CFrame
function SpawnManager:_instantiateNPC(templateName: string, cf: CFrame): Model?
	local RS = game:GetService("ReplicatedStorage")
	local folder = RS:FindFirstChild("Enemies")
	if not folder then
		warn("[SpawnManager] ReplicatedStorage.Enemies folder not found")
		return nil
	end

	local template = folder:FindFirstChild(templateName)
	if not template then
		warn("[SpawnManager] Template not found: " .. templateName)
		return nil
	end

	local clone = template:Clone()
	clone.Parent = workspace

	-- Position root
	local root = clone:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = cf
	else
		clone:SetPrimaryPartCFrame(cf)
	end

	return clone
end

-- Pick a random template from a table
local function pickRandom(t: {string}): string
	return t[math.random(1, #t)]
end

-- ──────────────────────────────────────────────
--  Public API
-- ──────────────────────────────────────────────

--[[
	SetSpawnRateModifier(mod: number)
	Applied to BASE_SPAWN_INTERVAL: higher mod → faster spawns.
]]
function SpawnManager:SetSpawnRateModifier(mod: number)
	self._spawnRateModifier = math.max(0.1, mod)
end

--[[
	GetSpawnRate() -> number
	Effective spawn interval in seconds.
]]
function SpawnManager:GetSpawnRate(): number
	return BASE_SPAWN_INTERVAL / math.max(self._spawnRateModifier, 0.1)
end

--[[
	GetValidSpawnPoint(requiredTags?) -> SpawnPoint | nil
]]
function SpawnManager:GetValidSpawnPoint(requiredTags: {string}?)
	local positions = self:_getPlayerPositions()
	return self._pool:GetBestSpawnPoint(positions, requiredTags)
end

--[[
	SpawnEnemy(pacingMultiplier: number) -> Model | nil
	Spawns a standard enemy if conditions allow.
	pacingMultiplier comes from PacingManager:GetSpawnMultiplier().
]]
function SpawnManager:SpawnEnemy(pacingMultiplier: number): Model?
	self:_cleanupDead()

	if #self._activeEnemies >= MAX_ACTIVE_ENEMIES then return nil end
	if pacingMultiplier <= 0 then return nil end

	local effectiveInterval = self:GetSpawnRate() / pacingMultiplier
	if (tick() - self._lastSpawnTime) < effectiveInterval then return nil end

	local spawnPoint = self:GetValidSpawnPoint()
	if not spawnPoint then
		warn("[SpawnManager] No valid spawn points available")
		return nil
	end

	local templateName = pickRandom({
		ENEMY_TEMPLATES.standard,
		ENEMY_TEMPLATES.standard,  -- weighted 2:1 toward standard
		ENEMY_TEMPLATES.flanker,
		ENEMY_TEMPLATES.heavy,
	})

	local model = self:_instantiateNPC(templateName, spawnPoint:GetCFrame())
	if not model then return nil end

	spawnPoint:MarkUsed()
	self._lastSpawnTime = tick()

	table.insert(self._activeEnemies, {
		model     = model,
		type      = "standard",
		spawnedAt = tick(),
	})

	if self.OnEnemySpawned then
		pcall(self.OnEnemySpawned, model, "standard", spawnPoint:GetPosition())
	end

	return model
end

--[[
	SpawnElite(forceSpawn: boolean?) -> Model | nil
	Spawns an elite/boss unit. Respects its own longer cooldown.
]]
function SpawnManager:SpawnElite(forceSpawn: boolean?): Model?
	self:_cleanupDead()

	if self:_countByType("elite") >= MAX_ACTIVE_ELITES then return nil end

	if not forceSpawn then
		if (tick() - self._lastEliteTime) < ELITE_SPAWN_INTERVAL then return nil end
	end

	local spawnPoint = self:GetValidSpawnPoint({"elite_ok"})
	-- Fallback: any valid point if no elite-tagged ones exist
	if not spawnPoint then
		spawnPoint = self:GetValidSpawnPoint()
	end
	if not spawnPoint then return nil end

	local templateName = pickRandom(ELITE_TEMPLATES)
	local model = self:_instantiateNPC(templateName, spawnPoint:GetCFrame())
	if not model then return nil end

	spawnPoint:MarkUsed()
	self._lastEliteTime = tick()

	table.insert(self._activeEnemies, {
		model     = model,
		type      = "elite",
		spawnedAt = tick(),
	})

	if self.OnEnemySpawned then
		pcall(self.OnEnemySpawned, model, "elite", spawnPoint:GetPosition())
	end

	return model
end

--[[
	SpawnGroup(count: number, requiredTags?) -> {Model}
	Spawns multiple enemies at once (for ambushes/squads).
]]
function SpawnManager:SpawnGroup(count: number, requiredTags: {string}?): {Model}
	local spawned = {}
	local positions = self:_getPlayerPositions()

	for i = 1, count do
		if #self._activeEnemies >= MAX_ACTIVE_ENEMIES then break end

		local point = self._pool:GetBestSpawnPoint(positions, requiredTags)
		if not point then break end

		local model = self:_instantiateNPC(ENEMY_TEMPLATES.standard, point:GetCFrame())
		if model then
			point:MarkUsed()
			table.insert(self._activeEnemies, {
				model     = model,
				type      = "standard",
				spawnedAt = tick(),
			})
			table.insert(spawned, model)

			if self.OnEnemySpawned then
				pcall(self.OnEnemySpawned, model, "group", point:GetPosition())
			end
		end

		-- Small offset between group spawns so they don't all teleport the same point
		task.wait(0.1)
	end

	self._lastSpawnTime = tick()
	return spawned
end

function SpawnManager:GetActiveEnemyCount(): number
	self:_cleanupDead()
	return #self._activeEnemies
end

function SpawnManager:GetActiveEnemies(): table
	self:_cleanupDead()
	return self._activeEnemies
end

function SpawnManager:GetDebugInfo(): table
	self:_cleanupDead()
	return {
		ActiveEnemies   = #self._activeEnemies,
		SpawnRate       = string.format("%.1fs", self:GetSpawnRate()),
		SpawnRateMod    = string.format("%.2f", self._spawnRateModifier),
		NextSpawnIn     = string.format("%.1fs",
			math.max(0, self:GetSpawnRate() - (tick() - self._lastSpawnTime))),
		MaxEnemies      = MAX_ACTIVE_ENEMIES,
	}
end

return SpawnManager
