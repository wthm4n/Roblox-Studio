--[[
	COMBAT CORE - THE BRAIN
	
	This is the single authoritative decision-maker for all combat.
	Nothing bypasses this. Everything flows through here.
	
	Responsibilities:
	- State management (THE state machine)
	- Action validation and approval
	- Frame timing
	- Input buffering and priority resolution
	- Network authority
	- Event emission to subsystems
]]

local CombatCore = {}
CombatCore.__index = CombatCore

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Import subsystems (these are listeners, not decision-makers)
local StateManager = require(script.Parent.StateManager)
local InputBuffer = require(script.Parent.InputBuffer)
local FrameTimer = require(script.Parent.FrameTimer)
local NetworkSync = require(script.Parent.NetworkSync)

-- Constants
local BUFFER_WINDOW_FRAMES = 6 -- Input buffer window
local MAX_COMBO_GAP_FRAMES = 10 -- Max frames between combo inputs

--[[
	Creates a new CombatCore instance for a character
	@param character - Roblox R6 character model
	@param isServer - boolean, true if running on server
]]
function CombatCore.new(character: Model, isServer: boolean)
	local self = setmetatable({}, CombatCore)
	
	-- Core references
	self.Character = character
	self.Humanoid = character:WaitForChild("Humanoid")
	self.HumanoidRootPart = character:WaitForChild("HumanoidRootPart")
	self.IsServer = isServer
	
	-- State machine
	self.StateManager = StateManager.new(self)
	self.CurrentState = "Neutral" -- Always in exactly ONE state
	self.StateStartFrame = 0
	
	-- Frame timing
	self.FrameTimer = FrameTimer.new()
	self.CurrentFrame = 0
	self.ActionStartFrame = 0
	self.ActionTotalFrames = 0
	
	-- Input system
	self.InputBuffer = InputBuffer.new(BUFFER_WINDOW_FRAMES)
	self.LastConsumedInput = nil
	
	-- Current action tracking
	self.CurrentAction = nil -- { Type, Data, StartFrame, EndFrame }
	self.ActiveHitboxes = {} -- Currently active hitbox windows
	self.HitTargets = {} -- Targets hit this action (prevents multi-hit)
	
	-- Combo system
	self.ComboCounter = 0
	self.ComboChain = {} -- Track combo progression
	self.LastComboFrame = 0
	self.ComboResetFrame = 0 -- When combo can be started again after finishing
	self.InAttackWindow = false -- Whether we're in a valid attack continuation window
	self.AttackWindowEndFrame = 0 -- When current attack window expires
	
	-- Network sync
	if isServer then
		self.NetworkSync = NetworkSync.newServer(self)
	else
		self.NetworkSync = NetworkSync.newClient(self)
	end
	
	-- Cooldowns
	self.Cooldowns = {} -- { AbilityName = frameWhenReady }
	
	-- Animation tracking
	self.AnimationMarkers = {} -- Signals from animations
	self.CurrentTrack = nil
	
	-- Events (for subsystems to listen to)
	self.Events = {
		StateChanged = Instance.new("BindableEvent"),
		ActionStarted = Instance.new("BindableEvent"),
		ActionEnded = Instance.new("BindableEvent"),
		HitConfirmed = Instance.new("BindableEvent"),
		DamageTaken = Instance.new("BindableEvent"),
		CancelOpened = Instance.new("BindableEvent"),
		CancelClosed = Instance.new("BindableEvent"),
	}
	
	-- Start the frame loop
	self:StartFrameLoop()
	
	return self
end

--[[
	FRAME LOOP - The heartbeat of combat
	This runs every frame and drives all timing
]]
function CombatCore:StartFrameLoop()
	self.FrameConnection = RunService.Heartbeat:Connect(function(deltaTime)
		self:ProcessFrame(deltaTime)
	end)
end

function CombatCore:ProcessFrame(deltaTime: number)
	-- Increment frame counter
	self.CurrentFrame = self.FrameTimer:Tick(deltaTime)
	
	-- Update state machine
	self.StateManager:Update(self.CurrentFrame)
	
	-- Update attack window
	self:UpdateAttackWindow()
	
	-- Process buffered inputs
	self:ProcessInputBuffer()
	
	-- Update current action if active
	if self.CurrentAction then
		self:UpdateAction()
	end
	
	-- Update cooldowns
	self:UpdateCooldowns()
	
	-- Network sync (client prediction / server correction)
	if self.IsServer then
		self.NetworkSync:ServerUpdate()
	else
		self.NetworkSync:ClientUpdate()
	end
end

--[[
	INPUT HANDLING - The entry point for all player actions
	Nothing bypasses this. All inputs go through the buffer.
]]
function CombatCore:QueueInput(inputType: string, inputData: any)
	-- Add to buffer with current frame timestamp
	self.InputBuffer:Add(inputType, inputData, self.CurrentFrame)
end

function CombatCore:ProcessInputBuffer()
	-- Get highest priority input from buffer
	local input = self.InputBuffer:GetNextValid(self.CurrentFrame)
	
	if not input then return end
	
	-- Attempt to consume the input
	local success = self:TryConsumeInput(input)
	
	if success then
		self.InputBuffer:Consume(input)
		self.LastConsumedInput = input
	end
	-- If failed, input stays in buffer until it expires
end

--[[
	TryConsumeInput - THE DECISION MAKER
	This is where all validation happens.
	The Core decides if an action is allowed.
]]
function CombatCore:TryConsumeInput(input): boolean
	local inputType = input.Type
	local inputData = input.Data
	
	-- Get current state rules
	local stateRules = self.StateManager:GetCurrentStateRules()
	
	-- Check if this input type is allowed in current state
	if not stateRules.AllowedInputs[inputType] then
		return false -- State forbids this action
	end
	
	-- Check cancel permissions
	if self.CurrentAction then
		local canCancel = self:CanCancelCurrentAction(inputType)
		if not canCancel then
			return false -- Current action cannot be canceled
		end
	end
	
	-- Check cooldowns
	if inputType == "Ability" then
		if self:IsOnCooldown(inputData.AbilityName) then
			return false -- Ability on cooldown
		end
	end
	
	-- Check combo validity for M1
	if inputType == "M1" then
		-- Check if we can start a new combo
		if self.ComboCounter == 0 and not self:CanStartNewCombo() then
			return false -- Still on combo cooldown
		end
		
		if not self:IsValidComboInput() then
			return false -- Combo chain broken or wrong timing
		end
	end
	
	-- All checks passed - approve the action
	self:ExecuteAction(inputType, inputData)
	return true
end

--[[
	ExecuteAction - Starts an approved action
	This is the ONLY way actions begin.
]]
function CombatCore:ExecuteAction(actionType: string, actionData: any)
	-- Load action config
	local actionConfig = self:GetActionConfig(actionType, actionData)
	if not actionConfig then
		warn("No config found for action:", actionType)
		return
	end
	
	-- Cancel current action if one exists
	if self.CurrentAction then
		self:EndCurrentAction(true) -- Canceled = true
	end
	
	-- Set up new action
	self.CurrentAction = {
		Type = actionType,
		Data = actionData,
		Config = actionConfig,
		StartFrame = self.CurrentFrame,
		EndFrame = self.CurrentFrame + actionConfig.TotalFrames,
		Phase = "Startup", -- Startup -> Active -> Recovery
		PhaseFrame = 0,
	}
	
	self.ActionStartFrame = self.CurrentFrame
	self.ActionTotalFrames = actionConfig.TotalFrames
	self.HitTargets = {} -- Reset hit tracking
	
	-- Transition state
	self:ChangeState(actionConfig.RequiredState or "Attacking")
	
	-- Update combo tracking
	if actionType == "M1" then
		self:AdvanceCombo()
	end
	
	-- Set cooldown if applicable
	if actionType == "Ability" then
		self:SetCooldown(actionData.AbilityName, actionConfig.Cooldown)
	end
	
	-- Emit event for subsystems
	self.Events.ActionStarted:Fire({
		Type = actionType,
		Data = actionData,
		Config = actionConfig,
	})
end

--[[
	UpdateAction - Called every frame to progress the current action
]]
function CombatCore:UpdateAction()
	local action = self.CurrentAction
	local config = action.Config
	local framesSinceStart = self.CurrentFrame - action.StartFrame
	
	-- Determine current phase
	local oldPhase = action.Phase
	
	if framesSinceStart < config.StartupFrames then
		action.Phase = "Startup"
	elseif framesSinceStart < config.StartupFrames + config.ActiveFrames then
		action.Phase = "Active"
	else
		action.Phase = "Recovery"
	end
	
	-- Phase transition events
	if oldPhase ~= action.Phase then
		if action.Phase == "Active" then
			self:OnActivePhaseStart()
		elseif action.Phase == "Recovery" then
			self:OnRecoveryPhaseStart()
		end
	end
	
	-- Update phase frame counter
	action.PhaseFrame = framesSinceStart
	
	-- Check for action end
	if self.CurrentFrame >= action.EndFrame then
		self:EndCurrentAction(false) -- Not canceled
	end
end

function CombatCore:OnActivePhaseStart()
	-- Active frames started - hitboxes become active
	-- Attack window will open during recovery, not here
end

function CombatCore:OnRecoveryPhaseStart()
	-- Recovery started
	-- Open attack window for combo continuation (if not 4th hit)
	if self.CurrentAction.Type == "M1" and self.ComboCounter < 4 then
		local config = self.CurrentAction.Config
		local windowDuration = config.AttackWindowDuration or 12 -- Default 12 frames (0.2s)
		
		-- Delay window opening slightly into recovery for better feel
		local windowDelay = config.AttackWindowDelay or 3 -- Start window 3 frames into recovery
		
		task.delay(windowDelay / 60, function()
			if self.CurrentAction then -- Still in same action
				self:OpenAttackWindow(windowDuration)
			end
		end)
	end
end

function CombatCore:EndCurrentAction(wasCanceled: boolean)
	if not self.CurrentAction then return end
	
	local action = self.CurrentAction
	local config = action.Config
	
	-- Check if this action forces combo end (like M1_4 finisher)
	if config.ForceComboEnd and not wasCanceled then
		self.ComboResetFrame = self.CurrentFrame + 30 -- 0.5s cooldown
		self:ResetCombo()
	end
	
	-- Emit end event
	self.Events.ActionEnded:Fire({
		Type = action.Type,
		WasCanceled = wasCanceled,
	})
	
	-- Clear action
	self.CurrentAction = nil
	self.ActiveHitboxes = {}
	self.HitTargets = {}
	
	-- Return to neutral if not canceled into another action
	if not wasCanceled then
		self:ChangeState("Neutral")
	end
end

--[[
	STATE MANAGEMENT
]]
function CombatCore:ChangeState(newState: string)
	if self.CurrentState == newState then return end
	
	local oldState = self.CurrentState
	self.CurrentState = newState
	self.StateStartFrame = self.CurrentFrame
	
	-- Notify state manager
	self.StateManager:OnStateChanged(oldState, newState)
	
	-- Emit event
	self.Events.StateChanged:Fire({
		Old = oldState,
		New = newState,
		Frame = self.CurrentFrame,
	})
end

function CombatCore:GetCurrentState(): string
	return self.CurrentState
end

--[[
	CANCEL SYSTEM
]]
function CombatCore:CanCancelCurrentAction(intoInputType: string): boolean
	if not self.CurrentAction then return true end
	
	local config = self.CurrentAction.Config
	local phase = self.CurrentAction.Phase
	
	-- Check if cancels are allowed in this phase
	if not config.CancelRules then return false end
	
	local phaseRules = config.CancelRules[phase]
	if not phaseRules then return false end
	
	-- Check if this specific input type can cancel
	return phaseRules[intoInputType] == true
end

--[[
	COMBO SYSTEM - PROFESSIONAL SBG STYLE
	
	Attack Windows:
	- Each attack opens a window during late recovery
	- Player MUST input next attack during this window
	- Too early = blocked, too late = combo resets
	- This creates rhythm and prevents spam
]]
function CombatCore:IsValidComboInput(): boolean
	-- First hit always valid (if not on cooldown)
	if self.ComboCounter == 0 then
		return self:CanStartNewCombo()
	end
	
	-- For combo continuation: must be in attack window
	if not self.InAttackWindow then
		return false -- Not in valid window, input rejected
	end
	
	-- Check max combo length (4 hits)
	if self.ComboCounter >= 4 then
		return false
	end
	
	return true
end

function CombatCore:AdvanceCombo()
	self.ComboCounter = self.ComboCounter + 1
	self.LastComboFrame = self.CurrentFrame
	table.insert(self.ComboChain, self.CurrentFrame)
	
	-- Close previous attack window since we're advancing
	self.InAttackWindow = false
	
	-- After 4th hit, force combo end
	if self.ComboCounter >= 4 then
		self.ComboResetFrame = self.CurrentFrame + 45 -- 0.75s cooldown after full combo
	end
end

function CombatCore:ResetCombo()
	self.ComboCounter = 0
	self.ComboChain = {}
	self.LastComboFrame = 0
	self.ComboResetFrame = 0
	self.InAttackWindow = false
	self.AttackWindowEndFrame = 0
end

function CombatCore:CanStartNewCombo(): boolean
	-- Check if enough time passed since last combo ended
	if self.ComboResetFrame == 0 then return true end
	return self.CurrentFrame >= self.ComboResetFrame
end

--[[
	Open attack window during recovery phase
	This is when the player can input the next attack
]]
function CombatCore:OpenAttackWindow(durationFrames: number)
	self.InAttackWindow = true
	self.AttackWindowEndFrame = self.CurrentFrame + durationFrames
	
	-- Emit event for UI/VFX
	self.Events.CancelOpened:Fire()
end

function CombatCore:CloseAttackWindow()
	self.InAttackWindow = false
	self.AttackWindowEndFrame = 0
	
	self.Events.CancelClosed:Fire()
end

--[[
	Check if attack window has expired
	Called each frame
]]
function CombatCore:UpdateAttackWindow()
	if self.InAttackWindow and self.CurrentFrame >= self.AttackWindowEndFrame then
		self:CloseAttackWindow()
		
		-- Window expired without input = combo broken
		if self.ComboCounter > 0 and self.ComboCounter < 4 then
			-- Small grace period before full reset
			self.ComboResetFrame = self.CurrentFrame + 15 -- 0.25s grace
		end
	end
end

--[[
	COOLDOWN SYSTEM
]]
function CombatCore:SetCooldown(abilityName: string, cooldownFrames: number)
	self.Cooldowns[abilityName] = self.CurrentFrame + cooldownFrames
end

function CombatCore:IsOnCooldown(abilityName: string): boolean
	local readyFrame = self.Cooldowns[abilityName]
	if not readyFrame then return false end
	return self.CurrentFrame < readyFrame
end

function CombatCore:UpdateCooldowns()
	-- Cooldowns are frame-based, no active cleanup needed
	-- Could add events here for UI updates
end

--[[
	HIT VALIDATION - Server only
	Subsystem will call this when a hit is detected
]]
function CombatCore:ValidateHit(target: Model, hitPosition: Vector3): boolean
	if not self.IsServer then
		warn("ValidateHit called on client - hits must be validated server-side")
		return false
	end
	
	-- Check if we're in active frames
	if not self.CurrentAction or self.CurrentAction.Phase ~= "Active" then
		return false
	end
	
	-- Check if already hit this target
	if self.HitTargets[target] then
		return false -- No double-hitting
	end
	
	-- Mark as hit
	self.HitTargets[target] = true
	
	return true
end

function CombatCore:ConfirmHit(target: Model, damage: number, knockback: Vector3)
	-- This is called after ValidateHit passes
	self.Events.HitConfirmed:Fire({
		Target = target,
		Damage = damage,
		Knockback = knockback,
		Frame = self.CurrentFrame,
	})
end

--[[
	CONFIG LOADING
	Action configs define frame data, hitboxes, damage, etc.
]]
function CombatCore:GetActionConfig(actionType: string, actionData: any)
	-- This will load from ReplicatedStorage configs
	-- For now, return a placeholder
	
	if actionType == "M1" then
		return self:GetM1Config(actionData.ComboIndex or 1)
	elseif actionType == "Dash" then
		return self:GetDashConfig(actionData.Direction)
	elseif actionType == "Ability" then
		return self:GetAbilityConfig(actionData.AbilityName)
	end
	
	return nil
end

function CombatCore:GetM1Config(comboIndex: number)
	-- Placeholder - will load from config module
	return {
		StartupFrames = 3,
		ActiveFrames = 4,
		RecoveryFrames = 8,
		TotalFrames = 15,
		RequiredState = "Attacking",
		CancelRules = {
			Active = { Dash = true },
			Recovery = { M1 = true, Dash = true },
		},
	}
end

function CombatCore:GetDashConfig(direction: string)
	return {
		StartupFrames = 2,
		ActiveFrames = 10,
		RecoveryFrames = 5,
		TotalFrames = 17,
		RequiredState = "Dashing",
		CancelRules = {
			Recovery = { M1 = true, Ability = true },
		},
	}
end

function CombatCore:GetAbilityConfig(abilityName: string)
	return {
		StartupFrames = 8,
		ActiveFrames = 6,
		RecoveryFrames = 15,
		TotalFrames = 29,
		RequiredState = "Attacking",
		Cooldown = 180, -- 3 seconds at 60fps
		CancelRules = {},
	}
end

--[[
	CLEANUP
]]
function CombatCore:Destroy()
	if self.FrameConnection then
		self.FrameConnection:Disconnect()
	end
	
	for _, event in pairs(self.Events) do
		event:Destroy()
	end
	
	self.StateManager:Destroy()
	self.NetworkSync:Destroy()
end

return CombatCore