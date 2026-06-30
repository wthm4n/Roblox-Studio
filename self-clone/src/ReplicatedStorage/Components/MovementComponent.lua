--!strict
-- MovementComponent.lua
-- Still owns the Humanoid reference and walk speed -- still pure data/thin
-- wrapper, no Heartbeat. Two movement primitives are exposed:
--
--   :MoveTo(position)   -- pathed, one-shot destination (waypoints/patrol/
--                           AI goals). Use sparingly: this is the expensive
--                           primitive that triggers Roblox's internal
--                           path-following state machine.
--
--   :SetDirection(dir)  -- persistent velocity (Humanoid:Move). This is
--                           what FollowSystem uses every tick. Cheap,
--                           idempotent-safe to call, no internal state
--                           machine restart.
--
-- :Stop() no longer calls MoveTo(currentPosition) -- that was wasted path
-- computation just to halt. It now zeroes velocity directly.

local Signal = require(game:GetService("ReplicatedStorage").Framework.Signal)

export type MovementComponent = {
	WalkSpeed: number,
	Moving: boolean,

	MoveFinished: Signal.Signal, -- (reached: boolean) -- only fires for MoveTo, not SetDirection

	Init: (self: MovementComponent, entity: any) -> (),
	MoveTo: (self: MovementComponent, position: Vector3) -> (),
	SetDirection: (self: MovementComponent, direction: Vector3) -> (),
	Stop: (self: MovementComponent) -> (),
	SetWalkSpeed: (self: MovementComponent, speed: number) -> (),
	Destroy: (self: MovementComponent) -> (),

	_entity: any,
	_humanoid: Humanoid?,
	_moveConnection: RBXScriptConnection?,
}

local MovementComponent = {}
MovementComponent.__index = MovementComponent

function MovementComponent:Init(entity: any)
	self._entity = entity
	self._humanoid = entity.Model and entity.Model:FindFirstChildOfClass("Humanoid")

	if self._humanoid then
		self._humanoid.WalkSpeed = self.WalkSpeed
	end
end

function MovementComponent:MoveTo(position: Vector3)
	local humanoid = self._humanoid
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if self._moveConnection then
		self._moveConnection:Disconnect()
		self._moveConnection = nil
	end

	self.Moving = true
	humanoid:MoveTo(position)

	self._moveConnection = humanoid.MoveToFinished:Once(function(reached: boolean)
		self.Moving = false
		self._moveConnection = nil
		self.MoveFinished:Fire(reached)
	end)
end

-- Cheap, persistent-velocity movement. Safe to call every system tick --
-- Humanoid:Move() does not allocate or restart any internal pathing
-- state, it just sets the desired move direction for physics to consume.
function MovementComponent:SetDirection(direction: Vector3)
	local humanoid = self._humanoid
	if not humanoid or humanoid.Health <= 0 then
		return
	end
	self.Moving = direction.Magnitude > 0.01
	humanoid:Move(direction)
end

function MovementComponent:Stop()
	local humanoid = self._humanoid
	if not humanoid then
		return
	end

	if self._moveConnection then
		self._moveConnection:Disconnect()
		self._moveConnection = nil
	end

	self.Moving = false
    if self._humanoid then
        self._humanoid:Move(Vector3.zero)
    end
end

function MovementComponent:SetWalkSpeed(speed: number)
	self.WalkSpeed = speed
	if self._humanoid then
		self._humanoid.WalkSpeed = speed
	end
end

function MovementComponent:Destroy()
	if self._moveConnection then
		self._moveConnection:Disconnect()
		self._moveConnection = nil
	end
	self.MoveFinished:Destroy()
	self._humanoid = nil
	self._entity = nil
end

local function new(walkSpeed: number?): MovementComponent
	local self = setmetatable({
		WalkSpeed = walkSpeed or 16,
		Moving = false,

		MoveFinished = Signal.new(),

		_entity = nil,
		_humanoid = nil,
		_moveConnection = nil,
	}, MovementComponent)

	return (self :: any) :: MovementComponent
end

return {
	new = new,
}