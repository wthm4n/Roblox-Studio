-- ReplicatedStorage/Components/MovementComponent.lua
-- Owns EVERYTHING movement related for a single minion.
-- No other file should touch Humanoid:MoveTo directly.

local MovementComponent = {}
MovementComponent.__index = MovementComponent

function MovementComponent.new(humanoid, options)
	options = options or {}

	return setmetatable({
		Humanoid = humanoid,
		CurrentTarget = nil,
		WalkSpeed = options.WalkSpeed or 16,
		ReachedDistance = options.ReachedDistance or 3,
		_isMoving = false,
	}, MovementComponent)
end

function MovementComponent:SetTarget(position)
	self.CurrentTarget = position
end

-- Called once per Heartbeat by FormationSystem.
-- Moves the humanoid toward CurrentTarget and returns whether it is walking.
function MovementComponent:Move()
	if not self.CurrentTarget or not self.Humanoid or self.Humanoid.Health <= 0 then
		self._isMoving = false
		return self._isMoving
	end

	local rootPart = self.Humanoid.RootPart
	if not rootPart then
		self._isMoving = false
		return self._isMoving
	end

	local distance = (rootPart.Position - self.CurrentTarget).Magnitude

	if distance > self.ReachedDistance then
		self.Humanoid.WalkSpeed = self.WalkSpeed
		self.Humanoid:MoveTo(self.CurrentTarget)
		self._isMoving = true
	else
		self._isMoving = false
	end

	return self._isMoving
end

function MovementComponent:IsMoving()
	return self._isMoving
end

function MovementComponent:Destroy()
	self.CurrentTarget = nil
	self.Humanoid = nil
end

return MovementComponent
