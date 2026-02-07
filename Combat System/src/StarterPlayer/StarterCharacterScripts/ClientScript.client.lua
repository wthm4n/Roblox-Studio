--[[
	CLIENT SCRIPT
	
	Place this in: StarterPlayer > StarterCharacterScripts
	
	This initializes the combat system for the local player.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

-- Wait for combat system to be replicated
local CombatInitializer = ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatInitializer")

-- Initialize combat
CombatInitializer = require(CombatInitializer)
CombatInitializer.SetupClient()

-- Get our combat instance
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local combatInstance = CombatInitializer.GetCombatInstance(character)
local core = combatInstance.Core

--[[
	INPUT HANDLING
	Map keys to combat actions
]]

-- M1 (Left Click)
local m1Debounce = false

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	-- M1 Attack
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if not m1Debounce then
			m1Debounce = true
			core:QueueInput("M1", {
				ComboIndex = core.ComboCounter + 1
			})
			
			task.wait(0.1) -- Prevent spam
			m1Debounce = false
		end
	end
	
	-- Dash (Q = Front, E = Back)
	if input.KeyCode == Enum.KeyCode.Q then
		core:QueueInput("Dash", { Direction = "Front" })
	elseif input.KeyCode == Enum.KeyCode.E then
		core:QueueInput("Dash", { Direction = "Back" })
	end
	
	-- Example ability (R key)
	if input.KeyCode == Enum.KeyCode.R then
		core:QueueInput("Ability", { AbilityName = "FireBlast" })
	end
	
	-- Debug toggle (F1)
	if input.KeyCode == Enum.KeyCode.F1 then
		combatInstance.HitDetection:SetDebugMode(
			not combatInstance.HitDetection.DebugMode
		)
		print("Hitbox Debug:", combatInstance.HitDetection.DebugMode)
	end
end)

--[[
	VISUAL FEEDBACK
	Listen to combat events and play effects
]]

core.Events.HitConfirmed.Event:Connect(function(hitData)
	-- Play hit sound
	local hitSound = Instance.new("Sound")
	hitSound.SoundId = "rbxassetid://9125402735" -- Hit sound
	hitSound.Volume = 0.5
	hitSound.Parent = character.HumanoidRootPart
	hitSound:Play()
	hitSound.Ended:Connect(function()
		hitSound:Destroy()
	end)
	
	-- Could spawn hit particles here
end)

core.Events.DamageTaken.Event:Connect(function(damageData)
	-- Flash screen red or something
	print("Took", damageData.Damage, "damage!")
end)

print("Combat system initialized for", player.Name)
