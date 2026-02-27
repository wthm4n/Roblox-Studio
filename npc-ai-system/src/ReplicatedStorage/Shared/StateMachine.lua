--[[
	StateMachine.lua
	A clean, extensible Finite State Machine.

	Fix: Same-state check now happens BEFORE the lock check.
	This prevents the flood of "Transition called while locked. Queuing: Idle"
	warnings that occur when OnUpdate calls Transition every frame to the
	already-current state.
--]]

local StateMachine = {}
StateMachine.__index = StateMachine

export type State = {
	Name: string,
	OnEnter: ((self: any) -> ())?,
	OnExit: ((self: any) -> ())?,
	OnUpdate: ((self: any, dt: number) -> ())?,
}

export type StateMachineType = typeof(setmetatable({} :: {
	Entity: any,
	States: { [string]: State },
	CurrentState: State?,
	PreviousStateName: string?,
}, StateMachine))

function StateMachine.new(entity: any, states: { [string]: State }, initialState: string): StateMachineType
	local self = setmetatable({}, StateMachine)
	self.Entity = entity
	self.States = states
	self.CurrentState = nil
	self.PreviousStateName = nil
	self._locked = false
	self._queued = nil

	assert(states[initialState], "[StateMachine] Initial state '" .. initialState .. "' not found.")
	self:Transition(initialState)

	return self
end

function StateMachine:Transition(stateName: string)
	-- ── 1. Validate state exists ──────────────────────────────────────────
	local newState = self.States[stateName]
	if not newState then
		warn("[StateMachine] State not found: " .. stateName)
		return
	end

	-- ── 2. Drop no-op transitions (same state) BEFORE checking lock ───────
	--    This is the critical fix: previously this check was AFTER the lock
	--    check, so every Heartbeat call to Transition("Idle") while already
	--    in Idle would hit the lock path and spam the queue with 2000+ entries.
	if self.CurrentState and self.CurrentState.Name == stateName then
		return
	end

	-- ── 3. Queue if locked (silently — no warn, queuing is correct behavior) ─
	if self._locked then
		if self._queued ~= stateName then
			self._queued = stateName
		end
		return
	end

	self._locked = true

	-- Exit current state
	if self.CurrentState then
		self.PreviousStateName = self.CurrentState.Name
		if self.CurrentState.OnExit then
			self.CurrentState.OnExit(self.Entity)
		end
	end

	-- Enter new state
	self.CurrentState = newState
	if newState.OnEnter then
		newState.OnEnter(self.Entity)
	end

	self._locked = false

	-- Handle queued transition (only if it's still different from current)
	if self._queued then
		local queued = self._queued
		self._queued = nil
		-- Guard: don't re-enter if the queued state matches where we landed
		if self.CurrentState and self.CurrentState.Name ~= queued then
			self:Transition(queued)
		end
	end
end

function StateMachine:Update(dt: number)
	if self.CurrentState and self.CurrentState.OnUpdate then
		self.CurrentState.OnUpdate(self.Entity, dt)
	end
end

function StateMachine:GetState(): string
	return self.CurrentState and self.CurrentState.Name or "None"
end

return StateMachine