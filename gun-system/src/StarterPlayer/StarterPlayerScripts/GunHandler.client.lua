--[[
	Gun Client Handler - AAA REALISTIC CAMERA + CHARACTER ROTATION
	Place in StarterPlayer > StarterPlayerScripts
	
	IMPROVEMENTS:
	✅ Character body rotates to face where you're aiming (like PUBG, Fortnite)
	✅ Enhanced AAA-style camera shake with Perlin noise
	✅ Smooth character turning with interpolation
	
	Handles all client-side effects:
	- Character rotation toward mouse
	- Muzzle flash
	- Bullet tracers
	- Hit effects
	- Shell ejection
	- REALISTIC CAMERA SHAKE & RECOIL
	- Sounds
	- Animations
	- UI updates
]]

-- ═══════════════════════════════════════════════════════════
--  DEBUG MODE
-- ═══════════════════════════════════════════════════════════
local DEBUG = true -- Set to false to disable debug logging

local function debugLog(category, ...)
	if not DEBUG then
		return
	end

	local prefix = {
		["INFO"] = "ℹ️",
		["SUCCESS"] = "✅",
		["ERROR"] = "❌",
		["WARNING"] = "⚠️",
		["LOAD"] = "📦",
		["SOUND"] = "🔊",
		["VFX"] = "🎆",
		["ANIM"] = "🎬",
		["CONFIG"] = "⚙️",
		["FIRE"] = "🔫",
		["RECOIL"] = "↕️",
		["SHAKE"] = "📳",
		["ROTATION"] = "🔄",
	}

	print(string.format("[GUN DEBUG] %s [%s]", prefix[category] or "📌", category), ...)
end

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

-- UI References
local PlayerGui = Player:WaitForChild("PlayerGui")
local MainUI = PlayerGui:WaitForChild("MainUI")
local GunFrame = MainUI:WaitForChild("GunFrame")
local EquippedGunImage = GunFrame:WaitForChild("EquippedGun")
local CurrentBulletLabel = GunFrame:WaitForChild("CurrentBullet")
local MaxBulletLabel = GunFrame:WaitForChild("MaxBullet")

-- Gun state
local CurrentGun = nil
local GunConfig = nil
local EquippedTool = nil
local IsAiming = false
local CanFire = true

-- Animation tracks
local AnimationTracks = {
	Idle = nil,
	Walk = nil,
	Fire = nil,
	ReloadTactical = nil,
	ReloadEmpty = nil,
}

-- ═══════════════════════════════════════════════════════════
--  AAA CAMERA RECOIL & SHAKE SYSTEM
-- ═══════════════════════════════════════════════════════════

-- Camera recoil - AAA REALISTIC SYSTEM
local RecoilOffset = Vector2.new(0, 0) -- Current recoil offset (pitch, yaw)
local RecoilVelocity = Vector2.new(0, 0) -- Recoil velocity for snappier feel
local RecoilRecoverySpeed = 8 -- How fast recoil recovers (lower = slower)
local RecoilSnappiness = 0.3 -- How snappy the initial kick is (0-1, higher = snappier)

-- Enhanced Camera shake system with Perlin noise
local CameraShake = {
	-- Shake intensity
	Intensity = 0,
	Decay = 15, -- How fast shake decays

	-- Perlin noise parameters for natural shake
	NoiseOffsetX = 0,
	NoiseOffsetY = 0,
	NoiseOffsetZ = 0,
	NoiseSpeed = 35, -- How fast the noise moves (higher = more erratic)

	-- Shake amplitude multipliers
	PitchMultiplier = 1.2, -- Up/down shake
	YawMultiplier = 0.8, -- Left/right shake
	RollMultiplier = 0.4, -- Tilt shake (subtle)

	-- Random impulses for variety
	RandomImpulse = Vector3.new(0, 0, 0),
	ImpulseDecay = 20,
}

-- Character rotation settings
local RotateToMouse = true -- Should character rotate to face mouse when firing
local InstantRotation = true -- Snap instantly instead of smooth lerp
local RotationSpeed = 18 -- How fast character rotates if using smooth (ignored if InstantRotation = true)
local RotationSmoothness = 0.4 -- Smoothing factor (0-1, lower = smoother)
local IsFiring = false -- Track if currently firing
local LastRotationTarget = nil -- Store target rotation

-- Enhanced Perlin-like noise with multiple octaves
local function perlinNoise(x)
	local function noise(x)
		local x0 = math.floor(x)
		local x1 = x0 + 1
		local sx = x - x0

		-- Smooth interpolation
		sx = sx * sx * (3 - 2 * sx)

		-- Random hash function
		local function hash(n)
			n = math.sin(n) * 43758.5453123
			return n - math.floor(n)
		end

		return hash(x0) * (1 - sx) + hash(x1) * sx
	end

	-- Multiple octaves for natural movement
	local result = 0
	result = result + noise(x) * 1.0
	result = result + noise(x * 2.1) * 0.5
	result = result + noise(x * 4.3) * 0.25
	result = result + noise(x * 8.7) * 0.125

	return result
end

-- Sounds (loaded from gun config)
local Sounds = {
	Fire = nil,
	Reload = nil,
	EmptyClick = nil,
	ShellEject = nil,
}

-- VFX Assets (loaded from gun config)
local VFXAssets = {
	MuzzleFlash = nil,
	BulletTracer = nil,
	HitEffect = nil,
	ShellCasing = nil,
}

-- Asset folder path
local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")

-- ═══════════════════════════════════════════════════════════
--  UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════

-- Load sound from config or asset path
local function loadSound(soundSource, gunName)
	debugLog("SOUND", "Attempting to load sound:", soundSource, "for gun:", gunName)

	if not soundSource then
		debugLog("WARNING", "Sound source is nil")
		return nil
	end

	-- If it's already a Sound instance, clone it
	if typeof(soundSource) == "Instance" and soundSource:IsA("Sound") then
		local sound = soundSource:Clone()
		sound.Parent = Camera
		debugLog("SUCCESS", "Loaded direct Sound instance:", soundSource.Name)
		debugLog("INFO", "  └─ SoundId:", sound.SoundId)
		debugLog("INFO", "  └─ Volume:", sound.Volume)
		return sound
	end

	-- If it's a string path, try to load from Assets folder
	if typeof(soundSource) == "string" then
		debugLog("LOAD", "Searching for sound:", soundSource)

		-- Try loading from ReplicatedStorage > Assets > [GunName] > [SoundName]
		local gunFolder = AssetsFolder:FindFirstChild(gunName)
		if gunFolder then
			debugLog("INFO", "Found gun folder:", gunName)

			local sound = gunFolder:FindFirstChild(soundSource)
			if sound and sound:IsA("Sound") then
				local clonedSound = sound:Clone()
				clonedSound.Parent = Camera
				debugLog("SUCCESS", "Loaded sound from:", gunName .. "/" .. soundSource)
				return clonedSound
			end

			-- Try in VFX subfolder
			local vfxFolder = gunFolder:FindFirstChild("VFX")
			if vfxFolder then
				sound = vfxFolder:FindFirstChild(soundSource)
				if sound and sound:IsA("Sound") then
					local clonedSound = sound:Clone()
					clonedSound.Parent = Camera
					debugLog("SUCCESS", "Loaded sound from:", gunName .. "/VFX/" .. soundSource)
					return clonedSound
				end
			end
		end

		-- Try direct path (recursive search)
		local sound = AssetsFolder:FindFirstChild(soundSource, true)
		if sound and sound:IsA("Sound") then
			local clonedSound = sound:Clone()
			clonedSound.Parent = Camera
			debugLog("SUCCESS", "Found sound via recursive search")
			return clonedSound
		end

		debugLog("ERROR", "Sound not found anywhere:", soundSource)
	end

	return nil
end

-- Load VFX asset (ParticleEmitter, Beam, etc)
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

-- Clean up old sounds
local function cleanupSounds()
	for soundType, sound in pairs(Sounds) do
		if sound and sound:IsA("Sound") then
			sound:Destroy()
		end
		Sounds[soundType] = nil
	end
end

-- Get material-based hit color
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

-- ═══════════════════════════════════════════════════════════
--  VISUAL EFFECTS
-- ═══════════════════════════════════════════════════════════

-- Create muzzle flash effect
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

	-- Default muzzle flash
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

-- Create bullet tracer
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
	beam.Brightness = 0
	beam.Width0 = 0
	beam.Width1 = 0
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(1, 1)
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

-- Create hit effect
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

-- Create shell ejection
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
--  AAA CAMERA RECOIL & SHAKE SYSTEM
-- ═══════════════════════════════════════════════════════════

-- Apply camera recoil
local function applyCameraRecoil(recoilData)
	if not recoilData then
		return
	end

	local vertical = recoilData[1] or 0
	local horizontal = recoilData[2] or 0

	-- Add velocity for snappy kick
	RecoilVelocity = RecoilVelocity + Vector2.new(horizontal * 2, vertical * 2)

	debugLog("RECOIL", string.format("🎯 RECOIL KICK - V: %.2f, H: %.2f", vertical, horizontal))
end

-- Apply enhanced AAA-style camera shake with Perlin noise
local function applyCameraShake(intensity)
	CameraShake.Intensity = CameraShake.Intensity + (intensity or 0.5)

	-- Add random impulse for variety
	CameraShake.RandomImpulse = Vector3.new(
		(math.random() - 0.5) * intensity * 2,
		(math.random() - 0.5) * intensity * 2,
		(math.random() - 0.5) * intensity
	)

	debugLog("SHAKE", string.format("📳 Camera Shake - Intensity: %.2f", intensity or 0.5))
end

-- Update camera with recoil & enhanced shake
RunService.RenderStepped:Connect(function(deltaTime)
	-- ═══════════════════════════════════════════════════════════
	--  RECOIL SYSTEM
	-- ═══════════════════════════════════════════════════════════

	RecoilOffset = RecoilOffset + (RecoilVelocity * deltaTime * 10)
	RecoilVelocity = RecoilVelocity:Lerp(Vector2.new(0, 0), RecoilSnappiness)

	if RecoilOffset.Magnitude > 0.001 then
		Camera.CFrame = Camera.CFrame
			* CFrame.Angles(
				math.rad(-RecoilOffset.Y), -- Vertical
				math.rad(RecoilOffset.X), -- Horizontal
				0
			)
		RecoilOffset = RecoilOffset:Lerp(Vector2.new(0, 0), RecoilRecoverySpeed * deltaTime)
	end

	-- ═══════════════════════════════════════════════════════════
	--  ENHANCED CAMERA SHAKE with Perlin Noise
	-- ═══════════════════════════════════════════════════════════

	if CameraShake.Intensity > 0.001 then
		-- Update noise offsets
		CameraShake.NoiseOffsetX = CameraShake.NoiseOffsetX + deltaTime * CameraShake.NoiseSpeed
		CameraShake.NoiseOffsetY = CameraShake.NoiseOffsetY + deltaTime * CameraShake.NoiseSpeed
		CameraShake.NoiseOffsetZ = CameraShake.NoiseOffsetZ + deltaTime * CameraShake.NoiseSpeed

		-- Generate Perlin noise for smooth, natural shake
		local noiseX = perlinNoise(CameraShake.NoiseOffsetX)
		local noiseY = perlinNoise(CameraShake.NoiseOffsetY)
		local noiseZ = perlinNoise(CameraShake.NoiseOffsetZ)

		-- Apply intensity and multipliers
		local shakeX = noiseX * CameraShake.Intensity * CameraShake.YawMultiplier
		local shakeY = noiseY * CameraShake.Intensity * CameraShake.PitchMultiplier
		local shakeZ = noiseZ * CameraShake.Intensity * CameraShake.RollMultiplier

		-- Add random impulse
		shakeX = shakeX + CameraShake.RandomImpulse.X
		shakeY = shakeY + CameraShake.RandomImpulse.Y
		shakeZ = shakeZ + CameraShake.RandomImpulse.Z

		-- Apply shake to camera
		Camera.CFrame = Camera.CFrame
			* CFrame.Angles(
				math.rad(shakeY), -- Pitch
				math.rad(shakeX), -- Yaw
				math.rad(shakeZ) -- Roll
			)

		-- Decay intensity
		CameraShake.Intensity = math.max(CameraShake.Intensity - (CameraShake.Decay * deltaTime), 0)

		-- Decay random impulse
		CameraShake.RandomImpulse =
			CameraShake.RandomImpulse:Lerp(Vector3.new(0, 0, 0), CameraShake.ImpulseDecay * deltaTime)
	end
end)

-- ═══════════════════════════════════════════════════════════
--  CHARACTER ROTATION TO MOUSE (ONLY WHEN FIRING)
-- ═══════════════════════════════════════════════════════════

-- Instantly rotate character to face mouse (called on each shot)
local function rotateCharacterToMouse()
	if not RotateToMouse then
		return
	end

	if not HumanoidRootPart then
		return
	end

	local mouse = Player:GetMouse()
	if not mouse then
		return
	end

	local mouseHit = mouse.Hit.Position
	local rootPos = HumanoidRootPart.Position

	-- Calculate direction (only Y-axis rotation)
	local direction = Vector3.new(mouseHit.X - rootPos.X, 0, mouseHit.Z - rootPos.Z)

	if direction.Magnitude > 0.1 then
		if InstantRotation then
			-- INSTANT SNAP - No lerp, immediate rotation
			local targetCFrame = CFrame.new(rootPos, rootPos + direction)
			HumanoidRootPart.CFrame = targetCFrame

			debugLog("ROTATION", "🎯 INSTANT SNAP to target!")
		else
			-- Store target for smooth rotation
			LastRotationTarget = CFrame.new(rootPos, rootPos + direction)
		end

		local angle = math.deg(math.atan2(direction.X, direction.Z))
		debugLog("ROTATION", string.format("Character rotated to: %.1f°", angle))
	end
end

-- Smooth rotation loop (only if InstantRotation = false)
RunService.RenderStepped:Connect(function(deltaTime)
	if InstantRotation then
		return -- Skip if using instant rotation
	end

	if not RotateToMouse then
		return
	end

	-- ONLY rotate if currently firing AND we have a target
	if not IsFiring or not LastRotationTarget then
		return
	end

	if not EquippedTool or not HumanoidRootPart then
		return
	end

	-- Smooth rotation toward target
	local currentCFrame = HumanoidRootPart.CFrame
	local newCFrame = currentCFrame:Lerp(LastRotationTarget, RotationSpeed * deltaTime * RotationSmoothness)
	HumanoidRootPart.CFrame = newCFrame

	-- Clear target when close enough
	local angle = math.acos(math.clamp(currentCFrame.LookVector:Dot(LastRotationTarget.LookVector), -1, 1))
	if angle < math.rad(2) then -- Within 2 degrees
		LastRotationTarget = nil
		debugLog("ROTATION", "✅ Rotation complete")
	end
end)

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
		IsFiring = true -- Start rotating character

		-- Rotate character immediately on click
		rotateCharacterToMouse()

		if GunConfig.FireMode == "Auto" or GunConfig.FireMode == "Burst" then
			FireConnection = RunService.Heartbeat:Connect(function()
				if IsMouseDown and CanFire then
					local mouse = Player:GetMouse()
					if mouse then
						-- Rotate before each shot in auto mode
						rotateCharacterToMouse()
						FireGunRemote:FireServer(mouse.Hit.Position)
					end
				end
			end)
		elseif GunConfig.FireMode == "Semi" then
			if CanFire then
				local mouse = Player:GetMouse()
				if mouse then
					FireGunRemote:FireServer(mouse.Hit.Position)
				end
			end
		end
	end

	if input.KeyCode == Enum.KeyCode.R then
		ReloadGunRemote:FireServer()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		IsMouseDown = false
		IsFiring = false -- Stop rotating character
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
	debugLog("FIRE", "GUN EQUIP EVENT RECEIVED")

	GunConfig = config
	GunFrame.Visible = true

	cleanupSounds()

	if config.Assets then
		Sounds.Fire = loadSound(config.Assets.FireSound, config.GunName)
		Sounds.Reload = loadSound(config.Assets.ReloadSound, config.GunName)
		Sounds.EmptyClick = loadSound(config.Assets.EmptyClickSound, config.GunName)
		Sounds.ShellEject = loadSound(config.Assets.ShellEjectSound, config.GunName)

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

	debugLog("SUCCESS", "GUN SETUP COMPLETE!")
end)

UnequipGunRemote.OnClientEvent:Connect(function()
	GunConfig = nil
	EquippedTool = nil
	GunFrame.Visible = false

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
		end

		if data.Recoil then
			applyCameraRecoil(data.Recoil)
		end

		-- Enhanced AAA shake
		applyCameraShake(0.6)

		if Sounds.Fire then
			Sounds.Fire:Play()
		end
	elseif effectType == "Reload" then
		local animName = data.ReloadType == "Tactical" and "ReloadTactical" or "ReloadEmpty"
		playAnimation(animName, 0.2)

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
	end
end)

UpdateAmmoRemote.OnClientEvent:Connect(function(ammoData)
	CurrentBulletLabel.Text = tostring(ammoData.CurrentAmmo)
	MaxBulletLabel.Text = tostring(ammoData.ReserveAmmo)

	if ammoData.GunImage then
		EquippedGunImage.Image = ammoData.GunImage
	end
end)

-- ═══════════════════════════════════════════════════════════
--  INITIALIZATION
-- ═══════════════════════════════════════════════════════════

GunFrame.Visible = false

debugLog(
	"SUCCESS",
	"═══════════════════════════════════════════"
)
debugLog("SUCCESS", "GUN CLIENT - CHARACTER ROTATION + AAA SHAKE")
debugLog(
	"SUCCESS",
	"═══════════════════════════════════════════"
)
debugLog("ROTATION", "Character Rotation:", RotateToMouse and "ENABLED ✅" or "DISABLED")
debugLog("ROTATION", "Rotation Speed:", RotationSpeed, "| Smoothness:", RotationSmoothness)
debugLog("SHAKE", "Enhanced Perlin Shake - Decay:", CameraShake.Decay, "| Speed:", CameraShake.NoiseSpeed)
debugLog("RECOIL", "Recoil Recovery:", RecoilRecoverySpeed, "| Snappiness:", RecoilSnappiness)
debugLog(
	"SUCCESS",
	"═══════════════════════════════════════════"
)
