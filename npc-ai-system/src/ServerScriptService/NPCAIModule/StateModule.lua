--[[
	StateModule.lua
	Lightweight state machine with transition validation
--]]

local VALID_STATES = {
	passive    = true,
	aggressive = true,
	scared     = true,
	patrol     = true,
}

local StateModule = {}
StateModule.__index = StateModule

function StateModule.new(initial: string)
	assert(VALID_STATES[initial], "[StateModule] Invalid initial state: " .. tostring(initial))
	local self = setmetatable({}, StateModule)
	self._state    = initial
	self._previous = nil
	self._onChange = {}   -- { [fn] = true }
	return self
end

function StateModule:Get(): string
	return self._state
end

function StateModule:Set(newState: string)
	assert(VALID_STATES[newState], "[StateModule] Invalid state: " .. tostring(newState))
	if newState == self._state then return end
	self._previous = self._state
	self._state    = newState
	-- Fire listeners
	for fn in pairs(self._onChange) do
		fn(newState, self._previous)
	end
end

function StateModule:Previous(): string?
	return self._previous
end

-- Register a callback: fn(newState, prevState)
function StateModule:OnChange(fn: (string, string?) -> ())
	self._onChange[fn] = true
	return function()  -- returns disconnect handle
		self._onChange[fn] = nil
	end
end

return StateModule
