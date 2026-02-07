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
local DamageEvent = RemoteFolder:WaitForChild("DamageRequest")

local CombatVFX = ReplicatedStorage.Assets.Combat:WaitForChild("CombatVFX")
local PunchVFX = CombatVFX:WaitForChild("Punch vfx")
local BlockVFX = CombatVFX:WaitForChild("block vfx")

local isAttacking = false
local isDashing = false
local isBlocking = false
local currentCombo = 0
local lastDash = 0
local lastAttackTime = 0
local attackEndTime = 0
local comboResetTimer = nil
local canRequestAttack = true

local animations = {}
local currentAttackTrack = nil
local animator = nil

local function LoadAnimations()
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local anim1 = Instance.new("Animation")
	anim1.AnimationId = SETTINGS.ANIM_M1
	animations.M1 = animator:LoadAnimation(anim1)

	local anim2 = Instance.new("Animation")
	anim2.AnimationId = SETTINGS.ANIM_M2
	animations.M2 = animator:LoadAnimation(anim2)

	local anim3 = Instance.new("Animation")
	anim3.AnimationId = SETTINGS.ANIM_M3
	animations.M3 = animator:LoadAnimation(anim3)

	local anim4 = Instance.new("Animation")
	anim4.AnimationId = SETTINGS.ANIM_M4
	animations.M4 = animator:LoadAnimation(anim4)

	local frontDash = Instance.new("Animation")
	frontDash.AnimationId = SETTINGS.ANIM_FRONTDASH
	animations.FrontDash = animator:LoadAnimation(frontDash)

	local run = Instance.new("Animation")
	run.AnimationId = SETTINGS.ANIM_RUN
	animations.Run = animator:LoadAnimation(run)

	local sideDashLeft = Instance.new("Animation")
	sideDashLeft.AnimationId = SETTINGS.ANIM_SIDEDASHLEFT
	animations.SideDashLeft = animator:LoadAnimation(sideDashLeft)

	local sideDashRight = Instance.new("Animation")
	sideDashRight.AnimationId = SETTINGS.ANIM_SIDEDASHRIGHT
	animations.SideDashRight = animator:LoadAnimation(sideDashRight)

	local walk = Instance.new("Animation")
	walk.AnimationId = SETTINGS.ANIM_WALK
	animations.Walk = animator:LoadAnimation(walk)

	local backDash = Instance.new("Animation")
	backDash.AnimationId = SETTINGS.ANIM_BACKDASH
	animations.BackDash = animator:LoadAnimation(backDash)
end

LoadAnimations()

local isMoving = false
local currentMoveAnim = nil
local runSpeedFixed = false

RunService.RenderStepped:Connect(function()
	if not isDashing and not runSpeedFixed then
		if humanoid.WalkSpeed ~= SETTINGS.NORMAL_MOVE_SPEED and not isBlocking then
			humanoid.WalkSpeed = SETTINGS.NORMAL_MOVE_SPEED
			runSpeedFixed = true
		end
	end

	if isDashing or isAttacking or isBlocking then
		if currentMoveAnim then
			currentMoveAnim:Stop()
			isMoving = false
		end
		return
	end

	local velocity = rootPart.Velocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if horizontalSpeed > 2 then
		if not isMoving then
			isMoving = true
			if horizontalSpeed > 20 then
				currentMoveAnim = animations.Run
			else
				currentMoveAnim = animations.Walk
			end
			if currentMoveAnim then
				currentMoveAnim:Play()
			end
		end
	else
		if isMoving then
			isMoving = false
			if currentMoveAnim then
				currentMoveAnim:Stop()
			end
		end
	end
end)

local function CreateComboUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ComboUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local comboLabel = Instance.new("TextLabel")
	comboLabel.Name = "ComboLabel"
	comboLabel.Size = UDim2.new(0, 250, 0, 60)
	comboLabel.Position = UDim2.new(0.5, -125, 0.65, 0)
	comboLabel.BackgroundTransparency = 1
	comboLabel.Font = Enum.Font.GothamBold
	comboLabel.TextSize = 42
	comboLabel.TextColor3 = Color3.new(1, 1, 1)
	comboLabel.TextStrokeTransparency = 0.3
	comboLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	comboLabel.Text = ""
	comboLabel.Visible = false
	comboLabel.Parent = screenGui

	return comboLabel
end

local comboLabel = CreateComboUI()

local punchAura = nil
local function CreatePunchAura()
	if PunchVFX:FindFirstChild("constant punch vfx") then
		punchAura = PunchVFX["constant punch vfx"]:Clone()
		local rightArm = character:FindFirstChild("Right Arm")
		if rightArm then
			punchAura.Parent = rightArm
		end
	end
end

CreatePunchAura()

local function PerformDash(direction)
	if isDashing or isAttacking then
		return
	end

	local currentTime = tick()
	if currentTime - lastDash < SETTINGS.DASH_COOLDOWN then
		return
	end

	isDashing = true
	lastDash = currentTime
	runSpeedFixed = false

	if currentMoveAnim then
		currentMoveAnim:Stop()
	end

	local dashAnim
	if direction == "Forward" then
		dashAnim = animations.FrontDash
	elseif direction == "Back" then
		dashAnim = animations.BackDash
	elseif direction == "Left" then
		dashAnim = animations.SideDashLeft
	elseif direction == "Right" then
		dashAnim = animations.SideDashRight
	end

	if dashAnim then
		dashAnim:Play()
	end

	local dashDirection = Vector3.new(0, 0, 0)

	if direction == "Forward" then
		dashDirection = rootPart.CFrame.LookVector
	elseif direction == "Back" then
		dashDirection = -rootPart.CFrame.LookVector
	elseif direction == "Left" then
		dashDirection = -rootPart.CFrame.RightVector
	elseif direction == "Right" then
		dashDirection = rootPart.CFrame.RightVector
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	bodyVelocity.Velocity = dashDirection * SETTINGS.DASH_SPEED
	bodyVelocity.Parent = rootPart

	task.delay(SETTINGS.DASH_DURATION, function()
		if bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end

		rootPart.AssemblyLinearVelocity = Vector3.zero

		isDashing = false
		if dashAnim then
			dashAnim:Stop()
		end

		if not isBlocking then
			humanoid.WalkSpeed = SETTINGS.NORMAL_MOVE_SPEED
			runSpeedFixed = true
		end
	end)
end

local function GetHitFrame(combo)
	local hitFrames = {
		[1] = 0.4,
		[2] = 0.4,
		[3] = 0.45,
		[4] = 0.5,
	}

	local animDuration
	if combo == 1 then
		animDuration = SETTINGS.ANIM_DURATION_M1
	elseif combo == 2 then
		animDuration = SETTINGS.ANIM_DURATION_M2
	elseif combo == 3 then
		animDuration = SETTINGS.ANIM_DURATION_M3
	elseif combo == 4 then
		animDuration = SETTINGS.ANIM_DURATION_M4
	else
		animDuration = SETTINGS.ANIM_DURATION_M1
	end

	local hitFrame = hitFrames[combo] or 0.4
	return animDuration * hitFrame
end

local function PlayAttackAnimation(combo)
	if isAttacking then
		return false
	end

	isAttacking = true
	canRequestAttack = true

	for _, track in pairs(humanoid:GetPlayingAnimationTracks()) do
		local animId = track.Animation.AnimationId
		if
			animId == SETTINGS.ANIM_M1
			or animId == SETTINGS.ANIM_M2
			or animId == SETTINGS.ANIM_M3
			or animId == SETTINGS.ANIM_M4
		then
			track:Stop(0)
		end
	end

	if currentAttackTrack then
		currentAttackTrack:Stop(0)
		currentAttackTrack = nil
	end

	local anim
	local animDuration

	if combo == 1 then
		anim = animations.M1
		animDuration = SETTINGS.ANIM_DURATION_M1
	elseif combo == 2 then
		anim = animations.M2
		animDuration = SETTINGS.ANIM_DURATION_M2
	elseif combo == 3 then
		anim = animations.M3
		animDuration = SETTINGS.ANIM_DURATION_M3
	elseif combo == 4 then
		anim = animations.M4
		animDuration = SETTINGS.ANIM_DURATION_M4
	else
		anim = animations.M1
		animDuration = SETTINGS.ANIM_DURATION_M1
	end

	if anim then
		currentAttackTrack = anim
		anim:Play(0.05, 1, 1)
	end

	lastAttackTime = tick()
	attackEndTime = lastAttackTime + animDuration

	local hitFrameTime = GetHitFrame(combo)

	task.delay(hitFrameTime, function()
		if canRequestAttack then
			DamageEvent:FireServer(combo)
			canRequestAttack = false
		end
	end)

	task.wait(animDuration)

	isAttacking = false
	currentAttackTrack = nil

	return true
end

local function ShowHitEffect(targetCharacter, wasBlocked)
	local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
	local targetTorso = targetCharacter:FindFirstChild("Torso") or targetCharacter:FindFirstChild("UpperTorso")

	if not targetRoot then
		return
	end

	local vfxAttachPoint = targetTorso or targetRoot

	if wasBlocked then
		local blockEffect = BlockVFX:Clone()
		blockEffect.Parent = vfxAttachPoint

		if blockEffect:IsA("Model") then
			blockEffect:PivotTo(vfxAttachPoint.CFrame)
		elseif blockEffect:IsA("Part") or blockEffect:IsA("MeshPart") then
			blockEffect.CFrame = vfxAttachPoint.CFrame
		end

		for _, obj in pairs(blockEffect:GetDescendants()) do
			if obj:IsA("ParticleEmitter") then
				obj:Emit(obj:GetAttribute("EmitCount") or 25)
			end
		end

		Debris:AddItem(blockEffect, 2.0)
	else
		local punchEffect = PunchVFX:Clone()
		punchEffect.Parent = vfxAttachPoint

		if punchEffect:IsA("Model") then
			punchEffect:PivotTo(vfxAttachPoint.CFrame)
		elseif punchEffect:IsA("Part") or punchEffect:IsA("MeshPart") then
			punchEffect.CFrame = vfxAttachPoint.CFrame
		end

		for _, obj in pairs(punchEffect:GetDescendants()) do
			if obj:IsA("ParticleEmitter") then
				local emitCount = obj:GetAttribute("EmitCount") or 40
				obj:Emit(emitCount)

				obj.Enabled = true
				task.delay(0.3, function()
					if obj then
						obj.Enabled = false
					end
				end)
			elseif obj:IsA("Beam") then
				obj.Enabled = true
				task.delay(0.4, function()
					if obj then
						obj.Enabled = false
					end
				end)
			end
		end

		Debris:AddItem(punchEffect, 1.5)
	end

	local sound = Instance.new("Sound")
	sound.SoundId = wasBlocked and "rbxassetid://9114487369" or "rbxassetid://72142112079276"
	sound.Volume = 0.6
	sound.Parent = vfxAttachPoint
	sound:Play()
	Debris:AddItem(sound, 2)

	if targetCharacter == character then
		local shakeMagnitude = wasBlocked and 0.2 or 0.5
		local shakeTime = 0.1

		local camera = workspace.CurrentCamera
		local originalCFrame = camera.CFrame

		task.spawn(function()
			local elapsed = 0
			while elapsed < shakeTime do
				local shake = Vector3.new(
					math.random(-100, 100) / 100 * shakeMagnitude,
					math.random(-100, 100) / 100 * shakeMagnitude,
					math.random(-100, 100) / 100 * shakeMagnitude
				)
				camera.CFrame = camera.CFrame * CFrame.new(shake)
				elapsed += task.wait()
			end
		end)
	end
end

local function UpdateCombo(combo)
	currentCombo = combo

	if combo > 0 then
		comboLabel.Text = combo .. " HIT" .. (combo > 1 and "S" or "") .. "!"

		if combo >= 4 then
			comboLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
		elseif combo >= 3 then
			comboLabel.TextColor3 = Color3.fromRGB(255, 140, 0)
		elseif combo >= 2 then
			comboLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
		else
			comboLabel.TextColor3 = Color3.new(1, 1, 1)
		end

		comboLabel.Visible = true

		comboLabel.Size = UDim2.new(0, 280, 0, 70)
		TweenService:Create(comboLabel, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 250, 0, 60),
		}):Play()

		if comboResetTimer then
			task.cancel(comboResetTimer)
		end

		comboResetTimer = task.delay(SETTINGS.COMBO_RESET_TIME, function()
			currentCombo = 0
			comboLabel.Visible = false
		end)
	else
		comboLabel.Visible = false
	end
end

local keysPressed = {
	W = false,
	A = false,
	S = false,
	D = false,
	Q = false,
	F = false,
}

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = true
	elseif input.KeyCode == Enum.KeyCode.Q then
		keysPressed.Q = true

		if not isDashing and not isAttacking and not isBlocking then
			if keysPressed.S then
				PerformDash("Back")
			elseif keysPressed.A then
				PerformDash("Left")
			elseif keysPressed.D then
				PerformDash("Right")
			else
				PerformDash("Forward")
			end
		end
	elseif input.KeyCode == Enum.KeyCode.F then
		if not isAttacking and not isDashing and not isBlocking then
			isBlocking = true
			humanoid.WalkSpeed = SETTINGS.BLOCK_MOVE_SPEED
			BlockEvent:FireServer(true)

			if BlockVFX then
				local blockEffect = BlockVFX:Clone()
				blockEffect.Name = "ActiveBlock"
				blockEffect.Parent = rootPart
			end
		end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local currentTime = tick()

		if isAttacking then
			return
		end

		if isDashing or isBlocking then
			return
		end

		local timeSinceLastAttack = currentTime - lastAttackTime
		local minimumDelay = SETTINGS.MINIMUM_ATTACK_DELAY

		if timeSinceLastAttack < minimumDelay then
			return
		end

		M1Event:FireServer()
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
	elseif input.KeyCode == Enum.KeyCode.Q then
		keysPressed.Q = false
	elseif input.KeyCode == Enum.KeyCode.F then
		if isBlocking then
			isBlocking = false
			humanoid.WalkSpeed = SETTINGS.NORMAL_MOVE_SPEED
			BlockEvent:FireServer(false)

			local activeBlock = rootPart:FindFirstChild("ActiveBlock")
			if activeBlock then
				activeBlock:Destroy()
			end
		end
	end
end)

M1Event.OnClientEvent:Connect(function(serverCombo)
	local nextCombo = (currentCombo % SETTINGS.COMBO_MAX) + 1

	UpdateCombo(nextCombo)

	PlayAttackAnimation(nextCombo)
end)

DamageEvent.OnClientEvent:Connect(function(targetCharacter, hitSuccess, wasBlocked)
	if hitSuccess and targetCharacter then
		ShowHitEffect(targetCharacter, wasBlocked)
	end
end)

BlockEvent.OnClientEvent:Connect(function(eventType)
	if eventType == "blocked" then
		local blockFlash = Instance.new("Part")
		blockFlash.Size = Vector3.new(4, 4, 0.1)
		blockFlash.Transparency = 0.7
		blockFlash.Color = Color3.fromRGB(100, 200, 255)
		blockFlash.Anchored = true
		blockFlash.CanCollide = false
		blockFlash.CFrame = rootPart.CFrame * CFrame.new(0, 0, -2)
		blockFlash.Parent = workspace

		TweenService:Create(blockFlash, TweenInfo.new(0.3), {
			Transparency = 1,
			Size = Vector3.new(6, 6, 0.1),
		}):Play()

		Debris:AddItem(blockFlash, 0.5)
	end
end)

character.Humanoid.Died:Connect(function()
	if comboResetTimer then
		task.cancel(comboResetTimer)
	end
	isAttacking = false
	isDashing = false
	isBlocking = false
	currentCombo = 0
end)
