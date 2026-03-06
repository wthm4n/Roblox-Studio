-- PacingManager.lua
-- Controls game pacing states and transitions based on director stress.
-- States: RELAX → BUILDUP → PEAK → RECOVERY

local PacingManager = {}
PacingManager.__index = PacingManager

-- ──────────────────────────────────────────────
--  Pacing State Enum
-- ──────────────────────────────────────────────
PacingManager.State = {
	RELAX    = "RELAX",
	BUILDUP  = "BUILDUP",
	PEAK     = "PEAK",
	RECOVERY = "RECOVERY",
}

-- ──────────────────────────────────────────────
--  Transition Thresholds (stress 0–100)
-- ──────────────────────────────────────────────
local THRESHOLDS = {
	-- Stress must EXCEED this to move UP
	RELAX_TO_BUILDUP   = 30,
	BUILDUP_TO_PEAK    = 65,
	-- Stress must FALL BELOW this to move DOWN
	PEAK_TO_RECOVERY   = 45,
	RECOVERY_TO_RELAX  = 20,
}

-- Minimum time (seconds) a state must be held before transitioning
local MIN_STATE_DURATION = {
	RELAX    = 8,
	BUILDUP  = 5,
	PEAK     = 6,
	RECOVERY = 10,
}

-- Spawn multipliers per state (applied on top of base spawn rate)
local SPAWN_MULTIPLIERS = {
	RELAX    = 0.0,   -- no spawning during relax
	BUILDUP  = 0.6,
	PEAK     = 1.0,
	RECOVERY = 0.2,
}

-- Probability (0–1) of a special event being triggered per evaluation
local EVENT_PROBABILITY = {
	RELAX    = 0.00,
	BUILDUP  = 0.10,
	PEAK     = 0.30,
	RECOVERY = 0.05,
}

-- ──────────────────────────────────────────────
--  Constructor
-- ──────────────────────────────────────────────
function PacingManager.new()
	local self = setmetatable({}, PacingManager)

	self.CurrentState     = PacingManager.State.RELAX
	self._stateTimer      = 0    -- seconds spent in current state
	self._previousState   = nil
	self._transitionCount = 0    -- total transitions (for debug)
	self._listeners       = {}   -- state-change callbacks

	return self
end

-- ──────────────────────────────────────────────
--  Internal Helpers
-- ──────────────────────────────────────────────
local function getMinDuration(state: string): number
	return MIN_STATE_DURATION[state] or 5
end

function PacingManager:_transitionTo(newState: string)
	if newState == self.CurrentState then return end

	self._previousState   = self.CurrentState
	self.CurrentState     = newState
	self._stateTimer      = 0
	self._transitionCount += 1

	-- Fire listeners
	for _, cb in ipairs(self._listeners) do
		pcall(cb, newState, self._previousState)
	end

	warn(string.format(
		"[PacingManager] %s → %s (transition #%d)",
		self._previousState, newState, self._transitionCount
	))
end

-- ──────────────────────────────────────────────
--  Public API
-- ──────────────────────────────────────────────

--[[
	UpdateState(stress: number, dt: number)
	Call each Director tick. stress is 0–100.
	dt is delta-time in seconds.
]]
function PacingManager:UpdateState(stress: number, dt: number)
	assert(type(stress) == "number", "[PacingManager] stress must be a number")
	self._stateTimer += dt

	local state = self.CurrentState
	local minHeld = getMinDuration(state)

	-- Guard: don't transition until minimum duration met
	if self._stateTimer < minHeld then return end

	-- State machine transitions
	if state == PacingManager.State.RELAX then
		if stress > THRESHOLDS.RELAX_TO_BUILDUP then
			self:_transitionTo(PacingManager.State.BUILDUP)
		end

	elseif state == PacingManager.State.BUILDUP then
		if stress > THRESHOLDS.BUILDUP_TO_PEAK then
			self:_transitionTo(PacingManager.State.PEAK)
		elseif stress < THRESHOLDS.RELAX_TO_BUILDUP then
			-- stress dropped back down
			self:_transitionTo(PacingManager.State.RELAX)
		end

	elseif state == PacingManager.State.PEAK then
		if stress < THRESHOLDS.PEAK_TO_RECOVERY then
			self:_transitionTo(PacingManager.State.RECOVERY)
		end

	elseif state == PacingManager.State.RECOVERY then
		if stress < THRESHOLDS.RECOVERY_TO_RELAX then
			self:_transitionTo(PacingManager.State.RELAX)
		elseif stress > THRESHOLDS.BUILDUP_TO_PEAK then
			-- Stress spiked again mid-recovery → jump to peak
			self:_transitionTo(PacingManager.State.PEAK)
		end
	end
end

--[[
	GetSpawnMultiplier() -> number
	Returns a 0–1 multiplier to scale spawn rate.
]]
function PacingManager:GetSpawnMultiplier(): number
	return SPAWN_MULTIPLIERS[self.CurrentState] or 0
end

--[[
	GetEventProbability() -> number
	Returns probability (0–1) that an event should be triggered this tick.
]]
function PacingManager:GetEventProbability(): number
	return EVENT_PROBABILITY[self.CurrentState] or 0
end

--[[
	GetStateDuration() -> number
	Seconds spent in the current state.
]]
function PacingManager:GetStateDuration(): number
	return self._stateTimer
end

--[[
	OnStateChanged(callback: (newState, prevState) -> ())
	Register a listener for state transitions.
]]
function PacingManager:OnStateChanged(callback)
	table.insert(self._listeners, callback)
end

-- Returns a summary table for debug/UI
function PacingManager:GetDebugInfo(): table
	return {
		CurrentState      = self.CurrentState,
		StateDuration     = math.floor(self._stateTimer * 10) / 10,
		SpawnMultiplier   = self:GetSpawnMultiplier(),
		EventProbability  = self:GetEventProbability(),
		TransitionCount   = self._transitionCount,
		PreviousState     = self._previousState or "none",
	}
end

return PacingManager
