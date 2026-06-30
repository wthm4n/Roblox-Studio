--!strict
-- AnimationComponent.lua
-- Server-side R6 Animation Controller (Event-Driven)

local Signal = require(game:GetService("ReplicatedStorage").Framework.Signal)

-- Default R6 Animation IDs
local DEFAULT_IDS = {
	Idle = "rbxassetid://180435571",
	Walk = "rbxassetid://180426354",
	Run  = "rbxassetid://180426354",
	Jump = "rbxassetid://125750702",
	Fall = "rbxassetid://180436148",
	Climb = "rbxassetid://180436334",
}

export type AnimationIds = {
	Idle: string?, Walk: string?, Run: string?,
	Jump: string?, Fall: string?, Climb: string?,
}

export type AnimationComponentConfig = {
	AnimationIds: AnimationIds?,
	FadeTime: number?,
}

export type AnimationComponent = {
	Init: (self: AnimationComponent, entity: any) -> (),
	Start: (self: AnimationComponent) -> (),
	Stop: (self: AnimationComponent) -> (),
	Destroy: (self: AnimationComponent) -> (),

	_entity: any,
	_humanoid: Humanoid?,
	_animator: Animator?,
	_tracks: { [string]: AnimationTrack },
	_currentTrack: AnimationTrack?,
	_fadeTime: number,
	_connections: { RBXScriptConnection },
}

local AnimationComponent = {}
AnimationComponent.__index = AnimationComponent

function AnimationComponent:Init(entity: any)
	self._entity = entity
	self._tracks = {}
	self._connections = {}
	self._fadeTime = (entity._config and entity._config.FadeTime) or 0.15

	local model = entity.Model
	if not model then return end

	self._humanoid = model:FindFirstChildOfClass("Humanoid")
	if not self._humanoid then return end

	-- Ensure Animator exists
	self._animator = self._humanoid:FindFirstChildOfClass("Animator") 
		or Instance.new("Animator", self._humanoid)

	-- Load Animation Tracks (Merge custom with defaults)
	local config = (entity._config :: AnimationComponentConfig?) or {}
	local customIds = config.AnimationIds or {}
	
	for state, defaultId in pairs(DEFAULT_IDS) do
		local id = customIds[state :: any] or defaultId
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		
		local track = (self._animator :: Animator):LoadAnimation(anim)
		track.Looped = (state ~= "Jump" and state ~= "Fall")
		self._tracks[state] = track
	end
end

function AnimationComponent:_playState(state: string)
	local track = self._tracks[state]
	if not track or self._currentTrack == track then return end

	if self._currentTrack then
		self._currentTrack:Stop(self._fadeTime)
	end
	
	track:Play(self._fadeTime)
	self._currentTrack = track
end

function AnimationComponent:Start()
	local hum = self._humanoid
	if not hum then return end

	-- Event-Driven Transitions.
	-- NOTE: HumanoidStateType.Running fires whenever the humanoid isn't
	-- idle/jumping/falling/climbing -- INCLUDING while standing still
	-- with zero MoveDirection (e.g. right after Movement:Stop() calls
	-- Humanoid:Move(Vector3.zero)). Roblox does not reliably transition
	-- back to the Idle state in that case, so driving Walk off this
	-- event alone left stationary minions stuck playing the Walk/Run
	-- animation forever. Walk/Idle is now driven off actual
	-- MoveDirection magnitude instead; StateChanged is kept only for
	-- the states that ARE reliable signals (Jump/Fall/Climb).
	table.insert(self._connections, hum:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if hum.MoveDirection.Magnitude > 0.05 then
			self:_playState("Walk")
		else
			self:_playState("Idle")
		end
	end))

	table.insert(self._connections, hum.StateChanged:Connect(function(_, newState)
		if newState == Enum.HumanoidStateType.Jumping then
			self:_playState("Jump")
		elseif newState == Enum.HumanoidStateType.Freefall then
			self:_playState("Fall")
		elseif newState == Enum.HumanoidStateType.Climbing then
			self:_playState("Climb")
		end
	end))

	-- Initial State
	self:_playState("Idle")
end

function AnimationComponent:Stop()
	for _, conn in ipairs(self._connections) do
		conn:Disconnect()
	end
	table.clear(self._connections)
	if self._currentTrack then self._currentTrack:Stop() end
end

function AnimationComponent:Destroy()
	self:Stop()
	for _, track in pairs(self._tracks) do track:Destroy() end
	table.clear(self._tracks)
end

local function new(config: AnimationComponentConfig?): AnimationComponent
	return setmetatable({
		_tracks = {},
		_connections = {},
		_fadeTime = 0.15,
		_config = config,
	}, AnimationComponent) :: any
end

return { new = new }