--[[
	Pistol Server Handler - UPDATED WITH JAMMING
	Place this script in ServerScriptService
	
	Monitors players for "Pistol" tool in their backpack/character
	Handles server-side gun logic including jamming
]]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Require the GunSystem module
local GunSystem = require(ReplicatedStorage.Modules:WaitForChild("GunSystem"))

-- Get remotes
local GunRemotes = ReplicatedStorage:WaitForChild("GunRemotes")
local FireGunRemote = GunRemotes:WaitForChild("FireGun")
local ReloadGunRemote = GunRemotes:WaitForChild("ReloadGun")
local UnjamGunRemote = GunRemotes:WaitForChild("UnjamGun")

-- ═══════════════════════════════════════════════════════════
--  PISTOL CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local PistolConfig = {
	-- Gun Info
	GunName = "Pistol", -- MUST match folder name in Assets!
	GunImage = "rbxassetid://123456789", -- Replace with your pistol image ID

	-- Damage Settings
	BaseDamage = 5,
	HeadshotMultiplier = 2.5,
	DamageFalloffStart = 75,
	DamageFalloffEnd = 200,
	MinDamage = 5,

	-- Fire Rate & Mode
	FireRate = 250, -- RPM
	FireMode = "Semi",
	BurstCount = 3,
	BurstDelay = 0.1,

	-- Ammo Configuration
	MagazineSize = 12,
	ReserveAmmo = 60,
	ReloadTimeTactical = 1.8,
	ReloadTimeEmpty = 2.3,

	-- Jamming System
	JamEnabled = true,
	JamChancePerShot = 0.02, -- 2% base chance
	JamChanceIncreasePerShot = 0.005, -- Increases by 0.5% per shot
	MaxJamChance = 0.15, -- Max 15% jam chance
	UnjamTime = 1.5, -- 1.5 seconds to unjam

	-- Recoil Pattern (Vertical, Horizontal)
	RecoilPattern = {
		{ 0.8, 0.15 },
		{ 0.9, -0.12 },
		{ 0.85, 0.18 },
		{ 0.95, -0.15 },
		{ 1.0, 0.20 },
		{ 0.95, -0.13 },
		{ 0.90, 0.16 },
	},
	RecoilRecovery = 0.15,

	-- Bloom/Spread
	BaseSpread = 0.8,
	SpreadIncrease = 0.4,
	MaxSpread = 6.0,
	SpreadRecovery = 0.22,

	-- Range
	MaxRange = 350,

	-- Animation IDs (⚠️ REPLACE WITH YOUR ANIMATION IDs)
	Animations = {
		Idle = 115284468970500,
		Walk = 0,
		Fire = 129841784532184,
		ReloadTactical = 77706176424948,
		ReloadEmpty = 77706176424948,
		Equip = 137291357974383,
		Unjam = 77706176424948,
	},

	-- Assets (Sounds & VFX)
	Assets = {
		FireSound = "FireSound",
		ReloadSound = "ReloadSound",
		EmptyClickSound = "EmptyClick",
		ShellEjectSound = "ShellEject",
		JamSound = "JamSound", -- Add jam sound asset
		UnjamSound = "UnjamSound", -- Add unjam sound asset

		MuzzleFlash = "MuzzleFlash",
		BulletTracer = nil,
		HitEffect = nil,
		ShellCasing = nil,
	},
}

-- ═══════════════════════════════════════════════════════════
--  PLAYER GUN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

local PlayerGuns = {}
local PlayerFireTimes = {}

local MIN_FIRE_INTERVAL = (60 / PistolConfig.FireRate) * 0.85
local TOOL_NAME = "Pistol"

-- Create gun for player
local function createGunForPlayer(player, tool)
	if PlayerGuns[player] then
		PlayerGuns[player].Gun:Unequip()
		PlayerGuns[player] = nil
	end

	local gun = GunSystem.new(PistolConfig)
	gun:Initialize(tool, player)

	PlayerGuns[player] = {
		Gun = gun,
		Tool = tool,
		IsEquipped = true,
	}

	print("Created Pistol for " .. player.Name)
end

-- Remove gun for player
local function removeGunForPlayer(player)
	if PlayerGuns[player] then
		PlayerGuns[player].Gun:Unequip()
		PlayerGuns[player] = nil
		print("Removed Pistol for " .. player.Name)
	end
end

-- Monitor tool equipped/unequipped
local function setupToolMonitoring(player, tool)
	local equippedConnection
	local unequippedConnection

	equippedConnection = tool.Equipped:Connect(function()
		if PlayerGuns[player] then
			PlayerGuns[player].IsEquipped = true
			PlayerGuns[player].Gun:Initialize(tool, player)
		end
	end)

	unequippedConnection = tool.Unequipped:Connect(function()
		if PlayerGuns[player] then
			PlayerGuns[player].IsEquipped = false
			PlayerGuns[player].Gun:Unequip()
		end
	end)

	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			equippedConnection:Disconnect()
			unequippedConnection:Disconnect()
			removeGunForPlayer(player)
		end
	end)
end

-- Find pistol tool
local function findPistolTool(player)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")

	if character then
		local tool = character:FindFirstChild(TOOL_NAME)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	if backpack then
		local tool = backpack:FindFirstChild(TOOL_NAME)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	return nil
end

-- Setup player
local function setupPlayer(player)
	local character = player.Character or player.CharacterAdded:Wait()

	task.wait(0.5)

	local pistolTool = findPistolTool(player)

	if pistolTool then
		print("Found Pistol for " .. player.Name)
		createGunForPlayer(player, pistolTool)
		setupToolMonitoring(player, pistolTool)
	else
		print("No Pistol found for " .. player.Name)
	end

	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(function(child)
		if child.Name == TOOL_NAME and child:IsA("Tool") then
			print("Pistol added to backpack for " .. player.Name)
			createGunForPlayer(player, child)
			setupToolMonitoring(player, child)
		end
	end)

	player.CharacterAdded:Connect(function(newCharacter)
		task.wait(0.5)
		local pistol = findPistolTool(player)
		if pistol then
			createGunForPlayer(player, pistol)
			setupToolMonitoring(player, pistol)
		end
	end)
end

-- Handle player joined
Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
	removeGunForPlayer(player)
	PlayerFireTimes[player] = nil
end)

-- Setup existing players
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		setupPlayer(player)
	end)
end

-- ═══════════════════════════════════════════════════════════
--  REMOTE EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════

-- Handle fire requests
FireGunRemote.OnServerEvent:Connect(function(player, targetPosition)
	local playerData = PlayerGuns[player]
	if not playerData then
		warn("Player " .. player.Name .. " tried to fire without gun!")
		return
	end

	if not playerData.IsEquipped then
		warn("Player " .. player.Name .. " tried to fire unequipped gun!")
		return
	end

	if not targetPosition or typeof(targetPosition) ~= "Vector3" then
		warn("Invalid target position from " .. player.Name)
		return
	end

	-- Anti-exploit: Rate limit check
	local currentTime = tick()
	local lastFireTime = PlayerFireTimes[player] or 0

	if currentTime - lastFireTime < MIN_FIRE_INTERVAL then
		warn("Player " .. player.Name .. " is firing too fast! Possible exploit.")
		return
	end

	PlayerFireTimes[player] = currentTime

	-- Fire the gun
	playerData.Gun:Fire(targetPosition)
end)

-- Handle reload requests
ReloadGunRemote.OnServerEvent:Connect(function(player)
	local playerData = PlayerGuns[player]
	if not playerData then
		return
	end
	if not playerData.IsEquipped then
		return
	end

	playerData.Gun:Reload()
end)

-- Handle unjam requests
UnjamGunRemote.OnServerEvent:Connect(function(player)
	local playerData = PlayerGuns[player]
	if not playerData then
		return
	end
	if not playerData.IsEquipped then
		return
	end

	-- Unjam the gun
	playerData.Gun:Unjam()
end)

-- Update spread recovery
RunService.Heartbeat:Connect(function(deltaTime)
	for player, data in pairs(PlayerGuns) do
		if data.IsEquipped then
			data.Gun:UpdateSpread(deltaTime)
		end
	end
end)

print(
	"═══════════════════════════════════════════"
)
print("🔫 Pistol Server Handler - UPDATED")
print(
	"═══════════════════════════════════════════"
)
print("✅ Gun Jamming System Enabled")
print("✅ Unjam Remote Handler Active")
print(
	"═══════════════════════════════════════════"
)
