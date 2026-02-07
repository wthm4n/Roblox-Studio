--[[
	COMBAT INITIALIZER
	
	Sets up the combat system when a character spawns.
	
	SERVER: Creates authoritative Core
	CLIENT: Creates predictive Core
	
	This script should be in StarterPlayer > StarterCharacterScripts
	for client, and ServerScriptService for server.
]]

local CombatInitializer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Import modules
local CombatCore = require(ReplicatedStorage.Combat.CombatCore)
local HitDetection = require(ReplicatedStorage.Combat.HitDetection)
local MovementController = require(ReplicatedStorage.Combat.MovementController)
local AnimationController = require(ReplicatedStorage.Combat.AnimationController)
local CameraController = require(ReplicatedStorage.Combat.CameraController)
local NPCController = require(ReplicatedStorage.Combat.NPCController)
local CombatConfig = require(ReplicatedStorage.Combat.CombatConfig)

-- Registry of active cores
local ActiveCores = {}

--[[
	Initialize combat for a character
	@param character - The character model
	@param isServer - Whether running on server
	@param isNPC - Whether this is an NPC (optional)
	@param npcConfig - NPC behavior config (optional)
]]
function CombatInitializer.InitializeCharacter(character: Model, isServer: boolean, isNPC: boolean?, npcConfig: any?)
	-- Wait for character to be ready
	local humanoid = character:WaitForChild("Humanoid")
	local hrp = character:WaitForChild("HumanoidRootPart")

	if not humanoid or not hrp then
		warn("Character not ready for combat initialization")
		return
	end

	-- Create Core
	local core = CombatCore.new(character, isServer)

	-- Override Core's GetActionConfig to use CombatConfig
	core.GetM1Config = function(self, comboIndex)
		return CombatConfig.GetM1Config(comboIndex)
	end

	core.GetDashConfig = function(self, direction)
		return CombatConfig.GetDashConfig(direction)
	end

	core.GetAbilityConfig = function(self, abilityName)
		return CombatConfig.GetAbilityConfig(abilityName)
	end

	-- Initialize subsystems
	local hitDetection = HitDetection.new(core)

	local isLocalPlayer = false
	if not isServer and not isNPC then
		local player = Players.LocalPlayer
		if player and player.Character == character then
			isLocalPlayer = true
		end
	end

	local movementController = MovementController.new(core, isLocalPlayer)

	local animationController = AnimationController.new(core, {
		AnimationIds = CombatConfig.AnimationIds,
		M1Animations = { "M1_1", "M1_2", "M1_3", "M1_4" },
		DashAnimations = {
			Front = "DashFront",
			Back = "DashBack",
			Left = "DashLeft",
			Right = "DashRight",
		},
	})

	-- Camera controller (local player only, not NPCs)
	local cameraController = nil
	if not isServer and isLocalPlayer then
		cameraController = CameraController.new(core)
	end

	-- Store references
	local combatInstance = {
		Core = core,
		HitDetection = hitDetection,
		MovementController = movementController,
		AnimationController = animationController,
		CameraController = cameraController,
	}

	-- NPC Controller (server-side only)
	if isServer and isNPC then
		combatInstance.NPCController = NPCController.new(combatInstance, npcConfig)
	end

	-- Register
	ActiveCores[character] = combatInstance

	-- Cleanup on death
	humanoid.Died:Connect(function()
		CombatInitializer.CleanupCharacter(character)
	end)

	return combatInstance
end

--[[
	Cleanup combat system
]]
function CombatInitializer.CleanupCharacter(character: Model)
	local combatInstance = ActiveCores[character]

	if combatInstance then
		combatInstance.Core:Destroy()
		combatInstance.HitDetection:Destroy()
		combatInstance.MovementController:Destroy()
		combatInstance.AnimationController:Destroy()

		if combatInstance.CameraController then
			combatInstance.CameraController:Destroy()
		end

		if combatInstance.NPCController then
			combatInstance.NPCController:Destroy()
		end

		ActiveCores[character] = nil
	end
end

--[[
	Get combat instance for a character
]]
function CombatInitializer.GetCombatInstance(character: Model)
	return ActiveCores[character]
end

--[[
	CLIENT SETUP
	Call this from a LocalScript in StarterCharacterScripts
]]
function CombatInitializer.SetupClient()
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()

	CombatInitializer.InitializeCharacter(character, false)

	-- Reinitialize on respawn
	player.CharacterAdded:Connect(function(newCharacter)
		CombatInitializer.InitializeCharacter(newCharacter, false)
	end)
end

--[[
	SERVER SETUP
	Call this from a ServerScript in ServerScriptService
]]
function CombatInitializer.SetupServer()
	-- Initialize for all existing players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			CombatInitializer.InitializeCharacter(player.Character, true)
		end

		player.CharacterAdded:Connect(function(character)
			CombatInitializer.InitializeCharacter(character, true)
		end)
	end

	-- Initialize for new players
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(character)
			CombatInitializer.InitializeCharacter(character, true)
		end)
	end)
end

return CombatInitializer
