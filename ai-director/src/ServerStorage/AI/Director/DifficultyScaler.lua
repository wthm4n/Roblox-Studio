-- DifficultyScaler.lua
-- Tracks player performance over time and returns a difficulty modifier
-- that the Director applies to spawn rate, elite chance, and enemy accuracy.

local DifficultyScaler = {}
DifficultyScaler.__index = DifficultyScaler

-- ──────────────────────────────────────────────
--  Config
-- ──────────────────────────────────────────────

-- Rolling window for performance samples (seconds)
local SAMPLE_WINDOW    = 60

-- Skill band boundaries (score 0–100)
-- Below EASY_CAP → scale down. Above HARD_FLOOR → scale up.
local EASY_CAP         = 35
local HARD_FLOOR       = 65

-- Modifier range (multiplier applied to spawn rate, elite chance, accuracy)
local MIN_MODIFIER     = 0.60   -- mercy mode
local MAX_MODIFIER     = 1.50   -- veteran mode
local BASE_MODIFIER    = 1.00

-- Accuracy weight in skill score
local ACCURACY_WEIGHT  = 0.40
-- KPM weight
local KPM_WEIGHT       = 0.35
-- Survival time weight (normalized; longer = better)
local SURVIVAL_WEIGHT  = 0.25
-- Max KPM considered "full score"
local MAX_KPM          = 6.0
-- Max survival seconds considered "full score"
local MAX_SURVIVAL     = 300

-- ──────────────────────────────────────────────
--  Constructor
-- ──────────────────────────────────────────────
function DifficultyScaler.new()
	local self = setmetatable({}, DifficultyScaler)

	-- Running totals (reset by rolling window logic)
	self._shotsFired       = 0
	self._shotsHit         = 0
	self._killTimestamps   = {}    -- array of tick() times
	self._sessionStartTime = tick()
	self._modifier         = BASE_MODIFIER
	self._skillScore       = 50    -- last computed 0–100 score
	self._evaluationCount  = 0

	return self
end

-- ──────────────────────────────────────────────
--  Event Reporters (call from combat hooks)
-- ──────────────────────────────────────────────

function DifficultyScaler:ReportShot(hit: boolean)
	self._shotsFired += 1
	if hit then self._shotsHit += 1 end
end

function DifficultyScaler:ReportKill()
	table.insert(self._killTimestamps, tick())
end

-- ──────────────────────────────────────────────
--  Internal Helpers
-- ──────────────────────────────────────────────

local function normalize(value: number, min: number, max: number): number
	return math.clamp((value - min) / (max - min), 0, 1)
end

-- Prune kill timestamps older than SAMPLE_WINDOW
function DifficultyScaler:_pruneKillLog()
	local cutoff = tick() - SAMPLE_WINDOW
	local i = 1
	while i <= #self._killTimestamps do
		if self._killTimestamps[i] < cutoff then
			table.remove(self._killTimestamps, i)
		else
			i += 1
		end
	end
end

function DifficultyScaler:_computeAccuracy(): number
	if self._shotsFired == 0 then return 0.5 end  -- neutral if no data
	return math.clamp(self._shotsHit / self._shotsFired, 0, 1)
end

function DifficultyScaler:_computeKPM(): number
	self:_pruneKillLog()
	local windowSeconds = math.min(SAMPLE_WINDOW, tick() - self._sessionStartTime)
	if windowSeconds <= 0 then return 0 end
	local kpm = (#self._killTimestamps / windowSeconds) * 60
	return math.clamp(kpm, 0, MAX_KPM)
end

function DifficultyScaler:_computeSurvivalScore(): number
	local elapsed = tick() - self._sessionStartTime
	return normalize(elapsed, 0, MAX_SURVIVAL)
end

-- ──────────────────────────────────────────────
--  Public API
-- ──────────────────────────────────────────────

--[[
	EvaluatePlayerSkill() -> number
	Computes a 0–100 skill score from accuracy, KPM, and survival time.
	Updates the internal modifier. Call periodically (e.g. every 10s).
]]
function DifficultyScaler:EvaluatePlayerSkill(): number
	self._evaluationCount += 1

	local accuracy      = self:_computeAccuracy()
	local kpmScore      = normalize(self:_computeKPM(), 0, MAX_KPM)
	local survivalScore = self:_computeSurvivalScore()

	local rawScore = (accuracy   * ACCURACY_WEIGHT)
	              + (kpmScore    * KPM_WEIGHT)
	              + (survivalScore * SURVIVAL_WEIGHT)

	self._skillScore = math.clamp(rawScore * 100, 0, 100)

	-- Map skill score → modifier
	if self._skillScore <= EASY_CAP then
		-- Scale down linearly from BASE to MIN
		local t = 1 - (self._skillScore / EASY_CAP)
		self._modifier = BASE_MODIFIER - t * (BASE_MODIFIER - MIN_MODIFIER)
	elseif self._skillScore >= HARD_FLOOR then
		-- Scale up linearly from BASE to MAX
		local t = (self._skillScore - HARD_FLOOR) / (100 - HARD_FLOOR)
		self._modifier = BASE_MODIFIER + t * (MAX_MODIFIER - BASE_MODIFIER)
	else
		self._modifier = BASE_MODIFIER
	end

	return self._skillScore
end

--[[
	GetDifficultyModifier() -> number
	Returns the current difficulty multiplier (0.60 – 1.50).
	Apply to: spawn rate, elite spawn chance, enemy accuracy.
]]
function DifficultyScaler:GetDifficultyModifier(): number
	return self._modifier
end

-- Convenience getters for specific stat overrides

function DifficultyScaler:GetSpawnRateModifier(): number
	return self._modifier
end

function DifficultyScaler:GetEliteSpawnChance(base: number): number
	-- base is 0–1; amplified or reduced by difficulty
	return math.clamp(base * self._modifier, 0, 1)
end

function DifficultyScaler:GetEnemyAccuracyModifier(): number
	-- Accuracy bonus/malus on top of base enemy accuracy
	return self._modifier
end

function DifficultyScaler:GetDebugInfo(): table
	return {
		SkillScore        = math.floor(self._skillScore),
		DifficultyMod     = string.format("%.2f", self._modifier),
		Accuracy          = string.format("%.0f%%", self:_computeAccuracy() * 100),
		KPM               = string.format("%.1f", self:_computeKPM()),
		SurvivalTime      = string.format("%.0fs", tick() - self._sessionStartTime),
		EvaluationCount   = self._evaluationCount,
	}
end

return DifficultyScaler
