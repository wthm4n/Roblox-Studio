local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

local AbilitiesFolder = ReplicatedStorage.Modules.Combat:WaitForChild("Abilities")
local AbilityVFXFolder = ReplicatedStorage.Assets.Combat:WaitForChild("AbilityVFX")
local AbilityRemotes = ReplicatedStorage:WaitForChild("AbilityRemotes")
local UseAbilityEvent = AbilityRemotes:WaitForChild("UseAbility")
local AbilityResultEvent = AbilityRemotes:WaitForChild("AbilityResult")

local abilities = {}
local abilityModules = {}
local cooldowns = {}
local isUsingAbility = false

local animator = humanoid:FindFirstChildOfClass("Animator")
if not animator then
	animator = Instance.new("Animator")
	animator.Parent = humanoid
end

local abilityAnims = {}

local function CreateAbilityUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AbilityUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Name = "AbilityContainer"
	container.Size = UDim2.new(0, 400, 0, 80)
	container.Position = UDim2.new(0.5, -200, 0.9, -80)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	for i = 1, 4 do
		local slot = Instance.new("Frame")
		slot.Name = "Ability" .. i
		slot.Size = UDim2.new(0, 80, 0, 80)
		slot.Position = UDim2.new(0, (i - 1) * 100, 0, 0)
		slot.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		slot.BorderSizePixel = 0
		slot.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = slot

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.7, 0, 0.7, 0)
		icon.Position = UDim2.new(0.15, 0, 0.1, 0)
		icon.BackgroundTransparency = 1
		icon.Image = "rbxassetid://0"
		icon.Parent = slot

		local keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "KeyLabel"
		keyLabel.Size = UDim2.new(0.3, 0, 0.3, 0)
		keyLabel.Position = UDim2.new(0, 5, 0, 5)
		keyLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		keyLabel.BorderSizePixel = 0
		keyLabel.Text = tostring(i)
		keyLabel.Font = Enum.Font.GothamBold
		keyLabel.TextSize = 16
		keyLabel.TextColor3 = Color3.new(1, 1, 1)
		keyLabel.Parent = slot

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 5)
		keyCorner.Parent = keyLabel

		local cooldownOverlay = Instance.new("Frame")
		cooldownOverlay.Name = "CooldownOverlay"
		cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
		cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		cooldownOverlay.BackgroundTransparency = 0.7
		cooldownOverlay.BorderSizePixel = 0
		cooldownOverlay.Visible = false
		cooldownOverlay.Parent = slot

		local cooldownCorner = Instance.new("UICorner")
		cooldownCorner.CornerRadius = UDim.new(0, 10)
		cooldownCorner.Parent = cooldownOverlay

		local cooldownText = Instance.new("TextLabel")
		cooldownText.Name = "CooldownText"
		cooldownText.Size = UDim2.new(1, 0, 1, 0)
		cooldownText.BackgroundTransparency = 1
		cooldownText.Text = ""
		cooldownText.Font = Enum.Font.GothamBold
		cooldownText.TextSize = 24
		cooldownText.TextColor3 = Color3.new(1, 1, 1)
		cooldownText.TextStrokeTransparency = 0.5
		cooldownText.Parent = cooldownOverlay
	end

	return screenGui
end

local abilityUI = CreateAbilityUI()

local function LoadAbilities()
	local abilityCount = 0

	for _, moduleScript in ipairs(AbilitiesFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") and moduleScript.Name:match("^Ability%d") then
			local abilityNum = tonumber(moduleScript.Name:match("^Ability(%d)"))

			if abilityNum then
				local success, abilityModule = pcall(require, moduleScript)

				if success then
					abilityModules[abilityNum] = abilityModule
					abilities[abilityNum] = {
						Name = abilityModule.Name,
						Cooldown = abilityModule.Cooldown,
						Description = abilityModule.Description,
						Icon = abilityModule.Icon,
						AnimationId = abilityModule.AnimationId,
						Key = abilityNum,
					}

					if abilityModule.AnimationId and abilityModule.AnimationId ~= "" then
						local anim = Instance.new("Animation")
						anim.AnimationId = abilityModule.AnimationId
						abilityAnims[abilityNum] = animator:LoadAnimation(anim)
					end

					local slot = abilityUI.AbilityContainer:FindFirstChild("Ability" .. abilityNum)
					if slot and abilityModule.Icon and abilityModule.Icon ~= "" then
						slot.Icon.Image = abilityModule.Icon
					end

					cooldowns[abilityNum] = 0
					abilityCount = abilityCount + 1
				end
			end
		end
	end
end

LoadAbilities()

local function UpdateCooldownUI(abilityIndex, timeLeft)
	local slot = abilityUI.AbilityContainer:FindFirstChild("Ability" .. abilityIndex)
	if not slot then
		return
	end

	local overlay = slot.CooldownOverlay
	local text = overlay.CooldownText

	if timeLeft > 0 then
		overlay.Visible = true
		text.Text = string.format("%.1f", timeLeft)
	else
		overlay.Visible = false
		text.Text = ""
	end
end

local function StartCooldown(abilityIndex, duration)
	cooldowns[abilityIndex] = duration

	local slot = abilityUI.AbilityContainer:FindFirstChild("Ability" .. abilityIndex)
	if slot then
		TweenService:Create(slot, TweenInfo.new(0.1), {
			BackgroundColor3 = Color3.fromRGB(80, 80, 80),
		}):Play()

		task.delay(0.1, function()
			TweenService:Create(slot, TweenInfo.new(0.2), {
				BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			}):Play()
		end)
	end

	task.spawn(function()
		while cooldowns[abilityIndex] > 0 do
			task.wait(0.1)
			cooldowns[abilityIndex] = math.max(0, cooldowns[abilityIndex] - 0.1)
			UpdateCooldownUI(abilityIndex, cooldowns[abilityIndex])
		end
	end)
end

local function IsAbilityReady(abilityIndex)
	if not abilities[abilityIndex] then
		return false
	end
	if cooldowns[abilityIndex] > 0 then
		return false
	end
	if isUsingAbility then
		return false
	end
	return true
end

local function UseAbility(abilityIndex)
	if not IsAbilityReady(abilityIndex) then
		return
	end

	local ability = abilities[abilityIndex]

	isUsingAbility = true

	local anim = abilityAnims[abilityIndex]
	if anim then
		anim:Play()
	end

	UseAbilityEvent:FireServer(abilityIndex)
end

AbilityResultEvent.OnClientEvent:Connect(function(abilityIndex, success, targets)
	local ability = abilities[abilityIndex]
	local abilityModule = abilityModules[abilityIndex]

	if success and abilityModule then
		StartCooldown(abilityIndex, ability.Cooldown)

		local vfx = AbilityVFXFolder:FindFirstChild(abilityModule.VFXName)

		if vfx and abilityModule.PlayVFX then
			abilityModule:PlayVFX(rootPart, vfx)
		end

		if targets then
			for _, targetChar in ipairs(targets) do
				local hitEffect = Instance.new("Part")
				hitEffect.Size = Vector3.new(4, 4, 0.2)
				hitEffect.Transparency = 0.5
				hitEffect.Color = Color3.fromRGB(255, 200, 0)
				hitEffect.Anchored = true
				hitEffect.CanCollide = false

				local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
				if targetRoot then
					hitEffect.CFrame = targetRoot.CFrame
					hitEffect.Parent = workspace

					TweenService:Create(hitEffect, TweenInfo.new(0.5), {
						Transparency = 1,
						Size = Vector3.new(6, 6, 0.2),
					}):Play()

					game:GetService("Debris"):AddItem(hitEffect, 0.5)
				end
			end
		end
	end

	local anim = abilityAnims[abilityIndex]
	if anim and anim.IsPlaying then
		task.wait(anim.Length)
	else
		task.wait(0.5)
	end

	isUsingAbility = false
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local keyMap = {
		[Enum.KeyCode.One] = 1,
		[Enum.KeyCode.Two] = 2,
		[Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4,
	}

	local abilityIndex = keyMap[input.KeyCode]
	if abilityIndex then
		UseAbility(abilityIndex)
	end
end)

task.spawn(function()
	while true do
		for i = 1, 4 do
			UpdateCooldownUI(i, cooldowns[i])
		end
		task.wait(0.1)
	end
end)
