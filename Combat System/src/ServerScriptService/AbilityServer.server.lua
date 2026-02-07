--[[
	AbilityServer.lua
	
	Server-side ability system with validation and anti-exploit.
	Manages ability activation, cooldowns, and damage application.
	
	Author: [Your Name]
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Modules
local CombatUtilities = require(ReplicatedStorage.Modules.Combat.CombatUtilities)

-- ========================================
-- SETUP REMOTES
-- ========================================

local AbilityRemotes = ReplicatedStorage:FindFirstChild("AbilityRemotes")
if not AbilityRemotes then
	AbilityRemotes = Instance.new("Folder")
	AbilityRemotes.Name = "AbilityRemotes"
	AbilityRemotes.Parent = ReplicatedStorage
end

local function CreateRemote(name: string, class: string)
	local remote = AbilityRemotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = AbilityRemotes
	end
	return remote
end

local UseAbilityEvent = CreateRemote("UseAbility", "RemoteEvent")
local AbilityResultEvent = CreateRemote("AbilityResult", "RemoteEvent")

-- ========================================
-- LOAD ABILITIES
-- ========================================

local AbilitiesFolder = ReplicatedStorage.Modules.Combat:WaitForChild("Abilities")
local abilityModules = {}

local function LoadAbilityModules()
	for _, moduleScript in AbilitiesFolder:GetChildren() do
		if moduleScript:IsA("ModuleScript") and moduleScript.Name:match("^Ability%d$") then
			local abilityNum = tonumber(moduleScript.Name:match("^Ability(%d)$"))

			if abilityNum then
				local success, abilityModule = pcall(require, moduleScript)

				if success then
					-- Validate ability
					local valid, err = abilityModule:Validate()
					if valid then
						abilityModules[abilityNum] = abilityModule
						print("✅ Loaded ability:", abilityModule.Name)
					else
						warn("❌ Invalid ability in " .. moduleScript.Name .. ":", err)
					end
				else
					warn("❌ Failed to load ability:", moduleScript.Name, abilityModule)
				end
			end
		end
	end

	print("📦 Loaded", #abilityModules, "abilities")
end

LoadAbilityModules()

-- ========================================
-- PLAYER DATA
-- ========================================

local PlayerAbilityData = {}

local function InitializePlayer(player: Player)
	PlayerAbilityData[player.UserId] = {
		-- State
		IsUsingAbility = false,
		CurrentAbility = nil,

		-- Cooldowns
		Cooldowns = CombatUtilities.CreateCooldownTracker(),

		-- Anti-Exploit
		RateLimiter = CombatUtilities.CreateRateLimiter(3), -- 3 abilities per second max
	}

	print("🎮 Initialized ability data for:", player.Name)
end

local function GetPlayerData(player: Player)
	return PlayerAbilityData[player.UserId]
end

local function CleanupPlayerData(player: Player)
	PlayerAbilityData[player.UserId] = nil
end

-- ========================================
-- ABILITY UTILITIES (provided to abilities)
-- ========================================

local function CreateAbilityUtilities(player: Player, character: Model)
	return {
		-- Targeting
		GetTargetsInRange = function(position: Vector3, range: number)
			return CombatUtilities.GetTargetsInRadius(position, range, character)
		end,

		GetTargetsInCone = function(position: Vector3, direction: Vector3, range: number, angle: number)
			return CombatUtilities.GetTargetsInCone(position, direction, range, angle, character)
		end,

		-- Damage
		ApplyDamage = function(targetData, damage: number, knockback: { Horizontal: number, Vertical: number }?)
			if not targetData or not targetData.Humanoid or targetData.Humanoid.Health <= 0 then
				return false
			end

			-- Apply damage
			targetData.Humanoid:TakeDamage(damage)

			-- Apply knockback if specified
			if knockback and targetData.RootPart then
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local direction = (targetData.RootPart.Position - rootPart.Position).Unit
					CombatUtilities.ApplyKnockback(
						targetData.RootPart,
						direction,
						knockback.Horizontal or 0,
						knockback.Vertical or 0,
						0.2
					)
				end
			end

			return true
		end,

		-- Utility
		Player = player,
		Character = character,
	}
end

-- ========================================
-- ABILITY ACTIVATION
-- ========================================

UseAbilityEvent.OnServerEvent:Connect(function(player: Player, abilityIndex: number)
	-- Validate player
	if not CombatUtilities.ValidatePlayer(player) then
		return
	end

	local data = GetPlayerData(player)
	if not data then
		return
	end

	-- Rate limiting
	if not data.RateLimiter.Check(player.UserId) then
		warn(player.Name .. " is using abilities too fast!")
		return
	end

	-- Validate character
	local character = player.Character
	local charValid, err, humanoid, rootPart = CombatUtilities.ValidateCharacter(character)
	if not charValid then
		return
	end

	-- Validate ability exists
	local ability = abilityModules[abilityIndex]
	if not ability then
		warn("Invalid ability index:", abilityIndex)
		return
	end

	-- Check if already using ability
	if data.IsUsingAbility then
		return
	end

	-- Check cooldown
	local cooldownKey = "ability_" .. abilityIndex
	if not data.Cooldowns.IsReady(cooldownKey) then
		local remaining = data.Cooldowns.Get(cooldownKey)
		-- Optionally notify client of remaining cooldown
		return
	end

	-- Mark as using ability
	data.IsUsingAbility = true
	data.CurrentAbility = abilityIndex

	-- Set cooldown
	data.Cooldowns.Set(cooldownKey, ability.Cooldown)

	-- Create utility functions for this ability activation
	local utilities = CreateAbilityUtilities(player, character)

	-- Execute ability
	local success, targets = false, {}

	local executeSuccess, executeResult = pcall(function()
		return ability:OnActivate(player, character, rootPart, utilities)
	end)

	if executeSuccess then
		success, targets = executeResult[1], executeResult[2]
	else
		warn("Error executing ability:", ability.Name, executeResult)
	end

	-- Send result to client
	AbilityResultEvent:FireClient(player, abilityIndex, success, targets or {})

	-- Schedule ability end
	task.delay(ability.AnimationDuration, function()
		if data then
			data.IsUsingAbility = false
			data.CurrentAbility = nil
		end
	end)
end)

-- ========================================
-- PLAYER LIFECYCLE
-- ========================================

local function OnPlayerAdded(player: Player)
	InitializePlayer(player)

	player.CharacterAdded:Connect(function()
		local data = GetPlayerData(player)
		if data then
			data.IsUsingAbility = false
			data.CurrentAbility = nil
		end
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(CleanupPlayerData)

-- Initialize existing players
for _, player in Players:GetPlayers() do
	task.spawn(OnPlayerAdded, player)
end

print("✅ AbilityServer initialized")
