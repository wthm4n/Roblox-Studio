-- StressCalculator.lua
-- Calculates player stress (0-100) based on combat state inputs

local StressCalculator = {}
StressCalculator.__index = StressCalculator

-- Weights for each stress factor (must sum to 1.0)
local STRESS_WEIGHTS = {
	health        = 0.30,
	enemiesNearby = 0.25,
	damageTaken   = 0.20,
	ammo          = 0.10,
	timeSinceCombat = 0.15,
}

-- Thresholds
local LOW_HEALTH_THRESHOLD      = 40   -- below this = high stress
local CRITICAL_HEALTH_THRESHOLD = 20
local AMMO_LOW_THRESHOLD        = 0.25 -- fraction of max ammo
local COMBAT_IDLE_MAX           = 30   -- seconds; longer = lower stress
local MAX_ENEMIES_NEARBY        = 8

export type PlayerData = {
	health: number,          -- current HP (0–100)
	maxHealth: number,       -- max HP
	enemiesNearby: number,   -- count of enemies within detection radius
	damageTaken: number,     -- damage taken in last tick (0–maxHealth)
	ammo: number,            -- current ammo count
	maxAmmo: number,         -- max ammo capacity
	timeSinceCombat: number, -- seconds since last damage event
}

function StressCalculator.new()
	local self = setmetatable({}, StressCalculator)
	self._smoothedStress = 0
	self._smoothing = 0.15 -- lerp factor per tick
	return self
end

-- Map a value in [inMin, inMax] to [0, 1], clamped
local function normalize(value: number, inMin: number, inMax: number): number
	return math.clamp((value - inMin) / (inMax - inMin), 0, 1)
end

-- Individual factor calculators (each returns 0–1 stress contribution)

local function healthStress(data: PlayerData): number
	local fraction = data.health / math.max(data.maxHealth, 1)
	-- inverse: low health → high stress
	if fraction <= (CRITICAL_HEALTH_THRESHOLD / 100) then
		return 1.0
	elseif fraction <= (LOW_HEALTH_THRESHOLD / 100) then
		return normalize(fraction, CRITICAL_HEALTH_THRESHOLD / 100, LOW_HEALTH_THRESHOLD / 100)
		       * 0.5 + 0.5 -- range [0.5, 1.0]
	else
		return (1 - fraction) * 0.5 -- range [0, 0.5]
	end
end

local function enemyProximityStress(data: PlayerData): number
	return normalize(data.enemiesNearby, 0, MAX_ENEMIES_NEARBY)
end

local function damageTakenStress(data: PlayerData): number
	return normalize(data.damageTaken, 0, data.maxHealth * 0.5)
end

-- Rewrite ammoStress cleanly
local function ammoStressClean(data: PlayerData): number
	local fraction = data.ammo / math.max(data.maxAmmo, 1)
	if fraction > AMMO_LOW_THRESHOLD then return 0 end
	return 1 - (fraction / AMMO_LOW_THRESHOLD)
end

local function combatIdleStress(data: PlayerData): number
	-- More time since combat = LESS stress (recovery)
	local idleFraction = math.min(data.timeSinceCombat / COMBAT_IDLE_MAX, 1)
	return 1 - idleFraction
end

--[[
	CalculateStress(playerData: PlayerData) -> number
	Returns a weighted stress value in range [0, 100].
	Applies exponential smoothing between ticks.
]]
function StressCalculator:CalculateStress(playerData: PlayerData): number
	assert(playerData, "[StressCalculator] playerData is nil")

	local raw =
		healthStress(playerData)        * STRESS_WEIGHTS.health
		+ enemyProximityStress(playerData)  * STRESS_WEIGHTS.enemiesNearby
		+ damageTakenStress(playerData)     * STRESS_WEIGHTS.damageTaken
		+ ammoStressClean(playerData)       * STRESS_WEIGHTS.ammo
		+ combatIdleStress(playerData)      * STRESS_WEIGHTS.timeSinceCombat

	-- Smooth to avoid jarring spikes
	self._smoothedStress = self._smoothedStress
		+ (raw - self._smoothedStress) * self._smoothing

	return math.clamp(self._smoothedStress * 100, 0, 100)
end

-- Returns the last smoothed stress without recalculating
function StressCalculator:GetCurrentStress(): number
	return math.clamp(self._smoothedStress * 100, 0, 100)
end

-- Force-reset smoothing (e.g. after scene change)
function StressCalculator:Reset()
	self._smoothedStress = 0
end

return StressCalculator
