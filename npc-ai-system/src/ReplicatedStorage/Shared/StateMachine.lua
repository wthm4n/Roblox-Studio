--[[
	StateMachine.lua
	Fixes:
	  1. Same-state check is FIRST — redundant transitions are dropped before
	     the lock is ever checked, eliminating queue spam entirely.
	  2. Lock path is silent — queuing is correct behavior, not an error.
	  3. Queue deduplication — won't overwrite with same state name.
	  4. Post-unlock queue guard — won't process queued state if it matches
	     where we already landed.
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
	-- 1. Validate
	local newState = self.States[stateName]
	if not newState then
		warn("[StateMachine] State not found: " .. stateName)
		return
	end

	-- 2. Drop same-state transitions BEFORE lock check
	--    This is critical — without this, every Heartbeat call to
	--    Transition("Idle") while already in Idle hits the lock path
	if self.CurrentState and self.CurrentState.Name == stateName then
		return
	end

	-- 3. Queue silently if locked (no warn — queuing is correct behavior)
	if self._locked then
		if self._queued ~= stateName then
			self._queued = stateName
		end
		return
	end

	self._locked = true

	if self.CurrentState then
		self.PreviousStateName = self.CurrentState.Name
		if self.CurrentState.OnExit then
			self.CurrentState.OnExit(self.Entity)
		end
	end

	self.CurrentState = newState
	if newState.OnEnter then
		newState.OnEnter(self.Entity)
	end

	self._locked = false

	if self._queued then
		local queued = self._queued
		self._queued = nil
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