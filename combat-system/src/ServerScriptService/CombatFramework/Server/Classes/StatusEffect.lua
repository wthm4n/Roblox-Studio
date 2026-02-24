--[[
	StatusEffect.lua
	Represents a single timed status (Stun, Burn, Slow, GuardBreak, etc.)
	Runs its own thread — cancellable at any time.
]]

local StatusEffect = {}
StatusEffect.__index = StatusEffect

-- ─── Constructor ──────────────────────────────────────────────────────────────

function StatusEffect.new(name: string, duration: number, onApply: () -> (), onRemove: () -> ())
	local self = setmetatable({}, StatusEffect)

	self.Name     = name
	self.Duration = duration
	self._active  = false
	self._thread  = nil

	self._onApply  = onApply  or function() end
	self._onRemove = onRemove or function() end

	return self
end

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function StatusEffect:Start()
	if self._active then
		self:Cancel() -- refresh
	end

	self._active = true
	self._onApply()

	self._thread = task.delay(self.Duration, function()
		self:_Expire()
	end)
end

function StatusEffect:Cancel()
	if self._thread then
		task.cancel(self._thread)
		self._thread = nil
	end
	self:_Expire()
end

function StatusEffect:_Expire()
	if not self._active then return end
	self._active = false
	self._onRemove()
end

function StatusEffect:IsActive(): boolean
	return self._active
end

return StatusEffect