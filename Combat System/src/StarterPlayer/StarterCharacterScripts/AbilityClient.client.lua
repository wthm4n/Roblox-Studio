--[[
	AbilityClient.lua
	
	Client-side ability system.
	Handles input, UI, VFX, and cooldown display.
	
	Author: [Your Name]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Services
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")

-- Folders
local AbilitiesFolder = ReplicatedStorage.Modules.Combat:WaitForChild("Abilities")
local AbilityVFXFolder = ReplicatedStorage.Assets.Combat:WaitForChild("AbilityVFX")
local AbilityRemotes = ReplicatedStorage:WaitForChild("AbilityRemotes")

-- Remotes
local UseAbilityEvent = AbilityRemotes:WaitForChild("UseAbility")
local AbilityResultEvent = AbilityRemotes:WaitForChild("AbilityResult")

-- ========================================
-- STATE
-- ========================================

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

-- ========================================
-- UI CREATION
-- ========================================

local function CreateAbilityUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AbilityUI"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local container = Instance.new("Frame")
	container.Name = "AbilityContainer"
	container.Size = UDim2.new(0, 420, 0, 90)
	container.Position = UDim2.new(0.5, -210, 0.88, -90)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 15)
	layout.Parent = container

	for i = 1, 4 do
		local slot = Instance.new("Frame")
		slot.Name = "Ability" .. i
		slot.Size = UDim2.new(0, 85, 0, 85)
		slot.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
		slot.BorderSizePixel = 0
		slot.Parent = container

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = slot

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(80, 80, 80)
		stroke.Thickness = 2
		stroke.Transparency = 0.3
		stroke.Parent = slot

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0.65, 0, 0.65, 0)
		icon.Position = UDim2.new(0.175, 0, 0.125, 0)
		icon.BackgroundTransparency = 1
		icon.Image = "rbxassetid://0"
		icon.ImageColor3 = Color3.fromRGB(255, 255, 255)
		icon.Parent = slot

		local keyLabel = Instance.new("TextLabel")
		keyLabel.Name = "KeyLabel"
		keyLabel.Size = UDim2.new(0.28, 0, 0.28, 0)
		keyLabel.Position = UDim2.new(0.06, 0, 0.06, 0)
		keyLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		keyLabel.BorderSizePixel = 0
		keyLabel.Text = tostring(i)
		keyLabel.Font = Enum.Font.GothamBold
		keyLabel.TextSize = 18
		keyLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		keyLabel.Parent = slot

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 6)
		keyCorner.Parent = keyLabel

		local cooldownOverlay = Instance.new("Frame")
		cooldownOverlay.Name = "CooldownOverlay"
		cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
		cooldownOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		cooldownOverlay.BackgroundTransparency = 0.65
		cooldownOverlay.BorderSizePixel = 0
		cooldownOverlay.Visible = false
		cooldownOverlay.ZIndex = 2
		cooldownOverlay.Parent = slot

		local cooldownCorner = Instance.new("UICorner")
		cooldownCorner.CornerRadius = UDim.new(0, 12)
		cooldownCorner.Parent = cooldownOverlay

		local cooldownText = Instance.new("TextLabel")
		cooldownText.Name = "CooldownText"
		cooldownText.Size = UDim2.new(1, 0, 1, 0)
		cooldownText.BackgroundTransparency = 1
		cooldownText.Text = ""
		cooldownText.Font = Enum.Font.GothamBold
		cooldownText.TextSize = 28
		cooldownText.TextColor3 = Color3.new(1, 1, 1)
		cooldownText.TextStrokeTransparency = 0.4
		cooldownText.ZIndex = 3
		cooldownText.Parent = cooldownOverlay

		local abilityName = Instance.new("TextLabel")
		abilityName.Name = "AbilityName"
		abilityName.Size = UDim2.new(1, 0, 0.2, 0)
		abilityName.Position = UDim2.new(0, 0, 1, 5)
		abilityName.BackgroundTransparency = 1
		abilityName.Text = ""
		abilityName.Font = Enum.Font.Gotham
		abilityName.TextSize = 12
		abilityName.TextColor3 = Color3.fromRGB(200, 200, 200)
		abilityName.TextTruncate = Enum.TextTruncate.AtEnd
		abilityName.Parent = slot
	end

	return screenGui
end

local abilityUI = CreateAbilityUI()

-- ========================================
-- ABILITY LOADING
-- ========================================

local function LoadAbilities()
	for _, moduleScript in AbilitiesFolder:GetChildren() do
		if moduleScript:IsA("ModuleScript") and moduleScript.Name:match("^Ability%d") then
			local abilityNum = tonumber(moduleScript.Name:match("^Ability(%d)"))

			if abilityNum and abilityNum <= 4 then -- Only load first 4
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

					-- Load animation
					if abilityModule.AnimationId and abilityModule.AnimationId ~= "" then
						local anim = Instance.new("Animation")
						anim.AnimationId = abilityModule.AnimationId
						abilityAnims[abilityNum] = animator:LoadAnimation(anim)
					end

					-- Update UI
					local slot = abilityUI.AbilityContainer:FindFirstChild("Ability" .. abilityNum)
					if slot then
						if abilityModule.Icon and abilityModule.Icon ~= "" then
							slot.Icon.Image = abilityModule.Icon
						end
						slot.AbilityName.Text = abilityModule.Name
					end

					cooldowns[abilityNum] = 0

					print("✅ Loaded ability:", abilityModule.Name)
				else
					warn("❌ Failed to load ability:", moduleScript.Name)
				end
			end
		end
	end
end

LoadAbilities()

-- ========================================
-- COOLDOWN UI
-- ========================================

local function UpdateCooldownUI(abilityIndex: number, timeLeft: number)
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

local function StartCooldown(abilityIndex: number, duration: number)
	cooldowns[abilityIndex] = duration

	-- Visual feedback
	local slot = abilityUI.AbilityContainer:FindFirstChild("Ability" .. abilityIndex)
	if slot then
		TweenService:Create(slot, TweenInfo.new(0.1), { BackgroundColor3 = Color3.fromRGB(70, 70, 70) }):Play()

		task.delay(0.1, function()
			TweenService:Create(slot, TweenInfo.new(0.2), { BackgroundColor3 = Color3.fromRGB(30, 30, 30) }):Play()
		end)
	end

	-- Countdown
	task.spawn(function()
		while cooldowns[abilityIndex] > 0 do
			task.wait(0.1)
			cooldowns[abilityIndex] = math.max(0, cooldowns[abilityIndex] - 0.1)
			UpdateCooldownUI(abilityIndex, cooldowns[abilityIndex])
		end
	end)
end

-- ========================================
-- ABILITY USAGE
-- ========================================

local function IsAbilityReady(abilityIndex: number): boolean
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

local function UseAbility(abilityIndex: number)
	if not IsAbilityReady(abilityIndex) then
		return
	end

	isUsingAbility = true

	-- Play animation
	local anim = abilityAnims[abilityIndex]
	if anim then
		anim:Play()
	end

	-- Request from server
	UseAbilityEvent:FireServer(abilityIndex)
end

-- ========================================
-- SERVER RESPONSE
-- ========================================

AbilityResultEvent.OnClientEvent:Connect(function(abilityIndex: number, success: boolean, targets)
	local ability = abilities[abilityIndex]
	local abilityModule = abilityModules[abilityIndex]

	if success and abilityModule then
		-- Start cooldown
		StartCooldown(abilityIndex, ability.Cooldown)

		-- Play VFX
		local vfx = AbilityVFXFolder:FindFirstChild(abilityModule.VFXName)
		if vfx and abilityModule.PlayVFX then
			pcall(function()
				abilityModule:PlayVFX(rootPart, vfx, targets)
			end)
		end
	end

	-- Wait for animation to finish
	local anim = abilityAnims[abilityIndex]
	if anim and anim.IsPlaying then
		task.wait(anim.Length * 0.8) -- 80% of animation
	else
		task.wait(0.5)
	end

	isUsingAbility = false
end)

-- ========================================
-- INPUT HANDLING
-- ========================================

local keyMap = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
}

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	local abilityIndex = keyMap[input.KeyCode]
	if abilityIndex then
		UseAbility(abilityIndex)
	end
end)

-- ========================================
-- UI UPDATE LOOP
-- ========================================

task.spawn(function()
	while true do
		for i = 1, 4 do
			UpdateCooldownUI(i, cooldowns[i])
		end
		task.wait(0.1)
	end
end)

print("✅ AbilityClient initialized")
