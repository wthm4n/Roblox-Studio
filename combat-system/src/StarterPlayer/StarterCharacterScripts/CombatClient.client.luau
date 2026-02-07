--[[
	CombatClient.lua
	
	TSB-inspired client combat with camera-based attacks.
	Features: Multi-target hits, dash combat, spin attacks, instant VFX.
	
	Author: Combat System Rewrite
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera

local SETTINGS = require(ReplicatedStorage.Modules.Combat:WaitForChild("CombatSettings"))
local RemoteFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local M1Event = RemoteFolder:WaitForChild("M1Attack")
local BlockEvent = RemoteFolder:WaitForChild("Block")
local HitEvent = RemoteFolder:WaitForChild("Hit")
local DashEvent = RemoteFolder:WaitForChild("Dash")
local SoundEvent = RemoteFolder:WaitForChild("PlaySound") -- Instant sound sync

local CombatVFX = ReplicatedStorage.Assets.CombatSystem:WaitForChild("CombatVfx")
local ConstantArmAura = CombatVFX:WaitForChild("ConstantArmAura")
local TargetHitVfx = CombatVFX:WaitForChild("TargetHitVfx")
local BlockVfx = CombatVFX:WaitForChild("BlockVfx")

-- ========================================
-- STATE
-- ========================================

local state = {
	isAttacking = false,
	isDashing = false,
	isBlocking = false,
	isSprinting = false,

	currentCombo = 0,
	lastDash = 0,
	lastAttack = 0,

	activeAura = nil,
	activeDashBodyVelocity = nil,
}

local animations = {}
local animator = nil

-- ========================================
-- SOUND PRE-CACHE (Eliminates lag on first play)
-- ========================================

local soundCache = {}

local function PreloadSounds()
	local ContentProvider = game:GetService("ContentProvider")

	-- Pre-create all combat sounds
	local soundsToCache = {
		M1 = SETTINGS.Audio.M1Sound,
		M2 = SETTINGS.Audio.M2Sound,
		M3 = SETTINGS.Audio.M3Sound,
		M4 = SETTINGS.Audio.M4Sound,
		Block = SETTINGS.Audio.BlockHit,
	}

	local assetsToPreload = {}

	for name, soundId in soundsToCache do
		if soundId and soundId ~= "" then
			table.insert(assetsToPreload, soundId)
		end
	end

	-- Preload all at once (faster)
	ContentProvider:PreloadAsync(assetsToPreload)

	print("✅ Combat sounds pre-cached (" .. #assetsToPreload .. " sounds)")
end

-- Optimized instant sound playback
local function PlayHitSound(soundId: string, position: Vector3)
	if not soundId or soundId == "" then
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = SETTINGS.Audio.HitVolume
	sound.PlayOnRemove = false

	-- Create attachment for 3D positioning
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	sound.Parent = attachment
	sound:Play()

	-- Cleanup
	Debris:AddItem(attachment, 1)
end

-- Pre-load sounds immediately
task.spawn(PreloadSounds)

-- ========================================
-- DAMAGE NUMBERS
-- ========================================

local function CreateDamageNumber(position: Vector3, damage: number, color: Color3, isSpecial: boolean)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Size = UDim2.new(0, 100, 0, 50)
	billboardGui.StudsOffset = Vector3.new(math.random(-2, 2), 3, 0)
	billboardGui.AlwaysOnTop = true
	billboardGui.Parent = workspace.CurrentCamera

	local textLabel = Instance.new("TextLabel")
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.Text = tostring(math.floor(damage))
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = isSpecial and 32 or SETTINGS.VFX.DamageNumbers.Size
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.5
	textLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	textLabel.Parent = billboardGui

	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain

	billboardGui.Adornee = attachment
	billboardGui.Parent = workspace

	-- Animate
	local riseSpeed = SETTINGS.VFX.DamageNumbers.RiseSpeed
	local duration = SETTINGS.VFX.DamageNumbers.Duration

	task.spawn(function()
		local startTime = tick()
		local startPos = position

		while tick() - startTime < duration do
			local alpha = (tick() - startTime) / duration
			local newPos = startPos + Vector3.new(0, riseSpeed * alpha, 0)
			attachment.WorldPosition = newPos
			textLabel.TextTransparency = alpha
			textLabel.TextStrokeTransparency = 0.5 + (alpha * 0.5)

			task.wait()
		end

		billboardGui:Destroy()
		attachment:Destroy()
	end)
end

-- ========================================
-- VFX SYSTEM
-- ========================================

local VFXController = {}

function VFXController.PlayHitVFX(targetChar: Model, isHeavy: boolean, isFinisher: boolean)
	local hrp = targetChar:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local hitVfx = TargetHitVfx:Clone()
	local offset = CFrame.new(0, 1, -0.6)

	if hitVfx:IsA("Model") then
		hitVfx:PivotTo(hrp.CFrame * offset)
	else
		hitVfx.CFrame = hrp.CFrame * offset
	end

	hitVfx.Parent = workspace -- Parent AFTER positioning for instant appearance

	-- Emit particles IMMEDIATELY
	for _, v in hitVfx:GetDescendants() do
		if v:IsA("ParticleEmitter") then
			local count = v:GetAttribute("EmitCount") or 30
			if isFinisher then
				count *= 2
			end
			v:Emit(count)
		end
	end

	Debris:AddItem(hitVfx, 0.5)
end

function VFXController.PlayBlockVFX(targetRoot: BasePart, isPerfect: boolean)
	local blockEffect = BlockVfx:Clone()

	if blockEffect:IsA("Model") then
		blockEffect:PivotTo(targetRoot.CFrame)
	else
		blockEffect.CFrame = targetRoot.CFrame
	end

	blockEffect.Parent = targetRoot -- Parent AFTER positioning

	-- Emit particles IMMEDIATELY
	for _, desc in blockEffect:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			local count = desc:GetAttribute("EmitCount") or 20
			if isPerfect then
				count = count * 1.5
			end
			desc:Emit(count)
		end
	end

	Debris:AddItem(blockEffect, 1.5)
end

function VFXController.EnableArmAura()
	if state.activeAura then
		return
	end

	local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	local leftArm = character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")

	if rightArm and leftArm then
		state.activeAura = {}

		local rightAura = ConstantArmAura:Clone()
		rightAura.Parent = rightArm
		table.insert(state.activeAura, rightAura)

		local leftAura = ConstantArmAura:Clone()
		leftAura.Parent = leftArm
		table.insert(state.activeAura, leftAura)

		for _, aura in state.activeAura do
			for _, desc in aura:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = true
				end
			end
		end
	end
end

function VFXController.DisableArmAura()
	if not state.activeAura then
		return
	end

	for _, aura in state.activeAura do
		for _, desc in aura:GetDescendants() do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = false
			end
		end

		Debris:AddItem(aura, 2)
	end

	state.activeAura = nil
end

function VFXController.ScreenShake(shakeType: string)
	local shakeData = SETTINGS.VFX.ScreenShake[shakeType]
	if not shakeData then
		return
	end

	local magnitude = shakeData.Magnitude
	local duration = shakeData.Duration

	task.spawn(function()
		local elapsed = 0
		while elapsed < duration do
			local shake = Vector3.new(
				math.random(-100, 100) / 100 * magnitude,
				math.random(-100, 100) / 100 * magnitude,
				math.random(-100, 100) / 100 * magnitude
			)
			camera.CFrame = camera.CFrame * CFrame.new(shake)
			elapsed += task.wait()
		end
	end)
end

-- ========================================
-- ANIMATION SYSTEM
-- ========================================

local function LoadAnimations()
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function load(id: string)
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		return animator:LoadAnimation(anim)
	end

	animations.Walk = load(SETTINGS.Animations.Walk)
	animations.Sprint = load(SETTINGS.Animations.Sprint)

	-- Fixed dash animation names to match direction
	animations.FrontDash = load(SETTINGS.Animations.FrontDash)
	animations.BackDash = load(SETTINGS.Animations.BackDash)
	animations.LeftDash = load(SETTINGS.Animations.SideDashLeft) -- Maps to Left direction
	animations.RightDash = load(SETTINGS.Animations.SideDashRight) -- Maps to Right direction

	animations.M1 = load(SETTINGS.Animations.M1.Id)
	animations.M2 = load(SETTINGS.Animations.M2.Id)
	animations.M3 = load(SETTINGS.Animations.M3.Id)
	animations.M4 = load(SETTINGS.Animations.M4.Id)
end

LoadAnimations()

-- ========================================
-- MOVEMENT SYSTEM
-- ========================================

local currentMoveAnim = nil
local isSprinting = false

local function UpdateMovement()
	local velocity = rootPart.Velocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if state.isDashing or state.isAttacking or state.isBlocking then
		if currentMoveAnim then
			currentMoveAnim:Stop()
			currentMoveAnim = nil
		end
		return
	end

	if horizontalSpeed > 2 then
		local targetAnim = isSprinting and animations.Sprint or animations.Walk

		if currentMoveAnim ~= targetAnim then
			if currentMoveAnim then
				currentMoveAnim:Stop()
			end
			currentMoveAnim = targetAnim
			currentMoveAnim:Play()
		end
	else
		if currentMoveAnim then
			currentMoveAnim:Stop()
			currentMoveAnim = nil
		end
	end
end

RunService.RenderStepped:Connect(UpdateMovement)

-- ========================================
-- SPRINT SYSTEM
-- ========================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == SETTINGS.Player.SprintKey then
		if not state.isBlocking and not state.isAttacking then
			isSprinting = true
			humanoid.WalkSpeed = SETTINGS.Player.SprintSpeed
			VFXController.EnableArmAura()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == SETTINGS.Player.SprintKey then
		isSprinting = false
		if not state.isBlocking then
			humanoid.WalkSpeed = SETTINGS.Player.WalkSpeed
		end
		VFXController.DisableArmAura()
	end
end)

-- ========================================
-- IMPROVED DASH SYSTEM (TSB-Style)
-- ========================================

local keysPressed = { W = false, A = false, S = false, D = false }

local function PerformDash(direction: string)
	if state.isDashing or state.isBlocking then
		return
	end

	local currentTime = tick()
	if currentTime - state.lastDash < SETTINGS.Dash.Cooldown then
		return
	end

	state.isDashing = true
	state.lastDash = currentTime

	-- Notify server
	DashEvent:FireServer(true)

	-- Stop movement animation
	if currentMoveAnim then
		currentMoveAnim:Stop()
	end

	-- Play dash animation with proper direction mapping
	local animName = direction .. "Dash"
	local dashAnim = animations[animName]
	if dashAnim then
		dashAnim:Play()
	else
		warn("Dash animation not found: " .. animName)
	end

	-- Calculate direction (CAMERA-RELATIVE)
	local cameraCF = camera.CFrame
	local dashDir = Vector3.zero

	if direction == "Front" then
		dashDir = Vector3.new(cameraCF.LookVector.X, 0, cameraCF.LookVector.Z).Unit
	elseif direction == "Back" then
		dashDir = -Vector3.new(cameraCF.LookVector.X, 0, cameraCF.LookVector.Z).Unit
	elseif direction == "Left" then -- Fixed: was "SideLeft"
		dashDir = -Vector3.new(cameraCF.RightVector.X, 0, cameraCF.RightVector.Z).Unit
	elseif direction == "Right" then -- Fixed: was "SideRight"
		dashDir = Vector3.new(cameraCF.RightVector.X, 0, cameraCF.RightVector.Z).Unit
	end

	-- Remove old dash velocity
	if state.activeDashBodyVelocity then
		state.activeDashBodyVelocity:Destroy()
	end

	-- Apply dash velocity
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Name = "DashVelocity"
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.Velocity = dashDir * SETTINGS.Dash.Speed
	bodyVelocity.Parent = rootPart
	state.activeDashBodyVelocity = bodyVelocity

	-- End dash
	task.delay(SETTINGS.Dash.Duration, function()
		if bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
		state.activeDashBodyVelocity = nil
		state.isDashing = false

		-- Notify server
		DashEvent:FireServer(false)

		if dashAnim then
			dashAnim:Stop()
		end
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Track WASD
	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = true
	end

	-- Dash (Fixed direction names)
	if input.KeyCode == SETTINGS.Dash.Key then
		if keysPressed.S then
			PerformDash("Back")
		elseif keysPressed.A then
			PerformDash("Left") -- Fixed: was "SideLeft"
		elseif keysPressed.D then
			PerformDash("Right") -- Fixed: was "SideRight"
		else
			PerformDash("Front")
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = false
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = false
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = false
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = false
	end
end)

-- ========================================
-- BLOCKING SYSTEM
-- ========================================

local activeBlockVFX = nil

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == SETTINGS.Block.Key then
		if not state.isAttacking and not state.isDashing and not state.isBlocking then
			state.isBlocking = true
			humanoid.WalkSpeed = SETTINGS.Player.BlockSpeed
			BlockEvent:FireServer(true)

			activeBlockVFX = BlockVfx:Clone()
			activeBlockVFX.Name = "ActiveBlock"
			activeBlockVFX.Parent = rootPart

			for _, desc in activeBlockVFX:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = true
				end
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == SETTINGS.Block.Key then
		if state.isBlocking then
			state.isBlocking = false
			humanoid.WalkSpeed = isSprinting and SETTINGS.Player.SprintSpeed or SETTINGS.Player.WalkSpeed
			BlockEvent:FireServer(false)

			if activeBlockVFX then
				activeBlockVFX:Destroy()
				activeBlockVFX = nil
			end
		end
	end
end)

-- ========================================
-- M1 ATTACK SYSTEM (Camera-Based + Client Prediction)
-- ========================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Allow attacking during dash (TSB-style)
		if state.isBlocking then
			return
		end

		if state.isAttacking and not SETTINGS.Dash.AllowAttackDuringDash then
			return
		end

		local currentTime = tick()
		if currentTime - state.lastAttack < SETTINGS.M1.AttackCooldown then
			return
		end

		state.lastAttack = currentTime

		-- CLIENT-SIDE PREDICTION: Play swing sound instantly
		local swingSound = Instance.new("Sound")
		swingSound.SoundId = "rbxassetid://0" -- Add swing whoosh sound here if you have one
		swingSound.Volume = 0.3
		swingSound.Parent = rootPart
		-- swingSound:Play() -- Uncomment if you add a swing sound

		-- Send camera direction to server for camera-based hitbox
		local cameraLookVector = nil
		if SETTINGS.M1.UseCameraDirection then
			cameraLookVector = camera.CFrame.LookVector
		end

		M1Event:FireServer(cameraLookVector)
	end
end)

-- ========================================
-- SERVER EVENTS
-- ========================================

-- Play attack animation
M1Event.OnClientEvent:Connect(function(combo: number, isHeavy: boolean, isFinisher: boolean)
	state.isAttacking = true
	state.currentCombo = combo

	-- STOP ALL PREVIOUS M1 ANIMATIONS (prevents blending issues)
	for i = 1, 4 do
		local animKey = "M" .. i
		local anim = animations[animKey]
		if anim and anim.IsPlaying then
			anim:Stop(0) -- Instant stop (no fade time)
		end
	end

	-- Play the new animation
	local animKey = "M" .. combo
	local anim = animations[animKey]
	if anim then
		anim:Play(0.05, 1, 1) -- Fast fade in, normal weight, normal speed
	end

	local animData = SETTINGS.Animations[animKey]
	local duration = animData and animData.Duration or 0.5

	VFXController.EnableArmAura()

	task.delay(duration, function()
		state.isAttacking = false

		if not isSprinting then
			VFXController.DisableArmAura()
		end
	end)
end)

-- INSTANT HIT FEEDBACK (plays immediately when damage applies)
HitEvent.OnClientEvent:Connect(
	function(
		targetChar: Model,
		damage: number,
		combo: number,
		isHeavy: boolean,
		isFinisher: boolean,
		wasBlocked: boolean,
		wasPerfectBlock: boolean
	)
		local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
		if not targetRoot then
			return
		end

		-- Determine damage color
		local color = SETTINGS.VFX.DamageNumbers.NormalColor
		if wasPerfectBlock then
			color = SETTINGS.VFX.DamageNumbers.CriticalColor
		elseif wasBlocked then
			color = SETTINGS.VFX.DamageNumbers.BlockedColor
		elseif isFinisher then
			color = SETTINGS.VFX.DamageNumbers.FinisherColor
		elseif isHeavy then
			color = SETTINGS.VFX.DamageNumbers.HeavyColor
		end

		-- Note: Sound is now played via instant SoundEvent (unreliable network)
		-- This provides the lowest possible latency for audio feedback

		-- Create damage number
		CreateDamageNumber(targetRoot.Position, damage, color, isFinisher or wasPerfectBlock)

		-- INSTANT VFX (plays when hit applies)
		if wasBlocked then
			VFXController.PlayBlockVFX(targetRoot, wasPerfectBlock)
		else
			VFXController.PlayHitVFX(targetChar, isHeavy, isFinisher)
		end

		-- Screen shake (only if WE got hit)
		if targetChar == character then
			if wasBlocked then
				VFXController.ScreenShake("Blocked")
			elseif isFinisher then
				VFXController.ScreenShake("Finisher")
			elseif isHeavy then
				VFXController.ScreenShake("Heavy")
			else
				VFXController.ScreenShake("Normal")
			end
		end
	end
)

-- Block feedback
BlockEvent.OnClientEvent:Connect(function(eventType: string, isPerfect: boolean)
	if eventType == "blocked" then
		local flash = Instance.new("Part")
		flash.Size = Vector3.new(4, 4, 0.1)
		flash.Transparency = 0.5
		flash.Color = isPerfect and Color3.fromRGB(255, 215, 0) or Color3.fromRGB(100, 200, 255)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CFrame = rootPart.CFrame * CFrame.new(0, 0, -2)
		flash.Parent = workspace

		TweenService:Create(flash, TweenInfo.new(0.3), {
			Transparency = 1,
			Size = Vector3.new(6, 6, 0.1),
		}):Play()

		Debris:AddItem(flash, 0.5)
	end
end)

-- Cleanup on death
character.Humanoid.Died:Connect(function()
	state.isAttacking = false
	state.isDashing = false
	state.isBlocking = false
	state.currentCombo = 0
	isSprinting = false

	VFXController.DisableArmAura()

	if activeBlockVFX then
		activeBlockVFX:Destroy()
		activeBlockVFX = nil
	end

	if state.activeDashBodyVelocity then
		state.activeDashBodyVelocity:Destroy()
		state.activeDashBodyVelocity = nil
	end
end)

-- ========================================
-- INSTANT SOUND PLAYBACK (Unreliable Network)
-- ========================================

SoundEvent.OnClientEvent:Connect(function(position: Vector3, soundKey: string)
	-- Map sound key to actual ID
	local soundId
	if soundKey == "M1Sound" then
		soundId = SETTINGS.Audio.M1Sound
	elseif soundKey == "M2Sound" then
		soundId = SETTINGS.Audio.M2Sound
	elseif soundKey == "M3Sound" then
		soundId = SETTINGS.Audio.M3Sound
	elseif soundKey == "M4Sound" then
		soundId = SETTINGS.Audio.M4Sound
	elseif soundKey == "BlockHit" then
		soundId = SETTINGS.Audio.BlockHit
	end

	if soundId then
		PlayHitSound(soundId, position)
	end
end)

print("✅ CombatClient initialized (TSB Multi-Target + Camera)")
