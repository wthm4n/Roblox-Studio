--[[
	CAMERA CONTROLLER
	
	Camera is reactive, not decorative.
	Responds to combat events with:
	- Hit stop (freeze frame)
	- Screen shake
	- FOV modulation
	- Impact effects
	
	SUBSYSTEM - Listens to Core events
]]

local CameraController = {}
CameraController.__index = CameraController

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

function CameraController.new(core)
	local self = setmetatable({}, CameraController)

	self.Core = core
	self.Camera = workspace.CurrentCamera

	-- Shake state
	self.ShakeIntensity = 0
	self.ShakeDuration = 0
	self.ShakeTimer = 0

	-- Hit stop state
	self.HitStopDuration = 0
	self.HitStopTimer = 0
	self.IsHitStopped = false

	-- Original camera values
	self.OriginalFOV = self.Camera.FieldOfView
	self.BaseCFrame = self.Camera.CFrame

	-- Connections
	self.Connections = {}

	-- Listen to combat events
	self.Connections.HitConfirmed = core.Events.HitConfirmed.Event:Connect(function(hitData)
		self:OnHitConfirmed(hitData)
	end)

	self.Connections.ActionStarted = core.Events.ActionStarted.Event:Connect(function(actionData)
		self:OnActionStarted(actionData)
	end)

	self.Connections.DamageTaken = core.Events.DamageTaken.Event:Connect(function(damageData)
		self:OnDamageTaken(damageData)
	end)

	-- Update loop
	self.Connections.RenderStepped = RunService.RenderStepped:Connect(function(dt)
		self:Update(dt)
	end)

	return self
end

--[[
	EVENT HANDLERS
]]
function CameraController:OnHitConfirmed(hitData)
	-- Screen shake on successful hit
	local config = self.Core.CurrentAction and self.Core.CurrentAction.Config

	if config and config.CameraShake then
		self:ApplyShake(config.CameraShake.Magnitude or 0.5, config.CameraShake.Duration or 0.2)
	else
		-- Default light shake
		self:ApplyShake(0.3, 0.15)
	end

	-- Hit stop effect (freeze frame)
	if config and config.HitStop then
		self:ApplyHitStop(config.HitStop or 0.05)
	else
		-- Default subtle hit stop
		self:ApplyHitStop(0.03)
	end

	-- FOV punch effect
	self:ApplyFOVPunch(-2, 0.1)
end

function CameraController:OnActionStarted(actionData)
	-- Camera effects for certain abilities
	local config = actionData.Config

	if config.CameraShake then
		self:ApplyShake(config.CameraShake.Magnitude, config.CameraShake.Duration)
	end

	-- FOV change for dashes
	if actionData.Type == "Dash" then
		self:ApplyFOVPunch(3, 0.2) -- Zoom out slightly
	end
end

function CameraController:OnDamageTaken(damageData)
	-- Shake when taking damage
	local magnitude = math.clamp(damageData.Damage / 20, 0.2, 1.0)
	self:ApplyShake(magnitude, 0.25)

	-- Red flash would go here (not implemented)
end

--[[
	SCREEN SHAKE
]]
function CameraController:ApplyShake(magnitude: number, duration: number)
	-- Add to existing shake (don't override)
	self.ShakeIntensity = math.max(self.ShakeIntensity, magnitude)
	self.ShakeDuration = math.max(self.ShakeDuration, duration)
	self.ShakeTimer = 0
end

function CameraController:UpdateShake(dt: number)
	if self.ShakeIntensity <= 0 then
		return
	end

	self.ShakeTimer = self.ShakeTimer + dt

	-- Decrease intensity over time
	local progress = self.ShakeTimer / self.ShakeDuration
	if progress >= 1 then
		self.ShakeIntensity = 0
		return
	end

	-- Apply shake to camera
	local currentIntensity = self.ShakeIntensity * (1 - progress)

	local shake = Vector3.new(math.random(-100, 100) / 100, math.random(-100, 100) / 100, math.random(-100, 100) / 100)
		* currentIntensity

	self.Camera.CFrame = self.Camera.CFrame * CFrame.Angles(math.rad(shake.X), math.rad(shake.Y), math.rad(shake.Z))
end

--[[
	HIT STOP (Freeze Frame)
]]
function CameraController:ApplyHitStop(duration: number)
	self.HitStopDuration = duration
	self.HitStopTimer = 0
	self.IsHitStopped = true

	-- Slow down time perception (visual effect)
	-- In a real implementation, you'd also slow animations briefly
end

function CameraController:UpdateHitStop(dt: number)
	if not self.IsHitStopped then
		return
	end

	self.HitStopTimer = self.HitStopTimer + dt

	if self.HitStopTimer >= self.HitStopDuration then
		self.IsHitStopped = false
		self.HitStopTimer = 0
	end

	-- Could implement actual frame freeze here
	-- by pausing animations temporarily
end

--[[
	FOV EFFECTS
]]
function CameraController:ApplyFOVPunch(amount: number, duration: number)
	local targetFOV = self.OriginalFOV + amount

	-- Tween to target FOV and back
	local tweenInfo = TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local tween1 = TweenService:Create(self.Camera, tweenInfo, {
		FieldOfView = targetFOV,
	})

	tween1.Completed:Connect(function()
		local tween2 = TweenService:Create(self.Camera, tweenInfo, {
			FieldOfView = self.OriginalFOV,
		})
		tween2:Play()
	end)

	tween1:Play()
end

--[[
	UPDATE LOOP
]]
function CameraController:Update(dt: number)
	self:UpdateShake(dt)
	self:UpdateHitStop(dt)
end

--[[
	PUBLIC API
]]
function CameraController:SetShakeEnabled(enabled: boolean)
	if not enabled then
		self.ShakeIntensity = 0
	end
end

function CameraController:Destroy()
	for _, conn in pairs(self.Connections) do
		conn:Disconnect()
	end

	-- Reset camera
	self.Camera.FieldOfView = self.OriginalFOV
end

return CameraController
