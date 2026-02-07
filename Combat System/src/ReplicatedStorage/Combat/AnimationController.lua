--[[
	ANIMATION CONTROLLER
	
	Animations do NOT deal damage.
	Animations only emit SIGNALS.
	
	The Core listens and decides what happens.
	
	Signals:
	- HitFrameStart
	- HitFrameEnd
	- CancelOpen
	- CancelClose
	- FootstepFrame
	
	This allows swapping animations without breaking combat.
]]

local AnimationController = {}
AnimationController.__index = AnimationController

local RunService = game:GetService("RunService")

function AnimationController.new(core, animationConfig)
	local self = setmetatable({}, AnimationController)
	
	self.Core = core
	self.Character = core.Character
	self.Humanoid = core.Humanoid
	self.Animator = core.Humanoid:WaitForChild("Animator")
	
	-- Animation config (loaded from ReplicatedStorage)
	self.Config = animationConfig or {}
	
	-- Currently playing tracks
	self.CurrentTracks = {} -- { TrackName = AnimationTrack }
	
	-- Animation marker tracking
	self.MarkerConnections = {}
	
	-- Connections
	self.Connections = {}
	
	-- Listen to core events
	self.Connections.ActionStarted = core.Events.ActionStarted.Event:Connect(function(actionData)
		self:OnActionStarted(actionData)
	end)
	
	self.Connections.ActionEnded = core.Events.ActionEnded.Event:Connect(function(actionData)
		self:OnActionEnded(actionData)
	end)
	
	self.Connections.StateChanged = core.Events.StateChanged.Event:Connect(function(stateData)
		self:OnStateChanged(stateData)
	end)
	
	return self
end

--[[
	Core started an action - play appropriate animation
]]
function AnimationController:OnActionStarted(actionData)
	local animationName = self:GetAnimationName(actionData)
	
	if not animationName then
		warn("No animation found for action:", actionData.Type)
		return
	end
	
	self:PlayAnimation(animationName, actionData)
end

function AnimationController:OnActionEnded(actionData)
	-- Stop current action animation
	local animationName = self:GetAnimationName(actionData)
	
	if animationName then
		self:StopAnimation(animationName)
	end
end

function AnimationController:OnStateChanged(stateData)
	-- Play state transition animations
	if stateData.New == "Hitstun" then
		self:PlayAnimation("Hit", { Priority = Enum.AnimationPriority.Action4 })
	elseif stateData.New == "Knockback" then
		self:PlayAnimation("Knockback", { Priority = Enum.AnimationPriority.Action4 })
	end
end

--[[
	Get animation name from action data
]]
function AnimationController:GetAnimationName(actionData): string?
	local actionType = actionData.Type
	
	if actionType == "M1" then
		-- Get combo-specific animation
		local comboIndex = self.Core.ComboCounter
		return self:GetM1Animation(comboIndex)
		
	elseif actionType == "Dash" then
		local direction = actionData.Data.Direction
		return self:GetDashAnimation(direction)
		
	elseif actionType == "Ability" then
		local abilityName = actionData.Data.AbilityName
		return abilityName -- Ability animations named after ability
	end
	
	return nil
end

function AnimationController:GetM1Animation(comboIndex: number): string
	-- Cycle through M1 combo animations
	local m1Anims = self.Config.M1Animations or {
		"M1_1",
		"M1_2", 
		"M1_3",
		"M1_4",
	}
	
	local index = ((comboIndex - 1) % #m1Anims) + 1
	return m1Anims[index]
end

function AnimationController:GetDashAnimation(direction: string): string
	local dashAnims = self.Config.DashAnimations or {
		Front = "DashFront",
		Back = "DashBack",
		Left = "DashLeft",
		Right = "DashRight",
	}
	
	return dashAnims[direction] or "DashFront"
end

--[[
	Play animation and listen for markers
]]
function AnimationController:PlayAnimation(animationName: string, options: any?)
	-- Load animation from config
	local animationId = self:GetAnimationId(animationName)
	
	if not animationId then
		warn("Animation not found:", animationName)
		return
	end
	
	-- Create Animation object
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	
	-- Load and play
	local track = self.Animator:LoadAnimation(animation)
	
	-- Set priority
	if options and options.Priority then
		track.Priority = options.Priority
	else
		track.Priority = Enum.AnimationPriority.Action
	end
	
	track:Play()
	
	-- Store reference
	self.CurrentTracks[animationName] = track
	
	-- Listen for animation markers
	self:ConnectMarkers(track, animationName)
	
	return track
end

function AnimationController:StopAnimation(animationName: string, fadeTime: number?)
	local track = self.CurrentTracks[animationName]
	
	if track then
		track:Stop(fadeTime or 0.1)
		self.CurrentTracks[animationName] = nil
		
		-- Disconnect marker listeners
		self:DisconnectMarkers(animationName)
	end
end

--[[
	ANIMATION MARKERS
	These are keyframes in animations that emit events
]]
function AnimationController:ConnectMarkers(track: AnimationTrack, animationName: string)
	local connection = track:GetMarkerReachedSignal(""):Connect(function(markerName)
		self:OnMarkerReached(markerName, animationName)
	end)
	
	self.MarkerConnections[animationName] = connection
end

function AnimationController:DisconnectMarkers(animationName: string)
	local connection = self.MarkerConnections[animationName]
	if connection then
		connection:Disconnect()
		self.MarkerConnections[animationName] = nil
	end
end

function AnimationController:OnMarkerReached(markerName: string, animationName: string)
	-- Emit to Core
	-- Core decides what to do with these signals
	
	if markerName == "HitFrameStart" then
		self.Core.Events.CancelOpened:Fire()
		
	elseif markerName == "HitFrameEnd" then
		self.Core.Events.CancelClosed:Fire()
		
	elseif markerName == "CancelWindow" then
		self.Core.Events.CancelOpened:Fire()
		
	elseif markerName == "Footstep" then
		-- Could trigger footstep sound
		
	elseif markerName == "Impact" then
		-- Could trigger screen shake, hit effects
		-- But damage is NEVER dealt here
	end
end

--[[
	Get animation ID from config
]]
function AnimationController:GetAnimationId(animationName: string): string?
	-- In production, load from ReplicatedStorage config
	-- For now, return placeholder IDs
	
	local animationIds = self.Config.AnimationIds or {
		-- M1 combos
		M1_1 = "rbxassetid://12345678901",
		M1_2 = "rbxassetid://12345678902",
		M1_3 = "rbxassetid://12345678903",
		M1_4 = "rbxassetid://12345678904",
		
		-- Dashes
		DashFront = "rbxassetid://12345678910",
		DashBack = "rbxassetid://12345678911",
		DashLeft = "rbxassetid://12345678912",
		DashRight = "rbxassetid://12345678913",
		
		-- States
		Hit = "rbxassetid://12345678920",
		Knockback = "rbxassetid://12345678921",
	}
	
	return animationIds[animationName]
end

--[[
	Manual animation speed adjustment
	Useful for slow-mo effects, time manipulation abilities
]]
function AnimationController:SetAnimationSpeed(animationName: string, speed: number)
	local track = self.CurrentTracks[animationName]
	if track then
		track:AdjustSpeed(speed)
	end
end

function AnimationController:Destroy()
	-- Stop all tracks
	for name, track in pairs(self.CurrentTracks) do
		track:Stop()
	end
	
	-- Disconnect all connections
	for _, conn in pairs(self.Connections) do
		conn:Disconnect()
	end
	
	for _, conn in pairs(self.MarkerConnections) do
		conn:Disconnect()
	end
end

return AnimationController
