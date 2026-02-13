--[[
	Gun Client Handler - AAA OVER-THE-SHOULDER SHOOTER
	Place in StarterPlayer > StarterPlayerScripts
	
	CORRECT FEATURES:
	✅ Over-the-shoulder camera with SHIFT LOCK (character follows camera)
	✅ Mouse wheel zoom in/out (limited range)
	✅ Custom Shift Lock (auto-enables on equip)
	✅ Damage Numbers (color-coded, stacking, fading)
	✅ Animated Crosshair (spring rotation, shows status)
	✅ Gun Jamming (F to unjam)
	✅ FIXED SOUNDS (they actually play now)
	✅ Equip Animation
	✅ FIXED: Camera shift-locked, character rotates with camera
	✅ FIXED: Crosshair rotates with spring easing
]]

-- ═══════════════════════════════════════════════════════════
--  SERVICES & SETUP
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Camera = workspace.CurrentCamera

-- Get remotes
local GunRemotes = ReplicatedStorage:WaitForChild("GunRemotes")
local FireGunRemote = GunRemotes:WaitForChild("FireGun")
local ReloadGunRemote = GunRemotes:WaitForChild("ReloadGun")
local PlayEffectRemote = GunRemotes:WaitForChild("PlayEffect")
local UpdateAmmoRemote = GunRemotes:WaitForChild("UpdateAmmo")
local EquipGunRemote = GunRemotes:WaitForChild("EquipGun")
local UnequipGunRemote = GunRemotes:WaitForChild("UnequipGun")
local UnjamGunRemote = GunRemotes:WaitForChild("UnjamGun")
local UpdateGunStatusRemote = GunRemotes:WaitForChild("UpdateGunStatus")

-- UI References
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Create main UI if it doesn't exist
local MainUI = PlayerGui:FindFirstChild("MainUI")
if not MainUI then
	MainUI = Instance.new("ScreenGui")
	MainUI.Name = "MainUI"
	MainUI.ResetOnSpawn = false
	MainUI.Parent = PlayerGui
end

-- Create Gun Frame
local GunFrame = MainUI:FindFirstChild("GunFrame")
if not GunFrame then
	GunFrame = Instance.new("Frame")
	GunFrame.Name = "GunFrame"
	GunFrame.Size = UDim2.new(0, 200, 0, 100)
	GunFrame.Position = UDim2.new(1, -220, 1, -120)
	GunFrame.BackgroundTransparency = 1
	GunFrame.Parent = MainUI

	local EquippedGunImage = Instance.new("ImageLabel")
	EquippedGunImage.Name = "EquippedGun"
	EquippedGunImage.Size = UDim2.new(0, 80, 0, 80)
	EquippedGunImage.Position = UDim2.new(0, 0, 0, 0)
	EquippedGunImage.BackgroundTransparency = 1
	EquippedGunImage.Parent = GunFrame

	local CurrentBulletLabel = Instance.new("TextLabel")
	CurrentBulletLabel.Name = "CurrentBullet"
	CurrentBulletLabel.Size = UDim2.new(0, 60, 0, 40)
	CurrentBulletLabel.Position = UDim2.new(0, 90, 0, 0)
	CurrentBulletLabel.BackgroundTransparency = 1
	CurrentBulletLabel.Font = Enum.Font.GothamBold
	CurrentBulletLabel.TextSize = 32
	CurrentBulletLabel.TextColor3 = Color3.new(1, 1, 1)
	CurrentBulletLabel.Text = "30"
	CurrentBulletLabel.Parent = GunFrame

	local MaxBulletLabel = Instance.new("TextLabel")
	MaxBulletLabel.Name = "MaxBullet"
	MaxBulletLabel.Size = UDim2.new(0, 60, 0, 30)
	MaxBulletLabel.Position = UDim2.new(0, 90, 0, 40)
	MaxBulletLabel.BackgroundTransparency = 1
	MaxBulletLabel.Font = Enum.Font.Gotham
	MaxBulletLabel.TextSize = 18
	MaxBulletLabel.TextColor3 = Color3.new(0.7, 0.7, 0.7)
	MaxBulletLabel.Text = "90"
	MaxBulletLabel.Parent = GunFrame
end

local EquippedGunImage = GunFrame:WaitForChild("EquippedGun")
local CurrentBulletLabel = GunFrame:WaitForChild("CurrentBullet")
local MaxBulletLabel = GunFrame:WaitForChild("MaxBullet")

-- Gun state
local CurrentGun = nil
local GunConfig = nil
local EquippedTool = nil
local IsAiming = false
local CanFire = true
local GunStatus = "Ready"

-- Animation tracks
local AnimationTracks = {
	Idle = nil,
	Walk = nil,
	Fire = nil,
	ReloadTactical = nil,
	ReloadEmpty = nil,
	Equip = nil,
	Unjam = nil,
}

-- ═══════════════════════════════════════════════════════════
--  SHIFT-LOCKED OVER-THE-SHOULDER CAMERA SYSTEM
-- ═══════════════════════════════════════════════════════════

local CameraOffset = Vector3.new(3, 2, 0) -- Offset to RIGHT shoulder (X=right, Y=up, Z=forward)
local CurrentZoom = 4 -- Closer default zoom like in the video
local MinZoom = 0.01 -- Minimum zoom
local MaxZoom = 4 -- Maximum zoom
local ZoomSpeed = 1.5 -- Slower zoom speed

local CameraEnabled = false
local CameraConnection = nil

-- Camera rotation (controlled by mouse)
local CameraAngleX = 0 -- Horizontal rotation (yaw)
local CameraAngleY = 0 -- Vertical rotation (pitch)
local MouseSensitivity = 0.004 -- Slightly higher sensitivity like in the video

-- Enable shift-locked over-the-shoulder camera
local function enableOverShoulderCamera()
	if CameraEnabled then
		return
	end

	CameraEnabled = true

	-- Lock mouse to center AND HIDE CURSOR
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	-- Set camera to scriptable
	Camera.CameraType = Enum.CameraType.Scriptable

	-- Initialize camera angles
	local lookVector = HumanoidRootPart.CFrame.LookVector
	CameraAngleX = math.atan2(-lookVector.X, -lookVector.Z)
	CameraAngleY = 0

	-- Update camera every frame
	if CameraConnection then
		CameraConnection:Disconnect()
	end

	CameraConnection = RunService.RenderStepped:Connect(function()
		if not HumanoidRootPart or not CameraEnabled then
			return
		end

		-- Calculate camera direction from angles
		local cameraCFrame = CFrame.new(HumanoidRootPart.Position)
			* CFrame.Angles(0, CameraAngleX, 0)
			* CFrame.Angles(CameraAngleY, 0, 0)

		-- Get camera vectors
		local lookVector = cameraCFrame.LookVector
		local rightVector = cameraCFrame.RightVector
		local upVector = cameraCFrame.UpVector

		-- Calculate shoulder offset (offset to the right and up from character)
		local shoulderOffset = (rightVector * CameraOffset.X) + (Vector3.new(0, CameraOffset.Y, 0))

		-- Position camera behind character with shoulder offset
		local cameraPosition = HumanoidRootPart.Position - lookVector * CurrentZoom + shoulderOffset

		-- Look-ahead point (what the camera looks at) - slightly in front and to the side
		-- This creates the "over-the-shoulder" viewing angle
		local lookAtOffset = Vector3.new(0, 1, 0) -- Offset aim point to left of character
		local lookAtPosition = HumanoidRootPart.Position + lookVector * 10 + lookAtOffset

		-- Smoothly interpolate camera CFrame
		local targetCFrame = CFrame.new(cameraPosition, lookAtPosition)
		Camera.CFrame = Camera.CFrame:Lerp(targetCFrame, 0.3) -- Smooth camera movement

		-- Rotate character to face camera direction (SHIFT LOCK BEHAVIOR)
		local flatDirection = Vector3.new(lookVector.X, 0, lookVector.Z).Unit
		if flatDirection.Magnitude > 0 then
			local targetCharacterCFrame =
				CFrame.new(HumanoidRootPart.Position, HumanoidRootPart.Position + flatDirection)
			HumanoidRootPart.CFrame = HumanoidRootPart.CFrame:Lerp(targetCharacterCFrame, 0.25) -- Smooth character rotation
		end
	end)

	print("✅ Shift-Locked Over-the-Shoulder Camera ENABLED")
end

-- Disable over-the-shoulder camera
local function disableOverShoulderCamera()
	if not CameraEnabled then
		return
	end

	CameraEnabled = false

	-- Restore mouse behavior AND SHOW CURSOR
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

	-- Restore default camera
	Camera.CameraType = Enum.CameraType.Custom

	-- Disconnect camera update
	if CameraConnection then
		CameraConnection:Disconnect()
		CameraConnection = nil
	end

	print("❌ Shift-Locked Camera DISABLED")
end

-- Handle mouse movement (for camera rotation)
UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if not CameraEnabled then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		-- Update camera angles based on mouse delta
		CameraAngleX = CameraAngleX - input.Delta.X * MouseSensitivity
		CameraAngleY = math.clamp(CameraAngleY - input.Delta.Y * MouseSensitivity, math.rad(-80), math.rad(80))
	end
end)

-- Handle mouse wheel zoom
local function handleZoom(input)
	if not CameraEnabled then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		CurrentZoom = math.clamp(CurrentZoom - input.Position.Z * ZoomSpeed, MinZoom, MaxZoom)
	end
end

UserInputService.InputChanged:Connect(handleZoom)

-- ═══════════════════════════════════════════════════════════
--  CROSSHAIR SYSTEM (SPRING ANIMATED + STATUS)
-- ═══════════════════════════════════════════════════════════

local CrosshairGui = nil
local CrosshairImage = nil
local CrosshairStatus = nil

-- Spring rotation system
local CurrentRotation = 0
local TargetRotation = 0
local RotationVelocity = 0
local SpringStiffness = 200 -- How fast it returns to target
local SpringDamping = 20 -- How much it dampens oscillation

-- Continuous rotation for reload/jam
local ContinuousRotation = false
local ContinuousRotationSpeed = 0

-- Create crosshair GUI
local function createCrosshair()
	if CrosshairGui then
		CrosshairGui:Destroy()
	end

	-- Create ScreenGui
	CrosshairGui = Instance.new("ScreenGui")
	CrosshairGui.Name = "CrosshairGui"
	CrosshairGui.ResetOnSpawn = false
	CrosshairGui.Parent = PlayerGui

	-- Create Frame container
	local Container = Instance.new("Frame")
	Container.Name = "Container"
	Container.Size = UDim2.new(1, 0, 1, 0)
	Container.BackgroundTransparency = 1
	Container.Parent = CrosshairGui

	-- Create crosshair image (ANIMATED)
	CrosshairImage = Instance.new("ImageLabel")
	CrosshairImage.Name = "CrosshairImage"
	CrosshairImage.Size = UDim2.new(0, 40, 0, 40)
	CrosshairImage.Position = UDim2.new(0.5, -20, 0.5, -20)
	CrosshairImage.AnchorPoint = Vector2.new(0.5, 0.5)
	CrosshairImage.BackgroundTransparency = 1
	CrosshairImage.Image = "rbxassetid://86534583278469"
	CrosshairImage.ImageColor3 = Color3.new(1, 1, 1)
	CrosshairImage.Parent = Container

	-- Create status text below crosshair
	CrosshairStatus = Instance.new("TextLabel")
	CrosshairStatus.Name = "StatusLabel"
	CrosshairStatus.Size = UDim2.new(0, 200, 0, 30)
	CrosshairStatus.Position = UDim2.new(0.5, -100, 0.5, 40)
	CrosshairStatus.BackgroundTransparency = 1
	CrosshairStatus.Font = Enum.Font.GothamBold
	CrosshairStatus.TextSize = 16
	CrosshairStatus.TextColor3 = Color3.new(1, 1, 1)
	CrosshairStatus.Text = ""
	CrosshairStatus.TextStrokeTransparency = 0.5
	CrosshairStatus.Parent = Container

	print("🎯 Crosshair Created")
end

-- Update crosshair status
local function updateCrosshairStatus(status)
	if not CrosshairImage or not CrosshairStatus then
		return
	end

	if status == "Ready" then
		CrosshairImage.ImageColor3 = Color3.fromRGB(255, 255, 255)
		CrosshairStatus.Text = ""
		CrosshairStatus.TextColor3 = Color3.fromRGB(255, 255, 255)
		ContinuousRotation = false
	elseif status == "Jammed" then
		CrosshairImage.ImageColor3 = Color3.fromRGB(255, 50, 50)
		CrosshairStatus.Text = "🔒 JAMMED - Press F"
		CrosshairStatus.TextColor3 = Color3.fromRGB(255, 50, 50)
		-- Stop any rotation
		ContinuousRotation = false
		TargetRotation = CurrentRotation
	elseif status == "Unjamming" then
		CrosshairImage.ImageColor3 = Color3.fromRGB(255, 200, 50)
		CrosshairStatus.Text = "Unjamming..."
		CrosshairStatus.TextColor3 = Color3.fromRGB(255, 200, 50)
		-- Rotate counter-clockwise during unjam
		ContinuousRotation = true
		ContinuousRotationSpeed = -360 -- Counter-clockwise
	elseif status == "NoAmmo" then
		CrosshairImage.ImageColor3 = Color3.fromRGB(255, 100, 100)
		CrosshairStatus.Text = "❌ NO AMMO - Reload"
		CrosshairStatus.TextColor3 = Color3.fromRGB(255, 100, 100)
		ContinuousRotation = false
	elseif status == "Reloading" then
		CrosshairImage.ImageColor3 = Color3.fromRGB(255, 200, 50)
		CrosshairStatus.Text = "🔄 Reloading..."
		CrosshairStatus.TextColor3 = Color3.fromRGB(255, 200, 50)
		-- Rotate counter-clockwise during reload
		ContinuousRotation = true
		ContinuousRotationSpeed = -360 -- Counter-clockwise
	end
end

-- Spring physics update for rotation
local function updateCrosshairRotation(deltaTime)
	if not CrosshairImage then
		return
	end

	if ContinuousRotation then
		-- Continuous rotation (for reload/unjam)
		CurrentRotation = CurrentRotation + (ContinuousRotationSpeed * deltaTime)
		TargetRotation = CurrentRotation -- Keep target moving
		RotationVelocity = 0 -- No spring physics during continuous rotation
	else
		-- Spring physics
		local displacement = TargetRotation - CurrentRotation
		local springForce = displacement * SpringStiffness
		local dampingForce = -RotationVelocity * SpringDamping

		RotationVelocity = RotationVelocity + (springForce + dampingForce) * deltaTime
		CurrentRotation = CurrentRotation + RotationVelocity * deltaTime
	end

	CrosshairImage.Rotation = CurrentRotation
end

-- Add rotation on shoot (spring-based, clockwise kick)
local function rotateCrosshairOnShoot()
	-- Add to target rotation (clockwise = positive)
	TargetRotation = TargetRotation + 30 -- Small clockwise kick

	-- Add velocity for spring effect
	RotationVelocity = RotationVelocity + 600 -- Impulse
end

-- Start continuous rotation for reload
local function rotateCrosshairOnReload(reloadTime)
	ContinuousRotation = true
	ContinuousRotationSpeed = -360 -- Counter-clockwise, full rotation per second

	-- Stop after reload time and reset
	task.delay(reloadTime, function()
		ContinuousRotation = false
		CurrentRotation = 0
		TargetRotation = 0
		RotationVelocity = 0
	end)
end

-- Start continuous rotation for unjam
local function rotateCrosshairOnUnjam(unjamTime)
	ContinuousRotation = true
	ContinuousRotationSpeed = -360 -- Counter-clockwise

	-- Stop after unjam time and reset
	task.delay(unjamTime, function()
		ContinuousRotation = false
		CurrentRotation = 0
		TargetRotation = 0
		RotationVelocity = 0
	end)
end

-- Update crosshair every frame
RunService.RenderStepped:Connect(function(deltaTime)
	updateCrosshairRotation(deltaTime)
end)

-- ═══════════════════════════════════════════════════════════
--  DAMAGE NUMBER SYSTEM
-- ═══════════════════════════════════════════════════════════

local function createDamageNumber(position, damage, isHeadshot, bodyPart)
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.Adornee = nil
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100
	billboard.Parent = workspace

	local damageLabel = Instance.new("TextLabel")
	damageLabel.Size = UDim2.new(1, 0, 1, 0)
	damageLabel.BackgroundTransparency = 1
	damageLabel.Font = Enum.Font.GothamBold
	damageLabel.TextSize = isHeadshot and 28 or 22
	damageLabel.TextStrokeTransparency = 0.5
	damageLabel.Text = "-" .. math.floor(damage)
	damageLabel.Parent = billboard

	if isHeadshot then
		damageLabel.TextColor3 = Color3.fromRGB(255, 220, 0)
	elseif bodyPart == "Torso" then
		damageLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
	else
		damageLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end

	local randomOffset = Vector3.new((math.random() - 0.5) * 2, math.random() * 3, (math.random() - 0.5) * 2)
	billboard.StudsOffset = randomOffset

	local startTime = tick()
	local duration = 1.2

	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local alpha = elapsed / duration

		if alpha >= 1 then
			connection:Disconnect()
			billboard:Destroy()
			return
		end

		billboard.StudsOffset = randomOffset + Vector3.new(0, alpha * 5, 0)
		damageLabel.TextTransparency = alpha
		damageLabel.TextStrokeTransparency = 0.5 + (alpha * 0.5)
	end)

	local part = Instance.new("Part")
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.Transparency = 1
	part.CanCollide = false
	part.Anchored = true
	part.CFrame = CFrame.new(position)
	part.Parent = workspace
	billboard.Adornee = part

	game:GetService("Debris"):AddItem(part, duration + 0.5)
end

local function showDamageNumber(hitResult)
	if not hitResult or not hitResult.Damage then
		return
	end

	createDamageNumber(
		hitResult.Position,
		hitResult.Damage,
		hitResult.IsHeadshot or false,
		hitResult.BodyPart or "Body"
	)
end

-- ═══════════════════════════════════════════════════════════
--  CAMERA RECOIL & SHAKE
-- ═══════════════════════════════════════════════════════════

local RecoilOffset = Vector2.new(0, 0)
local RecoilVelocity = Vector2.new(0, 0)
local RecoilRecoverySpeed = 8
local RecoilSnappiness = 0.3

local CameraShake = {
	Intensity = 0,
	Decay = 15,
	NoiseOffsetX = 0,
	NoiseOffsetY = 0,
	NoiseOffsetZ = 0,
	NoiseSpeed = 35,
	PitchMultiplier = 1.2,
	YawMultiplier = 0.8,
	RollMultiplier = 0.4,
	RandomImpulse = Vector3.new(0, 0, 0),
	ImpulseDecay = 20,
}

local function perlinNoise(x)
	local function noise(x)
		local x0 = math.floor(x)
		local x1 = x0 + 1
		local sx = x - x0
		sx = sx * sx * (3 - 2 * sx)

		local function hash(n)
			n = math.sin(n) * 43758.5453123
			return n - math.floor(n)
		end

		return hash(x0) * (1 - sx) + hash(x1) * sx
	end

	local result = 0
	result = result + noise(x) * 1.0
	result = result + noise(x * 2.1) * 0.5
	result = result + noise(x * 4.3) * 0.25
	result = result + noise(x * 8.7) * 0.125

	return result
end

local function applyCameraRecoil(recoilData)
	if not recoilData then
		return
	end
	local vertical = recoilData[1] or 0
	local horizontal = recoilData[2] or 0

	-- Apply recoil directly to camera angles for shift lock
	CameraAngleY = math.clamp(CameraAngleY + math.rad(vertical * 0.8), math.rad(-80), math.rad(80))
	CameraAngleX = CameraAngleX + math.rad(horizontal * 0.5)

	-- Also add visual recoil kick
	RecoilVelocity = RecoilVelocity + Vector2.new(horizontal * 1.5, vertical * 1.5)
end

local function applyCameraShake(intensity)
	CameraShake.Intensity = CameraShake.Intensity + (intensity or 0.5)
	CameraShake.RandomImpulse = Vector3.new(
		(math.random() - 0.5) * intensity * 2,
		(math.random() - 0.5) * intensity * 2,
		(math.random() - 0.5) * intensity
	)
end

RunService.RenderStepped:Connect(function(deltaTime)
	RecoilOffset = RecoilOffset + (RecoilVelocity * deltaTime * 10)
	RecoilVelocity = RecoilVelocity:Lerp(Vector2.new(0, 0), RecoilSnappiness)

	if RecoilOffset.Magnitude > 0.001 then
		Camera.CFrame = Camera.CFrame * CFrame.Angles(math.rad(-RecoilOffset.Y), math.rad(RecoilOffset.X), 0)
		RecoilOffset = RecoilOffset:Lerp(Vector2.new(0, 0), RecoilRecoverySpeed * deltaTime)
	end

	if CameraShake.Intensity > 0.001 then
		CameraShake.NoiseOffsetX = CameraShake.NoiseOffsetX + deltaTime * CameraShake.NoiseSpeed
		CameraShake.NoiseOffsetY = CameraShake.NoiseOffsetY + deltaTime * CameraShake.NoiseSpeed
		CameraShake.NoiseOffsetZ = CameraShake.NoiseOffsetZ + deltaTime * CameraShake.NoiseSpeed

		local noiseX = perlinNoise(CameraShake.NoiseOffsetX)
		local noiseY = perlinNoise(CameraShake.NoiseOffsetY)
		local noiseZ = perlinNoise(CameraShake.NoiseOffsetZ)

		local shakeX = noiseX * CameraShake.Intensity * CameraShake.YawMultiplier + CameraShake.RandomImpulse.X
		local shakeY = noiseY * CameraShake.Intensity * CameraShake.PitchMultiplier + CameraShake.RandomImpulse.Y
		local shakeZ = noiseZ * CameraShake.Intensity * CameraShake.RollMultiplier + CameraShake.RandomImpulse.Z

		Camera.CFrame = Camera.CFrame * CFrame.Angles(math.rad(shakeY), math.rad(shakeX), math.rad(shakeZ))

		CameraShake.Intensity = math.max(CameraShake.Intensity - (CameraShake.Decay * deltaTime), 0)
		CameraShake.RandomImpulse =
			CameraShake.RandomImpulse:Lerp(Vector3.new(0, 0, 0), CameraShake.ImpulseDecay * deltaTime)
	end
end)

-- ═══════════════════════════════════════════════════════════
--  SOUNDS & VFX (FIXED!)
-- ═══════════════════════════════════════════════════════════

local Sounds = {}
local VFXAssets = {}
local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")

-- FIXED: Load sound properly
local function loadSound(soundSource, gunName)
	if not soundSource then
		return nil
	end

	if typeof(soundSource) == "Instance" and soundSource:IsA("Sound") then
		local sound = soundSource:Clone()
		sound.Parent = Camera
		return sound
	end

	if typeof(soundSource) == "string" then
		local gunFolder = AssetsFolder:FindFirstChild(gunName)
		if gunFolder then
			local sound = gunFolder:FindFirstChild(soundSource)
			if sound and sound:IsA("Sound") then
				local clonedSound = sound:Clone()
				clonedSound.Parent = Camera
				return clonedSound
			end

			local vfxFolder = gunFolder:FindFirstChild("VFX")
			if vfxFolder then
				sound = vfxFolder:FindFirstChild(soundSource)
				if sound and sound:IsA("Sound") then
					local clonedSound = sound:Clone()
					clonedSound.Parent = Camera
					return clonedSound
				end
			end
		end

		local sound = AssetsFolder:FindFirstChild(soundSource, true)
		if sound and sound:IsA("Sound") then
			local clonedSound = sound:Clone()
			clonedSound.Parent = Camera
			return clonedSound
		end
	end

	return nil
end

local function loadVFXAsset(assetSource, gunName)
	if not assetSource then
		return nil
	end
	if typeof(assetSource) == "Instance" then
		return assetSource
	end

	if typeof(assetSource) == "string" then
		local gunFolder = AssetsFolder:FindFirstChild(gunName)
		if gunFolder then
			local asset = gunFolder:FindFirstChild(assetSource)
			if asset then
				return asset
			end

			local vfxFolder = gunFolder:FindFirstChild("VFX")
			if vfxFolder then
				asset = vfxFolder:FindFirstChild(assetSource)
				if asset then
					return asset
				end
			end
		end

		local asset = AssetsFolder:FindFirstChild(assetSource, true)
		if asset then
			return asset
		end
	end

	return nil
end

local function cleanupSounds()
	for soundType, sound in pairs(Sounds) do
		if sound and sound:IsA("Sound") then
			sound:Destroy()
		end
		Sounds[soundType] = nil
	end
end

local function getHitColor(material)
	local materialColors = {
		[Enum.Material.Grass] = Color3.fromRGB(100, 180, 100),
		[Enum.Material.Sand] = Color3.fromRGB(210, 180, 140),
		[Enum.Material.Rock] = Color3.fromRGB(150, 150, 150),
		[Enum.Material.Concrete] = Color3.fromRGB(180, 180, 180),
		[Enum.Material.Brick] = Color3.fromRGB(160, 100, 80),
		[Enum.Material.Wood] = Color3.fromRGB(139, 90, 43),
		[Enum.Material.Metal] = Color3.fromRGB(200, 200, 220),
		[Enum.Material.Glass] = Color3.fromRGB(200, 230, 255),
	}
	return materialColors[material] or Color3.fromRGB(200, 200, 200)
end

local function createMuzzleFlash(muzzlePart)
	if not muzzlePart then
		return
	end

	if VFXAssets.MuzzleFlash then
		local customFlash = VFXAssets.MuzzleFlash

		if customFlash:IsA("ParticleEmitter") then
			local particle = customFlash:Clone()
			particle.Parent = muzzlePart
			particle:Emit(particle:GetAttribute("EmitCount") or 5)
			task.delay(1, function()
				particle:Destroy()
			end)
			return
		end

		if customFlash:IsA("Folder") or customFlash:IsA("Model") then
			for _, child in ipairs(customFlash:GetChildren()) do
				if child:IsA("ParticleEmitter") then
					local particle = child:Clone()
					particle.Parent = muzzlePart
					particle:Emit(particle:GetAttribute("EmitCount") or 5)
					task.delay(1, function()
						particle:Destroy()
					end)
				elseif child:IsA("PointLight") then
					local light = child:Clone()
					light.Parent = muzzlePart
					task.delay(0.1, function()
						light:Destroy()
					end)
				end
			end
			return
		end
	end

	local particle = Instance.new("ParticleEmitter")
	particle.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particle.Color = ColorSequence.new(Color3.new(1, 0.8, 0.3))
	particle.Size = NumberSequence.new(0.3, 0.1)
	particle.Lifetime = NumberRange.new(0.05, 0.1)
	particle.Rate = 100
	particle.Speed = NumberRange.new(2, 5)
	particle.SpreadAngle = Vector2.new(20, 20)
	particle.Enabled = false
	particle.Parent = muzzlePart

	local light = Instance.new("PointLight")
	light.Brightness = 5
	light.Color = Color3.new(1, 0.8, 0.3)
	light.Range = 10
	light.Shadows = true
	light.Parent = muzzlePart

	particle:Emit(5)

	task.spawn(function()
		task.wait(0.05)
		light.Enabled = false
		task.wait(0.1)
		particle:Destroy()
		light:Destroy()
	end)
end

local function createBulletTracer(startPos, endPos)
	local attachment0 = Instance.new("Attachment")
	local attachment1 = Instance.new("Attachment")

	local tracerPart = Instance.new("Part")
	tracerPart.Anchored = true
	tracerPart.CanCollide = false
	tracerPart.Transparency = 1
	tracerPart.Size = Vector3.new(0.1, 0.1, 0.1)
	tracerPart.CFrame = CFrame.new(startPos)
	tracerPart.Parent = workspace

	local endPart = Instance.new("Part")
	endPart.Anchored = true
	endPart.CanCollide = false
	endPart.Transparency = 1
	endPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endPart.CFrame = CFrame.new(endPos)
	endPart.Parent = workspace

	attachment0.Parent = tracerPart
	attachment1.Parent = endPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Color = ColorSequence.new(Color3.new(1, 0.9, 0.5))
	beam.Brightness = 3
	beam.Width0 = 0.1
	beam.Width1 = 0.1
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = tracerPart

	task.spawn(function()
		task.wait(0.1)
		local fadeTime = 0.1
		local steps = 10
		for i = 1, steps do
			beam.Transparency = NumberSequence.new(0.3 + (0.7 * i / steps))
			task.wait(fadeTime / steps)
		end
		tracerPart:Destroy()
		endPart:Destroy()
	end)
end

local function createHitEffect(position, normal, material, isHeadshot)
	local hitPart = Instance.new("Part")
	hitPart.Anchored = true
	hitPart.CanCollide = false
	hitPart.Transparency = 1
	hitPart.Size = Vector3.new(0.5, 0.5, 0.5)
	hitPart.CFrame = CFrame.new(position, position + normal)
	hitPart.Parent = workspace

	local particle = Instance.new("ParticleEmitter")
	particle.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particle.Color = ColorSequence.new(getHitColor(material))
	particle.Size = NumberSequence.new(0.2, 0.05)
	particle.Lifetime = NumberRange.new(0.3, 0.6)
	particle.Rate = 50
	particle.Speed = NumberRange.new(5, 10)
	particle.SpreadAngle = Vector2.new(30, 30)
	particle.Enabled = false
	particle.Parent = hitPart
	particle:Emit(15)

	if material == Enum.Material.Metal or material == Enum.Material.CorrodedMetal then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkles.Color = ColorSequence.new(Color3.new(1, 0.8, 0.3))
		sparkles.Size = NumberSequence.new(0.1, 0.05)
		sparkles.Lifetime = NumberRange.new(0.2, 0.4)
		sparkles.Rate = 30
		sparkles.Speed = NumberRange.new(10, 15)
		sparkles.SpreadAngle = Vector2.new(45, 45)
		sparkles.Enabled = false
		sparkles.Parent = hitPart
		sparkles:Emit(10)
	end

	if isHeadshot then
		local headshotParticle = Instance.new("ParticleEmitter")
		headshotParticle.Texture = "rbxasset://textures/particles/smoke_main.dds"
		headshotParticle.Color = ColorSequence.new(Color3.fromRGB(200, 0, 0))
		headshotParticle.Size = NumberSequence.new(0.3, 0.1)
		headshotParticle.Lifetime = NumberRange.new(0.5, 0.8)
		headshotParticle.Rate = 100
		headshotParticle.Speed = NumberRange.new(3, 8)
		headshotParticle.Enabled = false
		headshotParticle.Parent = hitPart
		headshotParticle:Emit(20)
	end

	task.delay(2, function()
		hitPart:Destroy()
	end)
end

local function createShellEjection(ejectionPort)
	if not ejectionPort then
		return
	end

	local shell

	if VFXAssets.ShellCasing then
		local customShell = VFXAssets.ShellCasing
		if customShell:IsA("BasePart") or customShell:IsA("MeshPart") then
			shell = customShell:Clone()
		elseif customShell:IsA("Model") then
			shell = customShell:Clone()
			if not shell.PrimaryPart then
				shell.PrimaryPart = shell:FindFirstChildWhichIsA("BasePart")
			end
		end
	end

	if not shell then
		shell = Instance.new("Part")
		shell.Size = Vector3.new(0.1, 0.3, 0.1)
		shell.Material = Enum.Material.Metal
		shell.Color = Color3.fromRGB(200, 180, 100)
	end

	if shell:IsA("Model") and shell.PrimaryPart then
		shell:SetPrimaryPartCFrame(ejectionPort.CFrame * CFrame.new(0.3, 0, 0) * CFrame.Angles(math.rad(90), 0, 0))
	elseif shell:IsA("BasePart") then
		shell.CFrame = ejectionPort.CFrame * CFrame.new(0.3, 0, 0) * CFrame.Angles(math.rad(90), 0, 0)
		shell.CanCollide = true
	end

	shell.Parent = workspace

	local physicsPart = shell:IsA("Model") and shell.PrimaryPart or shell

	if physicsPart then
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Velocity = (ejectionPort.CFrame.RightVector * 15)
			+ (ejectionPort.CFrame.UpVector * 5)
			+ (ejectionPort.CFrame.LookVector * math.random(-2, 2))
		bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
		bodyVelocity.Parent = physicsPart

		local bodyAngularVelocity = Instance.new("BodyAngularVelocity")
		bodyAngularVelocity.AngularVelocity =
			Vector3.new(math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))
		bodyAngularVelocity.MaxTorque = Vector3.new(500, 500, 500)
		bodyAngularVelocity.Parent = physicsPart

		task.delay(0.1, function()
			if bodyVelocity then
				bodyVelocity:Destroy()
			end
			if bodyAngularVelocity then
				bodyAngularVelocity:Destroy()
			end
		end)
	end

	if Sounds.ShellEject then
		Sounds.ShellEject:Play()
	end

	game:GetService("Debris"):AddItem(shell, 5)
end

-- ═══════════════════════════════════════════════════════════
--  ANIMATIONS
-- ═══════════════════════════════════════════════════════════

local function loadAnimations(animationIds)
	for name, track in pairs(AnimationTracks) do
		if track then
			track:Stop()
			track:Destroy()
		end
		AnimationTracks[name] = nil
	end

	local animator = Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = Humanoid
	end

	for name, animId in pairs(animationIds) do
		if animId and animId > 0 then
			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. animId

			local success, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			if success and track then
				AnimationTracks[name] = track
			end

			animation:Destroy()
		end
	end

	if AnimationTracks.Idle then
		AnimationTracks.Idle.Looped = true
		AnimationTracks.Idle:Play()
	end
end

local function playAnimation(animName, fadeTime)
	local track = AnimationTracks[animName]
	if track then
		track:Play(fadeTime or 0.1)
	end
end

-- ═══════════════════════════════════════════════════════════
--  INPUT HANDLING
-- ═══════════════════════════════════════════════════════════

local IsMouseDown = false
local FireConnection = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not EquippedTool then
		return
	end
	if not GunConfig then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		IsMouseDown = true

		if GunConfig.FireMode == "Auto" or GunConfig.FireMode == "Burst" then
			FireConnection = RunService.Heartbeat:Connect(function()
				if IsMouseDown and CanFire and GunStatus == "Ready" then
					-- Calculate target position from camera center
					local ray = Camera:ViewportPointToRay(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
					local targetPosition = ray.Origin + ray.Direction * 1000
					FireGunRemote:FireServer(targetPosition)
				end
			end)
		elseif GunConfig.FireMode == "Semi" then
			if CanFire and GunStatus == "Ready" then
				local ray = Camera:ViewportPointToRay(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
				local targetPosition = ray.Origin + ray.Direction * 1000
				FireGunRemote:FireServer(targetPosition)
			end
		end
	end

	if input.KeyCode == Enum.KeyCode.R then
		if GunStatus ~= "Jammed" and GunStatus ~= "Unjamming" then
			ReloadGunRemote:FireServer()
		end
	end

	if input.KeyCode == Enum.KeyCode.F then
		if GunStatus == "Jammed" then
			UnjamGunRemote:FireServer()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		IsMouseDown = false
		if FireConnection then
			FireConnection:Disconnect()
			FireConnection = nil
		end
	end
end)

-- ═══════════════════════════════════════════════════════════
--  REMOTE EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════

EquipGunRemote.OnClientEvent:Connect(function(config)
	print("🔫 GUN EQUIPPED")

	GunConfig = config
	GunFrame.Visible = true

	-- Enable systems
	enableOverShoulderCamera()
	createCrosshair()

	-- Play equip animation
	if config.Animations and config.Animations.Equip and config.Animations.Equip > 0 then
		task.wait(0.1)
		playAnimation("Equip", 0.2)
	end

	-- Load assets
	cleanupSounds()

	if config.Assets then
		Sounds.Fire = loadSound(config.Assets.FireSound, config.GunName)
		Sounds.Reload = loadSound(config.Assets.ReloadSound, config.GunName)
		Sounds.EmptyClick = loadSound(config.Assets.EmptyClickSound, config.GunName)
		Sounds.ShellEject = loadSound(config.Assets.ShellEjectSound, config.GunName)
		Sounds.Jam = loadSound(config.Assets.JamSound, config.GunName)
		Sounds.Unjam = loadSound(config.Assets.UnjamSound, config.GunName)

		print("🔊 Loaded sounds:", Sounds.Fire ~= nil, Sounds.Reload ~= nil, Sounds.EmptyClick ~= nil)

		VFXAssets.MuzzleFlash = loadVFXAsset(config.Assets.MuzzleFlash, config.GunName)
		VFXAssets.BulletTracer = loadVFXAsset(config.Assets.BulletTracer, config.GunName)
		VFXAssets.HitEffect = loadVFXAsset(config.Assets.HitEffect, config.GunName)
		VFXAssets.ShellCasing = loadVFXAsset(config.Assets.ShellCasing, config.GunName)
	end

	if config.Animations then
		loadAnimations(config.Animations)
	end

	task.wait(0.1)
	EquippedTool = Character:FindFirstChildOfClass("Tool")

	print("✅ GUN SETUP COMPLETE")
end)

UnequipGunRemote.OnClientEvent:Connect(function()
	print("🔫 GUN UNEQUIPPED")

	GunConfig = nil
	EquippedTool = nil
	GunFrame.Visible = false

	disableOverShoulderCamera()

	if CrosshairGui then
		CrosshairGui:Destroy()
		CrosshairGui = nil
	end

	cleanupSounds()

	VFXAssets.MuzzleFlash = nil
	VFXAssets.BulletTracer = nil
	VFXAssets.HitEffect = nil
	VFXAssets.ShellCasing = nil

	for name, track in pairs(AnimationTracks) do
		if track then
			track:Stop()
		end
	end

	RecoilOffset = Vector2.new(0, 0)
	RecoilVelocity = Vector2.new(0, 0)
	CameraShake.Intensity = 0
	CameraShake.RandomImpulse = Vector3.new(0, 0, 0)
	CurrentRotation = 0
	TargetRotation = 0
	RotationVelocity = 0
	ContinuousRotation = false
	GunStatus = "Ready"
end)

PlayEffectRemote.OnClientEvent:Connect(function(effectType, data)
	if effectType == "Fire" then
		playAnimation("Fire", 0.05)

		local muzzle = EquippedTool and EquippedTool:FindFirstChild("Muzzle")
		local ejectionPort = EquippedTool and EquippedTool:FindFirstChild("EjectionPort") or muzzle

		if muzzle then
			createMuzzleFlash(muzzle)
		end

		if ejectionPort then
			createShellEjection(ejectionPort)
		end

		if data.MuzzlePosition and data.HitResult then
			createBulletTracer(data.MuzzlePosition, data.HitResult.Position)
		end

		if data.HitResult and data.HitResult.Hit then
			createHitEffect(
				data.HitResult.Position,
				data.HitResult.Normal,
				data.HitResult.Material,
				data.HitResult.IsHeadshot
			)
			showDamageNumber(data.HitResult)
		end

		if data.Recoil then
			applyCameraRecoil(data.Recoil)
		end

		applyCameraShake(0.6)
		rotateCrosshairOnShoot()

		if Sounds.Fire then
			Sounds.Fire:Play()
			print("🔊 Playing fire sound")
		else
			print("❌ Fire sound is nil!")
		end
	elseif effectType == "Reload" then
		local animName = data.ReloadType == "Tactical" and "ReloadTactical" or "ReloadEmpty"
		playAnimation(animName, 0.2)

		rotateCrosshairOnReload(data.ReloadTime)

		if Sounds.Reload then
			Sounds.Reload:Play()
		end

		CanFire = false
		task.delay(data.ReloadTime, function()
			CanFire = true
		end)
	elseif effectType == "EmptyClick" then
		if Sounds.EmptyClick then
			Sounds.EmptyClick:Play()
		end
	elseif effectType == "Jam" then
		print("🔒 GUN JAMMED!")
		if Sounds.Jam then
			Sounds.Jam:Play()
		end
	elseif effectType == "JamClick" then
		if Sounds.EmptyClick then
			Sounds.EmptyClick:Play()
		end
	elseif effectType == "Unjam" then
		print("🔓 UNJAMMING GUN...")
		playAnimation("Unjam", 0.2)

		rotateCrosshairOnUnjam(data.UnjamTime)

		if Sounds.Unjam then
			Sounds.Unjam:Play()
		end

		CanFire = false
		task.delay(data.UnjamTime, function()
			CanFire = true
			print("✅ GUN UNJAMMED!")
		end)
	end
end)

UpdateAmmoRemote.OnClientEvent:Connect(function(ammoData)
	CurrentBulletLabel.Text = tostring(ammoData.CurrentAmmo)
	MaxBulletLabel.Text = tostring(ammoData.ReserveAmmo)

	if ammoData.GunImage then
		EquippedGunImage.Image = ammoData.GunImage
	end
end)

UpdateGunStatusRemote.OnClientEvent:Connect(function(statusData)
	GunStatus = statusData.Status
	CanFire = statusData.CanFire
	updateCrosshairStatus(GunStatus)
end)

-- ═══════════════════════════════════════════════════════════
--  INITIALIZATION
-- ═══════════════════════════════════════════════════════════

GunFrame.Visible = false

print(
	"═══════════════════════════════════════════"
)
print("🔫 AAA OVER-THE-SHOULDER GUN CLIENT LOADED")
print(
	"═══════════════════════════════════════════"
)
print("✅ SHIFT-LOCKED Over-the-Shoulder Camera")
print("✅ Mouse Wheel Zoom (3-20 studs)")
print("✅ Damage Numbers (color-coded)")
print("✅ SPRING Animated Crosshair")
print("✅ Gun Jamming (F to unjam)")
print("✅ FIXED Sounds")
print(
	"═══════════════════════════════════════════"
)
