--!strict
-- FollowComponent.lua
-- PURE DATA. No Heartbeat, no logic. All behavior lives in FollowSystem,
-- which iterates every live FollowComponent once per scheduler tick
-- (bucketed). This is the ECS split: component = state, system = work.
--
-- Caching: _rootPart and _targetPart are resolved ONCE (on Init / target
-- change / character respawn) instead of every update. FollowSystem only
-- needs to re-resolve them when a CharacterAdded/AncestryChanged signal
-- says the old reference is stale -- not every tick.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal = require(ReplicatedStorage.Framework.Signal)

type FollowTarget = Player | BasePart | Model

export type FollowComponentConfig = {
	FollowDistance: number?,
	RepathDistance: number?,
}

export type FollowComponent = {
	FollowDistance: number,
	RepathDistance: number,
	Following: boolean,
	Target: FollowTarget?,

	TargetLost: Signal.Signal,

	Init: (self: FollowComponent, entity: any) -> (),
	SetTarget: (self: FollowComponent, target: FollowTarget?) -> (),
	Start: (self: FollowComponent) -> (),
	Stop: (self: FollowComponent) -> (),
	Destroy: (self: FollowComponent) -> (),

	_entity: any,
	_humanoid: Humanoid?,
	_movement: any,             -- cached MovementComponent reference (entity:GetComponent("Movement") once)
	_rootPart: BasePart?,       -- cached own HumanoidRootPart
	_targetPart: BasePart?,     -- cached target's tracked BasePart
	_targetCharConn: RBXScriptConnection?, -- only set if Target is a Player
	_lastTargetPosition: Vector3?,
	_lastDirection: Vector3?,   -- last direction we actually issued to Move()
	_moving: boolean,           -- are we currently telling the humanoid to move
}

local FollowComponent = {}
FollowComponent.__index = FollowComponent

-- Resolves and caches the BasePart we should be tracking for `target`.
-- Called once at SetTarget / Init, and again only when a CharacterAdded
-- fires for a Player target -- never on a per-frame basis.
local function resolveTargetPart(self: FollowComponent): BasePart?
	local target = self.Target
	if not target then
		return nil
	end

	if typeof(target) == "Instance" then
		if target:IsA("Player") then
			local character = (target :: Player).Character
			return character and (character:FindFirstChild("HumanoidRootPart") :: BasePart?)
		elseif target:IsA("BasePart") then
			return target :: BasePart
		elseif target:IsA("Model") then
			return (target :: Model).PrimaryPart
		end
	end

	return nil
end

function FollowComponent:Init(entity: any)
	self._entity = entity

	local model = entity.Model
	if model then
		self._rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		self._humanoid = model:FindFirstChildOfClass("Humanoid")
	end
	self._movement = entity:GetComponent("Movement")

	self._targetPart = resolveTargetPart(self)

	-- Only Player targets need a respawn-tracking connection -- one per
	-- following minion that targets a player, NOT a Heartbeat. This fires
	-- maybe once every few minutes per player, never in the hot path.
	local target = self.Target
	if typeof(target) == "Instance" and target:IsA("Player") then
		self._targetCharConn = (target :: Player).CharacterAdded:Connect(function()
			task.wait(0.5) -- let HumanoidRootPart exist
			self._targetPart = resolveTargetPart(self)
			self._lastTargetPosition = nil
		end)
	end
end

function FollowComponent:SetTarget(target: FollowTarget?)
	if self._targetCharConn then
		self._targetCharConn:Disconnect()
		self._targetCharConn = nil
	end

	self.Target = target
	self._lastTargetPosition = nil
	self._targetPart = resolveTargetPart(self)

	if typeof(target) == "Instance" and target:IsA("Player") then
		self._targetCharConn = (target :: Player).CharacterAdded:Connect(function()
			task.wait(0.5)
			self._targetPart = resolveTargetPart(self)
			self._lastTargetPosition = nil
		end)
	end
end

-- Start/Stop just flip a flag and (un)register with FollowSystem's flat
-- array. No per-component connections are created here.
function FollowComponent:Start()
	self.Following = true
	local FollowSystem = require(game:GetService("ReplicatedStorage").Framework.FollowSystem)
	FollowSystem.Register(self)
end

function FollowComponent:Stop()
	self.Following = false
	self._moving = false
	if self._movement then
		self._movement:SetDirection(Vector3.zero)
	end
	local FollowSystem = require(game:GetService("ReplicatedStorage").Framework.FollowSystem)
	FollowSystem.Unregister(self)
end

function FollowComponent:Destroy()
	self:Stop()
	if self._targetCharConn then
		self._targetCharConn:Disconnect()
		self._targetCharConn = nil
	end
	self.TargetLost:Destroy()
	self.Target = nil
	self._entity = nil
end

local function new(target: FollowTarget?, config: FollowComponentConfig?): FollowComponent
	config = config or {}

	local self = setmetatable({
		FollowDistance = config.FollowDistance or 6,
		RepathDistance = config.RepathDistance or 3,
		Following = false,
		Target = target,

		TargetLost = Signal.new(),

		_entity = nil,
		_humanoid = nil,
		_movement = nil,
		_rootPart = nil,
		_targetPart = nil,
		_targetCharConn = nil,
		_lastTargetPosition = nil,
		_lastDirection = nil,
		_moving = false,
	}, FollowComponent)

	return (self :: any) :: FollowComponent
end

return {
	new = new,
}