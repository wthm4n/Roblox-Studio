--[[
	CombatClient.lua
	
	Professional client-side combat system inspired by TSB.
	Features: Sprint, M1 combos, heavy attacks, damage numbers, VFX.
	
	Author: [Your Name]
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

local SETTINGS = require(ReplicatedStorage.Modules.Combat:WaitForChild("CombatSettings"))
local RemoteFolder = ReplicatedStorage:WaitForChild("CombatRemotes")
local M1Event = RemoteFolder:WaitForChild("M1Attack")
local BlockEvent = RemoteFolder:WaitForChild("Block")
local HitEvent = RemoteFolder:WaitForChild("Hit")

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
}

local animations = {}
local animator = nil

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

	-- Position in world
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = workspace.Terrain -- lightweight, perfect for world-space UI

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
	hitVfx.Parent = workspace

	-- R6 chest-level offset
	local offset = CFrame.new(0, 1, -0.6)

	if hitVfx:IsA("Model") then
		hitVfx:PivotTo(hrp.CFrame * offset)
	else
		hitVfx.CFrame = hrp.CFrame * offset
	end

	-- Emit particles
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
	blockEffect.Parent = targetRoot

	if blockEffect:IsA("Model") then
		blockEffect:PivotTo(targetRoot.CFrame)
	else
		blockEffect.CFrame = targetRoot.CFrame
	end

	-- Emit particles
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

		-- Enable particles
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
		-- Disable particles
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

	local camera = workspace.CurrentCamera
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

	-- Movement
	animations.Walk = load(SETTINGS.Animations.Walk)
	animations.Sprint = load(SETTINGS.Animations.Sprint)

	-- Dashing
	animations.FrontDash = load(SETTINGS.Animations.FrontDash)
	animations.BackDash = load(SETTINGS.Animations.BackDash)
	animations.SideDashLeft = load(SETTINGS.Animations.SideDashLeft)
	animations.SideDashRight = load(SETTINGS.Animations.SideDashRight)

	-- M1 Combo
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

	-- Don't play movement anims while dashing or attacking
	if state.isDashing or state.isAttacking or state.isBlocking then
		if currentMoveAnim then
			currentMoveAnim:Stop()
			currentMoveAnim = nil
		end
		return
	end

	-- Determine which animation to play
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
-- DASH SYSTEM
-- ========================================

local keysPressed = { W = false, A = false, S = false, D = false }

local function PerformDash(direction: string)
	if state.isDashing or state.isAttacking then
		return
	end

	local currentTime = tick()
	if currentTime - state.lastDash < SETTINGS.Dash.Cooldown then
		return
	end

	state.isDashing = true
	state.lastDash = currentTime

	-- Stop movement animation
	if currentMoveAnim then
		currentMoveAnim:Stop()
	end

	-- Play dash animation
	local dashAnim = animations[direction .. "Dash"]
	if dashAnim then
		dashAnim:Play()
	end

	-- Calculate direction
	local dashDir = Vector3.zero
	if direction == "Front" then
		dashDir = rootPart.CFrame.LookVector
	elseif direction == "Back" then
		dashDir = -rootPart.CFrame.LookVector
	elseif direction == "SideLeft" then
		dashDir = -rootPart.CFrame.RightVector
	elseif direction == "SideRight" then
		dashDir = rootPart.CFrame.RightVector
	end

	-- Apply dash velocity
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.Velocity = dashDir * SETTINGS.Dash.Speed
	bodyVelocity.Parent = rootPart

	task.delay(SETTINGS.Dash.Duration, function()
		if bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
		rootPart.AssemblyLinearVelocity = Vector3.zero
		state.isDashing = false

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

	-- Dash (Q key)
	if input.KeyCode == SETTINGS.Dash.Key then
		if keysPressed.S then
			PerformDash("Back")
		elseif keysPressed.A then
			PerformDash("SideLeft")
		elseif keysPressed.D then
			PerformDash("SideRight")
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

			-- Show block VFX
			activeBlockVFX = BlockVfx:Clone()
			activeBlockVFX.Name = "ActiveBlock"
			activeBlockVFX.Parent = rootPart

			-- Enable block particles
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

			-- Remove block VFX
			if activeBlockVFX then
				activeBlockVFX:Destroy()
				activeBlockVFX = nil
			end
		end
	end
end)

-- ========================================
-- M1 ATTACK SYSTEM
-- ========================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if state.isAttacking or state.isDashing or state.isBlocking then
			return
		end

		local currentTime = tick()
		if currentTime - state.lastAttack < SETTINGS.M1.AttackCooldown then
			return
		end

		state.lastAttack = currentTime
		M1Event:FireServer()
	end
end)

-- ========================================
-- SERVER EVENTS
-- ========================================

-- Play attack animation
M1Event.OnClientEvent:Connect(function(combo: number, isHeavy: boolean, isFinisher: boolean)
	state.isAttacking = true
	state.currentCombo = combo

	-- Play animation
	local animKey = "M" .. combo
	local anim = animations[animKey]
	if anim then
		anim:Play()
	end

	-- Get duration
	local animData = SETTINGS.Animations[animKey]
	local duration = animData and animData.Duration or 0.5

	-- Enable arm aura during attack
	VFXController.EnableArmAura()

	-- End attack
	task.delay(duration, function()
		state.isAttacking = false

		-- Disable aura if not sprinting
		if not isSprinting then
			VFXController.DisableArmAura()
		end
	end)
end)

-- Handle hit feedback
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

		-- Determine damage number color
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

		-- Play sound based on combo number
		local soundId
		if wasBlocked then
			soundId = SETTINGS.Audio.BlockHit
		else
			-- Play the specific M1 sound for this combo hit
			if combo == 1 then
				soundId = SETTINGS.Audio.M1Sound
			elseif combo == 2 then
				soundId = SETTINGS.Audio.M2Sound
			elseif combo == 3 then
				soundId = SETTINGS.Audio.M3Sound
			elseif combo == 4 then
				soundId = SETTINGS.Audio.M4Sound
			end
		end

		if soundId and soundId ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = soundId
			sound.Volume = SETTINGS.Audio.HitVolume
			sound.Parent = targetRoot
			sound:Play()
			Debris:AddItem(sound, 1)
		end

		-- Create damage number
		CreateDamageNumber(targetRoot.Position, damage, color, isFinisher or wasPerfectBlock)

		-- Play VFX
		if wasBlocked then
			VFXController.PlayBlockVFX(targetRoot, wasPerfectBlock)
		else
			VFXController.PlayHitVFX(targetChar, isHeavy, isFinisher)
		end

		-- Screen shake (only if it's our character getting hit)
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
		-- Flash effect
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
end)

print("✅ CombatClient initialized (TSB-style)")
