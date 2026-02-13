--[[
	Gun Client Handler
	Place in StarterPlayer > StarterPlayerScripts
	
	Handles all client-side effects:
	- Muzzle flash
	- Bullet tracers
	- Hit effects
	- Shell ejection
	- Camera recoil
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

-- Camera recoil
local RecoilOffset = Vector2.new(0, 0)
local RecoilRecoverySpeed = 10

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
				debugLog("INFO", "  └─ SoundId:", clonedSound.SoundId)
				debugLog("INFO", "  └─ Volume:", clonedSound.Volume)
				debugLog("INFO", "  └─ Path: Assets/" .. gunName .. "/" .. soundSource)
				return clonedSound
			else
				debugLog("INFO", "Sound not found in gun folder, checking VFX subfolder...")
			end

			-- Try in VFX subfolder (for structure: Pistol/VFX/Sound)
			local vfxFolder = gunFolder:FindFirstChild("VFX")
			if vfxFolder then
				debugLog("INFO", "Found VFX subfolder")
				sound = vfxFolder:FindFirstChild(soundSource)
				if sound and sound:IsA("Sound") then
					local clonedSound = sound:Clone()
					clonedSound.Parent = Camera
					debugLog("SUCCESS", "Loaded sound from:", gunName .. "/VFX/" .. soundSource)
					debugLog("INFO", "  └─ SoundId:", clonedSound.SoundId)
					debugLog("INFO", "  └─ Volume:", clonedSound.Volume)
					debugLog("INFO", "  └─ Path: Assets/" .. gunName .. "/VFX/" .. soundSource)
					return clonedSound
				else
					debugLog("WARNING", "Sound not found in VFX folder")
				end
			else
				debugLog("INFO", "No VFX subfolder found in gun folder")
			end
		else
			debugLog("WARNING", "Gun folder not found:", gunName)
			debugLog("INFO", "Available folders in Assets:")
			for _, child in ipairs(AssetsFolder:GetChildren()) do
				debugLog("INFO", "  └─", child.Name, "(" .. child.ClassName .. ")")
			end
		end

		-- Try direct path from Assets folder (recursive search)
		debugLog("INFO", "Attempting recursive search for:", soundSource)
		local sound = AssetsFolder:FindFirstChild(soundSource, true)
		if sound and sound:IsA("Sound") then
			local clonedSound = sound:Clone()
			clonedSound.Parent = Camera
			debugLog("SUCCESS", "Found sound via recursive search")
			debugLog("INFO", "  └─ Full path:", sound:GetFullName())
			debugLog("INFO", "  └─ SoundId:", clonedSound.SoundId)
			return clonedSound
		end

		debugLog("ERROR", "Sound not found anywhere:", soundSource)
	end

	return nil
end

-- Load VFX asset (ParticleEmitter, Beam, etc)
local function loadVFXAsset(assetSource, gunName)
	debugLog("VFX", "Attempting to load VFX:", assetSource, "for gun:", gunName)

	if not assetSource then
		debugLog("INFO", "VFX source is nil (will use default)")
		return nil
	end

	-- If it's already an instance, return it
	if typeof(assetSource) == "Instance" then
		debugLog("SUCCESS", "Using direct VFX instance:", assetSource.Name, "(" .. assetSource.ClassName .. ")")
		return assetSource
	end

	-- If it's a string path, try to load from Assets folder
	if typeof(assetSource) == "string" then
		debugLog("LOAD", "Searching for VFX asset:", assetSource)

		local gunFolder = AssetsFolder:FindFirstChild(gunName)
		if gunFolder then
			debugLog("INFO", "Found gun folder:", gunName)

			-- Try direct in gun folder
			local asset = gunFolder:FindFirstChild(assetSource)
			if asset then
				debugLog("SUCCESS", "Loaded VFX from:", gunName .. "/" .. assetSource)
				debugLog("INFO", "  └─ Type:", asset.ClassName)
				debugLog("INFO", "  └─ Path: Assets/" .. gunName .. "/" .. assetSource)
				if asset:IsA("Folder") then
					debugLog("INFO", "  └─ Children:")
					for _, child in ipairs(asset:GetChildren()) do
						debugLog("INFO", "      └─", child.Name, "(" .. child.ClassName .. ")")
					end
				end
				return asset
			else
				debugLog("INFO", "VFX not found in gun folder, checking VFX subfolder...")
			end

			-- Try in VFX subfolder (for structure: Pistol/VFX/MuzzleFlash)
			local vfxFolder = gunFolder:FindFirstChild("VFX")
			if vfxFolder then
				debugLog("INFO", "Found VFX subfolder")
				asset = vfxFolder:FindFirstChild(assetSource)
				if asset then
					debugLog("SUCCESS", "Loaded VFX from:", gunName .. "/VFX/" .. assetSource)
					debugLog("INFO", "  └─ Type:", asset.ClassName)
					debugLog("INFO", "  └─ Path: Assets/" .. gunName .. "/VFX/" .. assetSource)
					if asset:IsA("Folder") then
						debugLog("INFO", "  └─ Children:")
						for _, child in ipairs(asset:GetChildren()) do
							debugLog("INFO", "      └─", child.Name, "(" .. child.ClassName .. ")")
						end
					end
					return asset
				else
					debugLog("WARNING", "VFX not found in VFX folder")
					debugLog("INFO", "Available assets in VFX folder:")
					for _, child in ipairs(vfxFolder:GetChildren()) do
						debugLog("INFO", "  └─", child.Name, "(" .. child.ClassName .. ")")
					end
				end
			else
				debugLog("INFO", "No VFX subfolder found in gun folder")
			end
		else
			debugLog("WARNING", "Gun folder not found:", gunName)
		end

		-- Try direct path (recursive search)
		debugLog("INFO", "Attempting recursive search for:", assetSource)
		local asset = AssetsFolder:FindFirstChild(assetSource, true)
		if asset then
			debugLog("SUCCESS", "Found VFX via recursive search")
			debugLog("INFO", "  └─ Full path:", asset:GetFullName())
			debugLog("INFO", "  └─ Type:", asset.ClassName)
			return asset
		end

		debugLog("ERROR", "VFX asset not found anywhere:", assetSource)
		debugLog("INFO", "Will use default VFX instead")
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

-- Get hit particle based on material
local function getHitParticle(material)
	if material == Enum.Material.Grass or material == Enum.Material.LeafyGrass then
		return "Smoke"
	elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then
		return "Smoke"
	elseif material == Enum.Material.Metal or material == Enum.Material.CorrodedMetal then
		return "Sparkles"
	elseif material == Enum.Material.Glass then
		return "Shatter"
	else
		return "Smoke"
	end
end

-- ═══════════════════════════════════════════════════════════
--  VISUAL EFFECTS
-- ═══════════════════════════════════════════════════════════

-- Create muzzle flash effect
local function createMuzzleFlash(muzzlePart)
	if not muzzlePart then
		return
	end

	-- Check if custom muzzle flash asset is provided
	if VFXAssets.MuzzleFlash then
		local customFlash = VFXAssets.MuzzleFlash

		-- If it's a ParticleEmitter, clone and emit
		if customFlash:IsA("ParticleEmitter") then
			local particle = customFlash:Clone()
			particle.Parent = muzzlePart
			particle:Emit(particle:GetAttribute("EmitCount") or 5)

			task.delay(1, function()
				particle:Destroy()
			end)

			return
		end

		-- If it's a folder with multiple effects, clone all children
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

	-- Default muzzle flash (if no custom asset)
	-- Particle emitter for muzzle flash
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

	-- Point light for muzzle flash
	local light = Instance.new("PointLight")
	light.Brightness = 5
	light.Color = Color3.new(1, 0.8, 0.3)
	light.Range = 10
	light.Shadows = true
	light.Parent = muzzlePart

	-- Emit particles
	particle:Emit(5)

	-- Flash light
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
	local distance = (endPos - startPos).Magnitude
	local direction = (endPos - startPos).Unit

	-- Create beam
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
	beam.Width1 = 0.05
	beam.FaceCamera = true
	beam.Transparency = NumberSequence.new(0.3)
	beam.Parent = tracerPart

	-- Fade out and destroy
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
	-- Hit marker part
	local hitPart = Instance.new("Part")
	hitPart.Anchored = true
	hitPart.CanCollide = false
	hitPart.Transparency = 1
	hitPart.Size = Vector3.new(0.5, 0.5, 0.5)
	hitPart.CFrame = CFrame.new(position, position + normal)
	hitPart.Parent = workspace

	-- Particle effect based on material
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

	-- Add sparkles for metal
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

	-- Headshot effect
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

	-- Clean up
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

	-- Check if custom shell casing is provided
	if VFXAssets.ShellCasing then
		local customShell = VFXAssets.ShellCasing

		-- Clone the custom shell
		if customShell:IsA("BasePart") or customShell:IsA("MeshPart") then
			shell = customShell:Clone()
		elseif customShell:IsA("Model") then
			shell = customShell:Clone()
			-- Set up the primary part for models
			if not shell.PrimaryPart then
				shell.PrimaryPart = shell:FindFirstChildWhichIsA("BasePart")
			end
		end
	end

	-- Create default shell if no custom one
	if not shell then
		shell = Instance.new("Part")
		shell.Size = Vector3.new(0.1, 0.3, 0.1)
		shell.Material = Enum.Material.Metal
		shell.Color = Color3.fromRGB(200, 180, 100)
	end

	-- Position shell at ejection port
	if shell:IsA("Model") and shell.PrimaryPart then
		shell:SetPrimaryPartCFrame(ejectionPort.CFrame * CFrame.new(0.3, 0, 0) * CFrame.Angles(math.rad(90), 0, 0))
	elseif shell:IsA("BasePart") then
		shell.CFrame = ejectionPort.CFrame * CFrame.new(0.3, 0, 0) * CFrame.Angles(math.rad(90), 0, 0)
		shell.CanCollide = true
	end

	shell.Parent = workspace

	-- Get the main part for physics (Model or BasePart)
	local physicsPart = shell:IsA("Model") and shell.PrimaryPart or shell

	if physicsPart then
		-- Add velocity
		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.Velocity = (ejectionPort.CFrame.RightVector * 15)
			+ (ejectionPort.CFrame.UpVector * 5)
			+ (ejectionPort.CFrame.LookVector * math.random(-2, 2))
		bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
		bodyVelocity.Parent = physicsPart

		-- Add spin
		local bodyAngularVelocity = Instance.new("BodyAngularVelocity")
		bodyAngularVelocity.AngularVelocity =
			Vector3.new(math.random(-50, 50), math.random(-50, 50), math.random(-50, 50))
		bodyAngularVelocity.MaxTorque = Vector3.new(500, 500, 500)
		bodyAngularVelocity.Parent = physicsPart

		-- Remove forces after a bit
		task.delay(0.1, function()
			if bodyVelocity then
				bodyVelocity:Destroy()
			end
			if bodyAngularVelocity then
				bodyAngularVelocity:Destroy()
			end
		end)
	end

	-- Play shell eject sound if available
	if Sounds.ShellEject then
		Sounds.ShellEject:Play()
	end

	-- Clean up shell after some time
	game:GetService("Debris"):AddItem(shell, 5)
end

-- Camera shake
local function cameraShake(intensity)
	local shakeDuration = 0.1
	local shakeAmount = intensity or 0.5

	task.spawn(function()
		local startTime = tick()
		while tick() - startTime < shakeDuration do
			local progress = (tick() - startTime) / shakeDuration
			local currentShake = shakeAmount * (1 - progress)

			Camera.CFrame = Camera.CFrame
				* CFrame.Angles(
					math.rad(math.random(-currentShake, currentShake)),
					math.rad(math.random(-currentShake, currentShake)),
					math.rad(math.random(-currentShake, currentShake))
				)

			RunService.RenderStepped:Wait()
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
--  CAMERA RECOIL
-- ═══════════════════════════════════════════════════════════

-- Apply camera recoil
local function applyCameraRecoil(recoilData)
	if not recoilData then
		return
	end

	local vertical = recoilData[1] or 0
	local horizontal = recoilData[2] or 0

	RecoilOffset = RecoilOffset + Vector2.new(horizontal, vertical)
end

-- Update camera with recoil
RunService.RenderStepped:Connect(function(deltaTime)
	if RecoilOffset.Magnitude > 0.01 then
		-- Apply recoil to camera
		local cameraCFrame = Camera.CFrame
		Camera.CFrame = cameraCFrame * CFrame.Angles(math.rad(-RecoilOffset.Y), math.rad(-RecoilOffset.X), 0)

		-- Recover recoil
		RecoilOffset = RecoilOffset:Lerp(Vector2.new(0, 0), RecoilRecoverySpeed * deltaTime)
	end
end)

-- ═══════════════════════════════════════════════════════════
--  ANIMATIONS
-- ═══════════════════════════════════════════════════════════

-- Load animations
local function loadAnimations(animationIds)
	debugLog("ANIM", "Loading animations...")
	debugLog("CONFIG", "Animation IDs received:")
	for name, id in pairs(animationIds) do
		debugLog("INFO", "  └─", name, "=", id)
	end

	-- Clean up old animations
	for name, track in pairs(AnimationTracks) do
		if track then
			debugLog("INFO", "Stopping and cleaning up old animation:", name)
			track:Stop()
			track:Destroy()
		end
		AnimationTracks[name] = nil
	end

	-- Load new animations
	local animator = Humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		debugLog("INFO", "No Animator found, creating one...")
		animator = Instance.new("Animator")
		animator.Parent = Humanoid
		debugLog("SUCCESS", "Created Animator")
	else
		debugLog("INFO", "Found existing Animator")
	end

	local loadedCount = 0
	local skippedCount = 0

	for name, animId in pairs(animationIds) do
		if animId and animId > 0 then
			debugLog("LOAD", "Loading animation:", name, "with ID:", animId)

			local animation = Instance.new("Animation")
			animation.AnimationId = "rbxassetid://" .. animId

			local success, track = pcall(function()
				return animator:LoadAnimation(animation)
			end)

			if success and track then
				AnimationTracks[name] = track
				debugLog("SUCCESS", "Loaded animation:", name)
				debugLog("INFO", "  └─ ID: rbxassetid://" .. animId)
				debugLog("INFO", "  └─ Length:", track.Length, "seconds")
				debugLog("INFO", "  └─ Priority:", track.Priority.Name)
				loadedCount = loadedCount + 1
			else
				debugLog("ERROR", "Failed to load animation:", name)
				debugLog("ERROR", "  └─ Error:", tostring(track))
			end

			animation:Destroy()
		else
			debugLog("WARNING", "Skipping animation:", name, "(ID is 0 or nil)")
			skippedCount = skippedCount + 1
		end
	end

	debugLog("INFO", "Animation loading complete!")
	debugLog("INFO", "  └─ Loaded:", loadedCount)
	debugLog("INFO", "  └─ Skipped:", skippedCount)

	-- Play idle animation
	if AnimationTracks.Idle then
		AnimationTracks.Idle.Looped = true
		AnimationTracks.Idle:Play()
		debugLog("SUCCESS", "Started playing Idle animation")
	else
		debugLog("WARNING", "No Idle animation to play")
	end
end

-- Play animation
local function playAnimation(animName, fadeTime)
	local track = AnimationTracks[animName]
	if track then
		track:Play(fadeTime or 0.1)
	end
end

-- ═══════════════════════════════════════════════════════════
--  INPUT HANDLING
-- ═══════════════════════════════════════════════════════════

-- Track if mouse is held down
local IsMouseDown = false
local FireConnection = nil

-- Handle mouse input
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

	-- Fire gun on mouse click
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		IsMouseDown = true

		-- Determine fire mode
		if GunConfig.FireMode == "Auto" or GunConfig.FireMode == "Burst" then
			-- Auto fire loop
			FireConnection = RunService.Heartbeat:Connect(function()
				if IsMouseDown and CanFire then
					local mouse = Player:GetMouse()
					if mouse then
						FireGunRemote:FireServer(mouse.Hit.Position)
					end
				end
			end)
		elseif GunConfig.FireMode == "Semi" then
			-- Single shot
			if CanFire then
				local mouse = Player:GetMouse()
				if mouse then
					FireGunRemote:FireServer(mouse.Hit.Position)
				end
			end
		end
	end

	-- Reload on R key
	if input.KeyCode == Enum.KeyCode.R then
		ReloadGunRemote:FireServer()
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

-- Handle gun equipped
EquipGunRemote.OnClientEvent:Connect(function(config)
	debugLog(
		"FIRE",
		"═══════════════════════════════════════════"
	)
	debugLog("FIRE", "GUN EQUIP EVENT RECEIVED")
	debugLog(
		"FIRE",
		"═══════════════════════════════════════════"
	)

	GunConfig = config
	GunFrame.Visible = true

	-- Print full config
	debugLog("CONFIG", "Full gun configuration:")
	debugLog("INFO", "GunName:", config.GunName)
	debugLog("INFO", "GunImage:", config.GunImage)
	debugLog("INFO", "BaseDamage:", config.BaseDamage)
	debugLog("INFO", "HeadshotMultiplier:", config.HeadshotMultiplier)
	debugLog("INFO", "FireRate:", config.FireRate, "RPM")
	debugLog("INFO", "FireMode:", config.FireMode)
	debugLog("INFO", "MagazineSize:", config.MagazineSize)
	debugLog("INFO", "ReserveAmmo:", config.ReserveAmmo)
	debugLog("INFO", "MaxRange:", config.MaxRange)

	debugLog("CONFIG", "Recoil Pattern:")
	for i, pattern in ipairs(config.RecoilPattern or {}) do
		debugLog("INFO", string.format("  └─ Shot %d: Vertical=%.2f, Horizontal=%.2f", i, pattern[1], pattern[2]))
	end

	debugLog("LOAD", "Looking for assets in: ReplicatedStorage > Assets >", config.GunName)

	-- Check if Assets folder exists
	if not AssetsFolder then
		debugLog("ERROR", "Assets folder not found in ReplicatedStorage!")
		return
	else
		debugLog("SUCCESS", "Assets folder found")
	end

	-- List available folders in Assets
	debugLog("INFO", "Available folders in Assets:")
	for _, folder in ipairs(AssetsFolder:GetChildren()) do
		debugLog("INFO", "  └─", folder.Name, "(" .. folder.ClassName .. ")")
	end

	-- Clean up old sounds
	cleanupSounds()

	-- Load sounds from config
	if config.Assets then
		debugLog("CONFIG", "Assets configuration found:")
		debugLog("INFO", "  FireSound:", config.Assets.FireSound or "nil")
		debugLog("INFO", "  ReloadSound:", config.Assets.ReloadSound or "nil")
		debugLog("INFO", "  EmptyClickSound:", config.Assets.EmptyClickSound or "nil")
		debugLog("INFO", "  ShellEjectSound:", config.Assets.ShellEjectSound or "nil")
		debugLog("INFO", "  MuzzleFlash:", config.Assets.MuzzleFlash or "nil")
		debugLog("INFO", "  ShellCasing:", config.Assets.ShellCasing or "nil")

		debugLog("SOUND", "═══ LOADING SOUNDS ═══")
		Sounds.Fire = loadSound(config.Assets.FireSound, config.GunName)
		Sounds.Reload = loadSound(config.Assets.ReloadSound, config.GunName)
		Sounds.EmptyClick = loadSound(config.Assets.EmptyClickSound, config.GunName)
		Sounds.ShellEject = loadSound(config.Assets.ShellEjectSound, config.GunName)

		debugLog("SOUND", "Sound loading summary:")
		debugLog("INFO", "  FireSound:", Sounds.Fire and "✅ LOADED" or "❌ FAILED")
		debugLog("INFO", "  ReloadSound:", Sounds.Reload and "✅ LOADED" or "❌ FAILED")
		debugLog("INFO", "  EmptyClick:", Sounds.EmptyClick and "✅ LOADED" or "❌ FAILED")
		debugLog("INFO", "  ShellEject:", Sounds.ShellEject and "✅ LOADED" or "❌ FAILED")

		-- Load VFX assets
		debugLog("VFX", "═══ LOADING VFX ASSETS ═══")
		VFXAssets.MuzzleFlash = loadVFXAsset(config.Assets.MuzzleFlash, config.GunName)
		VFXAssets.BulletTracer = loadVFXAsset(config.Assets.BulletTracer, config.GunName)
		VFXAssets.HitEffect = loadVFXAsset(config.Assets.HitEffect, config.GunName)
		VFXAssets.ShellCasing = loadVFXAsset(config.Assets.ShellCasing, config.GunName)

		debugLog("VFX", "VFX loading summary:")
		debugLog("INFO", "  MuzzleFlash:", VFXAssets.MuzzleFlash and "✅ LOADED" or "⚪ Using default")
		debugLog("INFO", "  BulletTracer:", VFXAssets.BulletTracer and "✅ LOADED" or "⚪ Using default")
		debugLog("INFO", "  HitEffect:", VFXAssets.HitEffect and "✅ LOADED" or "⚪ Using default")
		debugLog("INFO", "  ShellCasing:", VFXAssets.ShellCasing and "✅ LOADED" or "⚪ Using default")
	else
		debugLog("ERROR", "No Assets table found in config!")
	end

	-- Load animations
	if config.Animations then
		debugLog("ANIM", "═══ LOADING ANIMATIONS ═══")
		loadAnimations(config.Animations)
	else
		debugLog("WARNING", "No Animations table found in config")
	end

	-- Wait for tool to be equipped
	task.wait(0.1)
	EquippedTool = Character:FindFirstChildOfClass("Tool")

	if EquippedTool then
		debugLog("SUCCESS", "Tool equipped:", EquippedTool.Name)
		debugLog("INFO", "  └─ Muzzle:", EquippedTool:FindFirstChild("Muzzle") and "✅ Found" or "❌ Missing")
		debugLog(
			"INFO",
			"  └─ EjectionPort:",
			EquippedTool:FindFirstChild("EjectionPort") and "✅ Found" or "⚪ Optional"
		)
	else
		debugLog("WARNING", "No tool found in character")
	end

	debugLog(
		"SUCCESS",
		"═══════════════════════════════════════════"
	)
	debugLog("SUCCESS", "GUN SETUP COMPLETE!")
	debugLog(
		"SUCCESS",
		"═══════════════════════════════════════════"
	)
end)

-- Handle gun unequipped
UnequipGunRemote.OnClientEvent:Connect(function()
	GunConfig = nil
	EquippedTool = nil
	GunFrame.Visible = false

	-- Clean up sounds
	cleanupSounds()

	-- Clear VFX assets
	VFXAssets.MuzzleFlash = nil
	VFXAssets.BulletTracer = nil
	VFXAssets.HitEffect = nil
	VFXAssets.ShellCasing = nil

	-- Stop animations
	for name, track in pairs(AnimationTracks) do
		if track then
			track:Stop()
		end
	end
end)

-- Handle effects
PlayEffectRemote.OnClientEvent:Connect(function(effectType, data)
	debugLog("FIRE", "Effect requested:", effectType)

	if effectType == "Fire" then
		debugLog("FIRE", "Playing fire effects...")

		-- Play fire animation
		playAnimation("Fire", 0.05)

		-- Get muzzle and ejection port
		local muzzle = EquippedTool and EquippedTool:FindFirstChild("Muzzle")
		local ejectionPort = EquippedTool and EquippedTool:FindFirstChild("EjectionPort") or muzzle

		debugLog("INFO", "Muzzle part:", muzzle and "✅ Found" or "❌ Missing")
		debugLog("INFO", "Ejection port:", ejectionPort and "✅ Found" or "❌ Missing")

		-- Muzzle flash
		if muzzle then
			debugLog("VFX", "Creating muzzle flash...")
			createMuzzleFlash(muzzle)
		else
			debugLog("ERROR", "Cannot create muzzle flash - no muzzle part!")
		end

		-- Shell ejection
		if ejectionPort then
			debugLog("VFX", "Creating shell ejection...")
			createShellEjection(ejectionPort)
		end

		-- Bullet tracer
		if data.MuzzlePosition and data.HitResult then
			debugLog("VFX", "Creating bullet tracer...")
			createBulletTracer(data.MuzzlePosition, data.HitResult.Position)
		end

		-- Hit effect
		if data.HitResult and data.HitResult.Hit then
			debugLog("VFX", "Creating hit effect at", data.HitResult.Position)
			debugLog("INFO", "  └─ Material:", data.HitResult.Material.Name)
			debugLog("INFO", "  └─ Headshot:", data.HitResult.IsHeadshot and "YES" or "NO")
			createHitEffect(
				data.HitResult.Position,
				data.HitResult.Normal,
				data.HitResult.Material,
				data.HitResult.IsHeadshot
			)
		end

		-- Camera recoil
		if data.Recoil then
			debugLog("INFO", string.format("Applying recoil: V=%.2f, H=%.2f", data.Recoil[1], data.Recoil[2]))
			applyCameraRecoil(data.Recoil)
		end

		-- Camera shake
		cameraShake(0.3)

		-- Play fire sound
		if Sounds.Fire then
			debugLog("SOUND", "Playing fire sound...")
			Sounds.Fire:Play()
		else
			debugLog("WARNING", "Fire sound not loaded - cannot play!")
		end
	elseif effectType == "Reload" then
		debugLog("INFO", "Reload effect:", data.ReloadType, "- Time:", data.ReloadTime, "seconds")
		-- Play reload animation
		local animName = data.ReloadType == "Tactical" and "ReloadTactical" or "ReloadEmpty"
		debugLog("ANIM", "Playing reload animation:", animName)
		playAnimation(animName, 0.2)

		-- Play reload sound
		if Sounds.Reload then
			debugLog("SOUND", "Playing reload sound...")
			Sounds.Reload:Play()
		else
			debugLog("WARNING", "Reload sound not loaded - cannot play!")
		end

		-- Disable firing during reload
		CanFire = false
		debugLog("INFO", "Firing disabled for", data.ReloadTime, "seconds")
		task.delay(data.ReloadTime, function()
			CanFire = true
			debugLog("SUCCESS", "Reload complete - firing enabled")
		end)
	elseif effectType == "EmptyClick" then
		debugLog("WARNING", "Gun is empty - playing empty click sound")
		-- Play empty click sound
		if Sounds.EmptyClick then
			Sounds.EmptyClick:Play()
		else
			debugLog("WARNING", "EmptyClick sound not loaded!")
		end
	end
end)

-- Handle ammo UI updates
UpdateAmmoRemote.OnClientEvent:Connect(function(ammoData)
	CurrentBulletLabel.Text = tostring(ammoData.CurrentAmmo)
	MaxBulletLabel.Text = tostring(ammoData.ReserveAmmo)

	-- Update gun image if provided
	if ammoData.GunImage then
		EquippedGunImage.Image = ammoData.GunImage
	end
end)

-- ═══════════════════════════════════════════════════════════
--  INITIALIZATION
-- ═══════════════════════════════════════════════════════════

-- Hide gun frame initially
GunFrame.Visible = false

debugLog(
	"SUCCESS",
	"═══════════════════════════════════════════"
)
debugLog("SUCCESS", "GUN CLIENT HANDLER INITIALIZED")
debugLog(
	"SUCCESS",
	"═══════════════════════════════════════════"
)
debugLog("CONFIG", "DEBUG MODE:", DEBUG and "ENABLED ✅" or "DISABLED")
debugLog("INFO", "Assets will be loaded from: ReplicatedStorage > Assets > [GunName]")
debugLog("INFO", "Waiting for gun to be equipped...")
debugLog(
	"SUCCESS",
	"═══════════════════════════════════════════"
)
