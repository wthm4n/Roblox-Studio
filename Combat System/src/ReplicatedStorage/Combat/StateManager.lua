--[[
	STATE MANAGER
	
	Enforces the state machine.
	Every character is in EXACTLY ONE state at all times.
	States define what's allowed. No exceptions.
]]

local StateManager = {}
StateManager.__index = StateManager

--[[
	STATE DEFINITIONS
	Each state defines:
	- AllowedInputs: What inputs can be processed
	- AllowedTransitions: What states can be entered from here
	- Priority: Used for conflict resolution
	- OnEnter/OnExit: Optional hooks
]]
local STATE_DEFINITIONS = {
	Neutral = {
		Priority = 0,
		AllowedInputs = {
			M1 = true,
			Dash = true,
			Ability = true,
			Block = true,
			Jump = true,
		},
		AllowedTransitions = {
			Attacking = true,
			Dashing = true,
			Blocking = true,
			Airborne = true,
			Hitstun = true,
		},
	},
	
	Attacking = {
		Priority = 2,
		AllowedInputs = {
			M1 = true, -- For combos
			Dash = true, -- Cancel into dash if allowed
		},
		AllowedTransitions = {
			Neutral = true,
			Recovery = true,
			Hitstun = true,
			Dashing = true,
		},
	},
	
	Recovery = {
		Priority = 1,
		AllowedInputs = {
			-- Very limited during recovery
			Dash = true, -- Only if cancel window open
			M1 = true, -- Only if cancel window open
		},
		AllowedTransitions = {
			Neutral = true,
			Hitstun = true,
			Attacking = true,
			Dashing = true,
		},
	},
	
	Dashing = {
		Priority = 3,
		AllowedInputs = {
			M1 = true, -- Attack out of dash
			Ability = true, -- Ability out of dash
		},
		AllowedTransitions = {
			Neutral = true,
			Attacking = true,
			Hitstun = true,
		},
	},
	
	Hitstun = {
		Priority = 10, -- Highest priority - cannot be interrupted
		AllowedInputs = {
			-- Nothing allowed during hitstun
		},
		AllowedTransitions = {
			Neutral = true,
			Knockback = true,
			Ragdoll = true,
		},
	},
	
	Knockback = {
		Priority = 11,
		AllowedInputs = {},
		AllowedTransitions = {
			Neutral = true,
			Ragdoll = true,
			Airborne = true,
		},
	},
	
	Ragdoll = {
		Priority = 12,
		AllowedInputs = {},
		AllowedTransitions = {
			Neutral = true,
			Recovery = true,
		},
	},
	
	Airborne = {
		Priority = 1,
		AllowedInputs = {
			M1 = true,
			Ability = true,
			Dash = true, -- Air dash if configured
		},
		AllowedTransitions = {
			Neutral = true, -- On landing
			Attacking = true,
			Hitstun = true,
		},
	},
	
	Blocking = {
		Priority = 2,
		AllowedInputs = {
			Block = true, -- Can release
		},
		AllowedTransitions = {
			Neutral = true,
			Hitstun = true, -- Block broken
		},
	},
	
	Invincible = {
		Priority = 15, -- Max priority
		AllowedInputs = {},
		AllowedTransitions = {
			-- Will transition based on iframe duration
			Neutral = true,
			Attacking = true,
			Dashing = true,
		},
	},
}

function StateManager.new(core)
	local self = setmetatable({}, StateManager)
	
	self.Core = core
	self.CurrentState = "Neutral"
	self.StateStartFrame = 0
	self.StateHistory = {} -- Track last N states for debugging
	self.MaxHistoryLength = 20
	
	-- I-frame tracking
	self.InvincibilityEndFrame = 0
	
	return self
end

function StateManager:Update(currentFrame: number)
	-- Update invincibility
	if self.InvincibilityEndFrame > 0 and currentFrame >= self.InvincibilityEndFrame then
		self.InvincibilityEndFrame = 0
		-- Could trigger state change here if in Invincible state
	end
	
	-- State-specific updates could go here
	-- For now, states are mostly reactive
end

function StateManager:OnStateChanged(oldState: string, newState: string)
	-- Validate transition
	if not self:IsValidTransition(oldState, newState) then
		warn(string.format(
			"INVALID STATE TRANSITION: %s -> %s (Frame: %d)",
			oldState,
			newState,
			self.Core.CurrentFrame
		))
		-- In production, you might want to force back to a safe state
		return
	end
	
	-- Record in history
	table.insert(self.StateHistory, {
		State = newState,
		Frame = self.Core.CurrentFrame,
	})
	
	-- Trim history if too long
	if #self.StateHistory > self.MaxHistoryLength then
		table.remove(self.StateHistory, 1)
	end
	
	-- Update current state
	self.CurrentState = newState
	self.StateStartFrame = self.Core.CurrentFrame
	
	-- Call hooks if they exist
	local stateDef = STATE_DEFINITIONS[newState]
	if stateDef and stateDef.OnEnter then
		stateDef.OnEnter(self.Core)
	end
	
	local oldStateDef = STATE_DEFINITIONS[oldState]
	if oldStateDef and oldStateDef.OnExit then
		oldStateDef.OnExit(self.Core)
	end
end

function StateManager:IsValidTransition(fromState: string, toState: string): boolean
	local stateDef = STATE_DEFINITIONS[fromState]
	if not stateDef then
		warn("Unknown state:", fromState)
		return false
	end
	
	-- Check if transition is allowed
	if not stateDef.AllowedTransitions[toState] then
		return false
	end
	
	-- Check priority override (higher priority states can always interrupt)
	local fromPriority = stateDef.Priority or 0
	local toPriority = STATE_DEFINITIONS[toState].Priority or 0
	
	if toPriority > fromPriority then
		return true -- Higher priority always wins
	end
	
	return true
end

function StateManager:GetCurrentStateRules()
	return STATE_DEFINITIONS[self.CurrentState] or STATE_DEFINITIONS.Neutral
end

function StateManager:GetStatePriority(stateName: string): number
	local stateDef = STATE_DEFINITIONS[stateName]
	return stateDef and stateDef.Priority or 0
end

--[[
	INVINCIBILITY FRAMES
	Sets temporary invincibility (i-frames)
]]
function StateManager:SetInvincibility(durationFrames: number)
	self.InvincibilityEndFrame = self.Core.CurrentFrame + durationFrames
end

function StateManager:IsInvincible(): boolean
	return self.Core.CurrentFrame < self.InvincibilityEndFrame
end

--[[
	FORCED STATE TRANSITIONS
	Used by server for hitstun, knockback, etc.
]]
function StateManager:ForceState(newState: string, durationFrames: number?)
	-- This bypasses normal transition rules
	-- Only used for authoritative server events
	
	if not self.Core.IsServer then
		warn("ForceState called on client - only server can force states")
		return
	end
	
	self.CurrentState = newState
	self.StateStartFrame = self.Core.CurrentFrame
	
	if durationFrames then
		-- Auto-transition back to Neutral after duration
		task.delay(durationFrames / 60, function()
			if self.CurrentState == newState then
				self.Core:ChangeState("Neutral")
			end
		end)
	end
end

function StateManager:GetCurrentState(): string
	return self.CurrentState
end

function StateManager:GetFramesInState(): number
	return self.Core.CurrentFrame - self.StateStartFrame
end

function StateManager:Destroy()
	-- Cleanup
end

return StateManager
