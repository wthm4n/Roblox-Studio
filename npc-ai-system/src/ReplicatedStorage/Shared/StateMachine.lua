--[[
	StateMachine.lua
	A clean, extensible Finite State Machine.
	
	Usage:
		local fsm = StateMachine.new(entity, states, "Idle")
		fsm:Update(dt)
		fsm:Transition("Chase")
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

	assert(states[initialState], "[StateMachine] Initial state '" .. initialState .. "' not found.")
	self:Transition(initialState)

	return self
end

function StateMachine:Transition(stateName: string)
	if self._locked then
		warn("[StateMachine] Transition called while locked. Queuing: " .. stateName)
		self._queued = stateName
		return
	end

	local newState = self.States[stateName]
	if not newState then
		warn("[StateMachine] State not found: " .. stateName)
		return
	end

	if self.CurrentState and self.CurrentState.Name == stateName then
		return -- Already in this state
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

	-- Handle queued transition
	if self._queued then
		local queued = self._queued
		self._queued = nil
		self:Transition(queued)
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
