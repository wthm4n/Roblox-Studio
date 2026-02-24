--[[
	AdvancedCombatClient.lua
	
	Advanced combat with:
	- Block animations (idle + hit reactions 1-5)
	- Hit reactions when not blocking (1-5)
	- Block breaking mechanic
	- M1-M5 combo system
	- Animation marker-based hits
	- BEAST MODE (10s damage boost with UI bar)
	- Debug hitbox visualizer
	
	Author: Advanced Combat System
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
local HitRequestEvent = RemoteFolder:WaitForChild("HitRequest")
local HitResultEvent = RemoteFolder:WaitForChild("HitResult")
local BlockEvent = RemoteFolder:WaitForChild("Block")
local BlockDamageEvent = RemoteFolder:WaitForChild("BlockDamage")
local BeastModeEvent = RemoteFolder:WaitForChild("BeastMode")

local CombatVFX = ReplicatedStorage.Assets.CombatSystem:WaitForChild("CombatVfx")
local TargetHitVfx = CombatVFX:WaitForChild("TargetHitVfx")
local BlockVfx = CombatVFX:WaitForChild("BlockVfx")
local ConstantArmAura = CombatVFX:FindFirstChild("ConstantArmAura") -- Optional - won't error if missing

-- ========================================
-- UI SETUP
-- ========================================
local playerGui = player:WaitForChild("PlayerGui")
local beastModeBar = playerGui:WaitForChild("GUI"):WaitForChild("BeastMode"):WaitForChild("Bar")
local beastModeFrame = beastModeBar.Parent -- Main BeastMode frame

-- ========================================
-- STATE
-- ========================================

local state = {
	currentCombo = 0,
	isAttacking = false,
	isBlocking = false,
	isStunned = false,

	blockHealth = 100, -- Block durability

	-- BEAST MODE
	isBeastMode = false,
	beastModeEndTime = 0,
	beastModeCooldownEnd = 0,

	lastAttackTime = 0,
	comboResetTask = nil,
	stunTask = nil,
	beastModeTask = nil,
}

local animations = {}
local animator = nil
local currentBlockAnim = nil
local currentHitReactionAnim = nil
local activeBlockVFX = nil
local beastModeActivationAnim = nil
local leftArmAura = nil
local rightArmAura = nil

-- Debug hitbox visualizer
local debugHitboxPart = nil
local debugTargetMarkers = {}

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
		if not id or id == "" then
			return nil
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		return animator:LoadAnimation(anim)
	end

	-- M1-M5 Combo
	animations.M1 = load(SETTINGS.Animations.M1.Id)
	animations.M2 = load(SETTINGS.Animations.M2.Id)
	animations.M3 = load(SETTINGS.Animations.M3.Id)
	animations.M4 = load(SETTINGS.Animations.M4.Id)
	animations.M5 = load(SETTINGS.Animations.M5.Id)

	-- Blocking
	animations.Block = load(SETTINGS.Animations.Block)
	animations.BlockingHitReaction1 = load(SETTINGS.Animations.BlockingHitReaction1)
	animations.BlockingHitReaction2 = load(SETTINGS.Animations.BlockingHitReaction2)
	animations.BlockingHitReaction3 = load(SETTINGS.Animations.BlockingHitReaction3)
	animations.BlockingHitReaction4 = load(SETTINGS.Animations.BlockingHitReaction4)
	animations.BlockingHitReaction5 = load(SETTINGS.Animations.BlockingHitReaction5)
	animations.BlockBroken = load(SETTINGS.Animations.BlockBroken)

	-- Hit Reactions (when not blocking)
	animations.HitReaction1 = load(SETTINGS.Animations.HitReaction1)
	animations.HitReaction2 = load(SETTINGS.Animations.HitReaction2)
	animations.HitReaction3 = load(SETTINGS.Animations.HitReaction3)
	animations.HitReaction4 = load(SETTINGS.Animations.HitReaction4)
	animations.HitReaction5 = load(SETTINGS.Animations.HitReaction5)

	-- Beast Mode
	beastModeActivationAnim = load(SETTINGS.BeastMode.ActivationAnimation)
end

LoadAnimations()

local function StopAllAttackAnims()
	for i = 1, 5 do
		local animKey = "M" .. i
		local anim = animations[animKey]
		if anim and anim.IsPlaying then
			anim:Stop(0)
		end
	end
end

local function StopAllHitReactionAnims()
	for i = 1, 5 do
		local animKey = "HitReaction" .. i
		local anim = animations[animKey]
		if anim and anim.IsPlaying then
			anim:Stop(0.1)
		end

		local blockAnimKey = "BlockingHitReaction" .. i
		local blockAnim = animations[blockAnimKey]
		if blockAnim and blockAnim.IsPlaying then
			blockAnim:Stop(0.1)
		end
	end
end

-- ========================================
-- SOUND SYSTEM
-- ========================================

local function PlayHitSound(soundId: string, position: Vector3)
	if not soundId or soundId == "" then
		return
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.1, 0.1, 0.1)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = SETTINGS.Audio.HitVolume or 10
	sound.Parent = part

	sound:Play()

	Debris:AddItem(part, sound.TimeLength + 0.2)
end

-- ========================================
-- DEBUG HITBOX VISUALIZER
-- ========================================

local function CreateDebugHitbox()
	if not SETTINGS.Debug.ShowHitbox then
		return
	end

	if debugHitboxPart then
		debugHitboxPart:Destroy()
	end

	debugHitboxPart = Instance.new("Part")
	debugHitboxPart.Name = "DebugHitbox"
	debugHitboxPart.Shape = Enum.PartType.Ball
	debugHitboxPart.Size =
		Vector3.new(SETTINGS.M1.HitboxRange * 2, SETTINGS.M1.HitboxRange * 2, SETTINGS.M1.HitboxRange * 2)
	debugHitboxPart.Color = SETTINGS.Debug.HitboxColor
	debugHitboxPart.Transparency = SETTINGS.Debug.HitboxTransparency
	debugHitboxPart.Material = Enum.Material.Neon
	debugHitboxPart.Anchored = true
	debugHitboxPart.CanCollide = false
	debugHitboxPart.Parent = workspace
end

local function UpdateDebugHitbox()
	if not SETTINGS.Debug.ShowHitbox or not debugHitboxPart then
		return
	end

	if state.isAttacking then
		debugHitboxPart.CFrame = rootPart.CFrame
		debugHitboxPart.Transparency = 0.5
	else
		debugHitboxPart.Transparency = 0.9
		debugHitboxPart.CFrame = rootPart.CFrame
	end
end

local function ClearTargetMarkers()
	for _, marker in debugTargetMarkers do
		if marker and marker.Parent then
			marker:Destroy()
		end
	end
	debugTargetMarkers = {}
end

local function CreateTargetMarker(targetRoot: BasePart)
	if not SETTINGS.Debug.ShowTargets then
		return
	end

	local marker = Instance.new("Part")
	marker.Name = "TargetMarker"
	marker.Shape = Enum.PartType.Cylinder
	marker.Size = Vector3.new(0.5, 3, 3)
	marker.Color = SETTINGS.Debug.TargetMarkerColor
	marker.Transparency = 0.3
	marker.Material = Enum.Material.Neon
	marker.Anchored = true
	marker.CanCollide = false
	marker.CFrame = targetRoot.CFrame * CFrame.Angles(0, 0, math.rad(90))
	marker.Parent = workspace

	table.insert(debugTargetMarkers, marker)

	-- Remove after 0.5 seconds
	Debris:AddItem(marker, 0.5)
end

-- Initialize debug hitbox
CreateDebugHitbox()

-- Update hitbox position every frame
RunService.RenderStepped:Connect(UpdateDebugHitbox)

-- ========================================
-- BEAST MODE SYSTEM
-- ========================================

local function UpdateBeastModeUI()
	if state.isBeastMode then
		-- Active: shrink bar over time
		local timeRemaining = state.beastModeEndTime - tick()
		local progress = math.clamp(timeRemaining / SETTINGS.BeastMode.Duration, 0, 1)

		beastModeBar.Size = UDim2.new(progress, 0, 1, 0)
		beastModeFrame.Visible = true
	else
		-- Check cooldown
		local cooldownRemaining = state.beastModeCooldownEnd - tick()
		if cooldownRemaining > 0 then
			-- On cooldown: show cooldown progress
			local cooldownProgress = 1 - (cooldownRemaining / SETTINGS.BeastMode.Cooldown)
			beastModeBar.Size = UDim2.new(cooldownProgress, 0, 1, 0)
			beastModeFrame.Visible = true
		else
			-- Ready: full bar
			beastModeBar.Size = UDim2.new(1, 0, 1, 0)
			beastModeFrame.Visible = true
		end
	end
end

local function ActivateBeastMode()
	if state.isBeastMode or state.isStunned or state.isAttacking or state.isBlocking then
		return
	end

	-- Check cooldown
	if tick() < state.beastModeCooldownEnd then
		warn("Beast Mode on cooldown!")
		return
	end

	-- Play activation animation first
	if beastModeActivationAnim then
		state.isAttacking = true

		local SS = game:GetService("SoundService"):WaitForChild("BeastModeSound")
		local soundLength = SS.TimeLength

		local animLength = beastModeActivationAnim.Length

		local speedMultiplier = animLength / soundLength
		beastModeActivationAnim:AdjustSpeed(speedMultiplier)

		-- Play both together
		beastModeActivationAnim:Play(0.05, 1, 1)
		SS:Play()

		-- Wait for sound duration (now perfectly synced)
		task.wait(soundLength)
		state.isAttacking = false
	end

	-- NOW activate beast mode
	state.isBeastMode = true
	state.beastModeEndTime = tick() + SETTINGS.BeastMode.Duration

	-- Notify server
	BeastModeEvent:FireServer(true)

	-- Add constant arm auras ONLY
	if SETTINGS.BeastMode.ArmAuraEnabled and ConstantArmAura then
		local leftArm = character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")
		local rightArm = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")

		if leftArm then
			leftArmAura = ConstantArmAura:Clone()
			leftArmAura.Parent = leftArm

			-- Enable all particle emitters
			for _, desc in leftArmAura:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = true
				end
			end
		end

		if rightArm then
			rightArmAura = ConstantArmAura:Clone()
			rightArmAura.Parent = rightArm

			-- Enable all particle emitters
			for _, desc in rightArmAura:GetDescendants() do
				if desc:IsA("ParticleEmitter") then
					desc.Enabled = true
				end
			end
		end
	elseif SETTINGS.BeastMode.ArmAuraEnabled and not ConstantArmAura then
		warn("ConstantArmAura not found in ReplicatedStorage.Assets.CombatSystem.CombatVfx!")
	end

	if SETTINGS.Debug.LogBeastMode then
		print("🔥 BEAST MODE ACTIVATED!")
	end

	-- Auto-deactivate after duration
	if state.beastModeTask then
		task.cancel(state.beastModeTask)
	end

	state.beastModeTask = task.delay(SETTINGS.BeastMode.Duration, function()
		state.isBeastMode = false
		state.beastModeCooldownEnd = tick() + SETTINGS.BeastMode.Cooldown

		-- Notify server
		BeastModeEvent:FireServer(false)

		-- Remove arm auras
		if leftArmAura then
			leftArmAura:Destroy()
			leftArmAura = nil
		end
		if rightArmAura then
			rightArmAura:Destroy()
			rightArmAura = nil
		end

		-- Play deactivation sound
		if SETTINGS.Audio.BeastModeDeactivate and SETTINGS.Audio.BeastModeDeactivate ~= "" then
			PlayHitSound(SETTINGS.Audio.BeastModeDeactivate, rootPart.Position)
		end

		if SETTINGS.Debug.LogBeastMode then
			print("❄️ Beast Mode ended. Cooldown: " .. SETTINGS.BeastMode.Cooldown .. "s")
		end

		state.beastModeTask = nil
	end)
end

-- Update UI every frame
RunService.RenderStepped:Connect(UpdateBeastModeUI)

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

	hitVfx.Parent = hrp -- 🔥 attach to target

	Debris:AddItem(hitVfx, 0.5) -- ⏱️ 1 second
end

function VFXController.PlayBlockVFX(targetRoot: BasePart, isPerfect: boolean)
	local blockEffect = BlockVfx:Clone()

	if blockEffect:IsA("Model") then
		blockEffect:PivotTo(targetRoot.CFrame)
	else
		blockEffect.CFrame = targetRoot.CFrame
	end

	blockEffect.Parent = targetRoot

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
-- DAMAGE NUMBERS
-- ========================================

local function CreateDamageNumber(position: Vector3, damage: number, color: Color3, isSpecial: boolean)
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Size = UDim2.new(0, 100, 0, 50)
	billboardGui.StudsOffset = Vector3.new(math.random(-2, 2), 3, 0)
	billboardGui.AlwaysOnTop = true

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
-- STUN SYSTEM
-- ========================================

local function ApplyStun(duration: number)
	if state.isStunned then
		return
	end

	state.isStunned = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	if state.stunTask then
		task.cancel(state.stunTask)
	end

	state.stunTask = task.delay(duration, function()
		state.isStunned = false
		if not state.isBlocking then
			humanoid.WalkSpeed = SETTINGS.Player.WalkSpeed
		else
			humanoid.WalkSpeed = SETTINGS.Player.BlockSpeed
		end
		humanoid.JumpPower = 50
		state.stunTask = nil
	end)
end

-- ========================================
-- COMBO SYSTEM
-- ========================================

local function IncrementCombo()
	state.currentCombo = (state.currentCombo % SETTINGS.M1.MaxCombo) + 1

	if state.comboResetTask then
		task.cancel(state.comboResetTask)
	end

	state.comboResetTask = task.delay(SETTINGS.M1.ComboResetTime, function()
		state.currentCombo = 0
		state.comboResetTask = nil
	end)

	return state.currentCombo
end

-- ========================================
-- ANIMATION MARKER HANDLER
-- ========================================

local function OnAnimationMarker(markerName: string, combo: number)
	if markerName ~= "Hit" then
		return
	end

	ClearTargetMarkers() -- Clear old markers

	local cameraLookVector = camera.CFrame.LookVector
	HitRequestEvent:FireServer(combo, cameraLookVector, state.isBeastMode)

	-- Play local swing sound
	local soundId = SETTINGS.Audio["M" .. combo .. "Sound"]
	if soundId and soundId ~= "" then
		PlayHitSound(soundId, rootPart.Position)
	end
end

-- ========================================
-- M1-M5 ATTACK SYSTEM
-- ========================================

local function PerformAttack()
	if state.isAttacking or state.isBlocking or state.isStunned then
		return
	end

	local currentTime = tick()
	if currentTime - state.lastAttackTime < SETTINGS.M1.AttackCooldown then
		return
	end

	-- Check combo timeout
	if currentTime - state.lastAttackTime > SETTINGS.M1.ComboResetTime then
		state.currentCombo = 0
		if state.comboResetTask then
			task.cancel(state.comboResetTask)
			state.comboResetTask = nil
		end
	end

	state.lastAttackTime = currentTime
	state.isAttacking = true

	local combo = IncrementCombo()

	StopAllAttackAnims()

	local animKey = "M" .. combo
	local anim = animations[animKey]

	if anim then
		anim:Play(0.05, 1, 1)

		local markerConnection
		markerConnection = anim:GetMarkerReachedSignal("Hit"):Connect(function()
			OnAnimationMarker("Hit", combo)
			markerConnection:Disconnect()
		end)
	end

	local animData = SETTINGS.Animations[animKey]
	local duration = animData and animData.Duration or 0.5

	task.delay(duration, function()
		state.isAttacking = false
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		PerformAttack()
	end

	-- Beast Mode activation
	if input.KeyCode == SETTINGS.BeastMode.ActivationKey then
		ActivateBeastMode()
	end
end)

-- ========================================
-- BLOCKING SYSTEM
-- ========================================

local function StartBlocking()
	if state.isAttacking or state.isBlocking or state.isStunned then
		return
	end

	state.isBlocking = true
	state.blockHealth = SETTINGS.Block.MaxHealth
	humanoid.WalkSpeed = SETTINGS.Player.BlockSpeed
	BlockEvent:FireServer(true)

	-- Play block idle animation
	if animations.Block then
		animations.Block:Play(0.1)
		currentBlockAnim = animations.Block
	end

	-- Active block VFX
	activeBlockVFX = BlockVfx:Clone()
	activeBlockVFX.Name = "ActiveBlock"
	activeBlockVFX.Parent = rootPart

	for _, desc in activeBlockVFX:GetDescendants() do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = true
		end
	end
end

local function EndBlocking()
	if not state.isBlocking then
		return
	end

	state.isBlocking = false
	if not state.isStunned then
		humanoid.WalkSpeed = SETTINGS.Player.WalkSpeed
	end
	BlockEvent:FireServer(false)

	if currentBlockAnim then
		currentBlockAnim:Stop(0.1)
		currentBlockAnim = nil
	end

	if activeBlockVFX then
		activeBlockVFX:Destroy()
		activeBlockVFX = nil
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == SETTINGS.Block.Key then
		StartBlocking()
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.KeyCode == SETTINGS.Block.Key then
		EndBlocking()
	end
end)

-- ========================================
-- BLOCK DAMAGE HANDLER
-- ========================================

BlockDamageEvent.OnClientEvent:Connect(function(damage: number, attackerCombo: number)
	-- Reduce block health
	state.blockHealth = math.max(0, state.blockHealth - damage)

	-- Play blocking hit reaction (random 1-5)
	StopAllHitReactionAnims()
	local reactionNum = math.random(1, 5)
	local reactionAnim = animations["BlockingHitReaction" .. reactionNum]

	if reactionAnim then
		-- Stop block idle temporarily
		if currentBlockAnim then
			currentBlockAnim:Stop(0)
		end

		reactionAnim:Play(0.05, 1, 1)
		currentHitReactionAnim = reactionAnim

		-- Return to block idle after reaction
		task.delay(0.3, function()
			if state.isBlocking and animations.Block then
				animations.Block:Play(0.1)
				currentBlockAnim = animations.Block
			end
		end)
	end

	-- Check if block broken
	if state.blockHealth <= 0 then
		EndBlocking()

		-- Play block broken animation
		if animations.BlockBroken then
			animations.BlockBroken:Play(0.05, 1, 1)
		end

		-- Stun player
		ApplyStun(SETTINGS.Block.BreakStunDuration)

		-- Visual feedback
		VFXController.ScreenShake("BlockBroken")

		local flash = Instance.new("Part")
		flash.Size = Vector3.new(6, 6, 0.1)
		flash.Transparency = 0.3
		flash.Color = Color3.fromRGB(255, 0, 0)
		flash.Anchored = true
		flash.CanCollide = false
		flash.CFrame = rootPart.CFrame * CFrame.new(0, 0, -2)
		flash.Parent = workspace

		TweenService:Create(flash, TweenInfo.new(0.5), {
			Transparency = 1,
			Size = Vector3.new(10, 10, 0.1),
		}):Play()

		Debris:AddItem(flash, 1)
	end
end)

-- ========================================
-- HIT RESULT HANDLER
-- ========================================

HitResultEvent.OnClientEvent:Connect(function(hitData)
	local targetChar = hitData.targetChar
	local targetRoot = targetChar and targetChar:FindFirstChild("HumanoidRootPart")

	if not targetRoot then
		return
	end

	-- Create debug marker for hit target
	if SETTINGS.Debug.ShowTargets and targetChar ~= character then
		CreateTargetMarker(targetRoot)
	end

	-- Determine damage color
	local color = SETTINGS.VFX.DamageNumbers.NormalColor
	if hitData.wasPerfectBlock then
		color = SETTINGS.VFX.DamageNumbers.CriticalColor
	elseif hitData.wasBlocked then
		color = SETTINGS.VFX.DamageNumbers.BlockedColor
	elseif hitData.isFinisher then
		color = SETTINGS.VFX.DamageNumbers.FinisherColor
	elseif hitData.isHeavy then
		color = SETTINGS.VFX.DamageNumbers.HeavyColor
	end

	CreateDamageNumber(targetRoot.Position, hitData.damage, color, hitData.isFinisher or hitData.wasPerfectBlock)

	-- Play VFX
	if hitData.wasBlocked then
		VFXController.PlayBlockVFX(targetRoot, hitData.wasPerfectBlock)
	else
		VFXController.PlayHitVFX(targetChar, hitData.isHeavy, hitData.isFinisher)
	end

	-- If WE got hit
	if targetChar == character then
		-- Play hit reaction if not blocking
		if not state.isBlocking then
			StopAllHitReactionAnims()
			local reactionNum = math.random(1, 5)
			local reactionAnim = animations["HitReaction" .. reactionNum]

			if reactionAnim then
				reactionAnim:Play(0.05, 1, 1)
				currentHitReactionAnim = reactionAnim
			end
		end

		-- Screen shake
		if hitData.wasBlocked then
			VFXController.ScreenShake("Blocked")
		elseif hitData.isFinisher then
			VFXController.ScreenShake("Finisher")
		elseif hitData.isHeavy then
			VFXController.ScreenShake("Heavy")
		else
			VFXController.ScreenShake("Normal")
		end
	end

	-- Play hit sound for spectators
	if targetChar ~= character then
		local soundId
		if hitData.wasBlocked then
			soundId = SETTINGS.Audio.BlockHit
		else
			soundId = SETTINGS.Audio["M" .. hitData.combo .. "Sound"]
		end

		if soundId and soundId ~= "" then
			PlayHitSound(soundId, targetRoot.Position)
		end
	end

	-- Debug logging
	if SETTINGS.Debug.LogHits then
		print(
			string.format(
				"💥 Hit! Damage: %d | Beast: %s | Heavy: %s | Finisher: %s",
				hitData.damage,
				tostring(hitData.isBeastMode),
				tostring(hitData.isHeavy),
				tostring(hitData.isFinisher)
			)
		)
	end
end)

-- Block feedback (perfect block flash)
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

-- ========================================
-- CLEANUP
-- ========================================

character.Humanoid.Died:Connect(function()
	state.isAttacking = false
	state.isBlocking = false
	state.isStunned = false
	state.currentCombo = 0
	state.blockHealth = SETTINGS.Block.MaxHealth
	state.isBeastMode = false

	if activeBlockVFX then
		activeBlockVFX:Destroy()
		activeBlockVFX = nil
	end

	if leftArmAura then
		leftArmAura:Destroy()
		leftArmAura = nil
	end

	if rightArmAura then
		rightArmAura:Destroy()
		rightArmAura = nil
	end

	if debugHitboxPart then
		debugHitboxPart:Destroy()
		debugHitboxPart = nil
	end

	ClearTargetMarkers()

	if state.comboResetTask then
		task.cancel(state.comboResetTask)
		state.comboResetTask = nil
	end

	if state.stunTask then
		task.cancel(state.stunTask)
		state.stunTask = nil
	end

	if state.beastModeTask then
		task.cancel(state.beastModeTask)
		state.beastModeTask = nil
	end
end)

print("started")
