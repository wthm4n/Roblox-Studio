--[[
	Pistol Server Handler
	Place this script in ServerScriptService
	
	Monitors players for "Pistol" tool in their backpack/character
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

-- ═══════════════════════════════════════════════════════════
--  PISTOL CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local PistolConfig = {
	-- Gun Info
	GunName = "Pistol", -- MUST match folder name in Assets!
	GunImage = "rbxassetid://123456789", -- Replace with your pistol image ID

	-- Damage Settings
	BaseDamage = 10,
	HeadshotMultiplier = 3.0,
	DamageFalloffStart = 75, -- studs where damage falloff begins
	DamageFalloffEnd = 200, -- studs where damage reaches minimum
	MinDamage = 5, -- minimum damage at max range

	-- Fire Rate & Mode
	FireRate = 250, -- Rounds Per Minute (RPM) - Semi-auto pistol
	FireMode = "Semi", -- "Auto", "Semi", "Burst"
	BurstCount = 3,
	BurstDelay = 0.1,

	-- Ammo Configuration
	MagazineSize = 7, -- Standard Desert Eagle mag size
	ReserveAmmo = 35,
	ReloadTimeTactical = 1.8, -- reload time with bullet in chamber
	ReloadTimeEmpty = 2.3, -- reload time from empty magazine

	-- Recoil Pattern (Vertical, Horizontal)
	-- Pistols have more vertical recoil
	RecoilPattern = {
		{ 0.8, 0.15 }, -- Shot 1 - Good kick upward
		{ 0.9, -0.12 }, -- Shot 2
		{ 0.85, 0.18 }, -- Shot 3
		{ 0.95, -0.15 }, -- Shot 4
		{ 1.0, 0.20 }, -- Shot 5 - Bigger kick
		{ 0.95, -0.13 }, -- Shot 6
		{ 0.90, 0.16 }, -- Shot 7
	},
	RecoilRecovery = 0.15,

	-- Bloom/Spread (in degrees)
	BaseSpread = 0.8, -- Pistols are less accurate
	SpreadIncrease = 0.4, -- More bloom per shot
	MaxSpread = 6.0, -- Higher max spread
	SpreadRecovery = 0.22, -- Faster recovery

	-- Range
	MaxRange = 350, -- Pistol effective range

	-- Animation IDs (replace with your animation IDs)
	Animations = {
		Idle = 115284468970500, -- idle animation ID
		Walk = 0, -- walking animation ID
		Fire = 129841784532184, -- fire animation ID
		ReloadTactical = 77706176424948, -- tactical reload (bullet in chamber)
		ReloadEmpty = 77706176424948, -- empty reload animation
	},

	-- Assets (Sounds & VFX) - Will be loaded from ReplicatedStorage > Assets > [GunName]
	Assets = {
		-- Sounds (either direct Sound instances or string names to find in Assets folder)
		FireSound = "FireSound", -- Will look for Assets/Pistol/FireSound
		ReloadSound = "ReloadSound",
		EmptyClickSound = "EmptyClick",
		ShellEjectSound = "ShellEject",

		-- VFX (Optional - leave nil to use defaults)
		MuzzleFlash = "MuzzleFlash", -- Can be ParticleEmitter, Folder with effects, or path string
		BulletTracer = nil, -- Custom beam or nil for default
		HitEffect = nil, -- Custom hit particles or nil for default
		ShellCasing = nil, -- Custom shell Part/MeshPart/Model or nil for default
	},
}

-- ═══════════════════════════════════════════════════════════
--  PLAYER GUN MANAGEMENT
-- ═══════════════════════════════════════════════════════════

-- Store gun instances per player
local PlayerGuns = {} -- [Player] = {Gun = GunSystem, Tool = Tool}

-- Anti-exploit: Fire rate limiter per player
local PlayerFireTimes = {} -- [Player] = lastFireTime

local MIN_FIRE_INTERVAL = (60 / PistolConfig.FireRate) * 0.85 -- 15% tolerance

-- Tool name to look for
local TOOL_NAME = "Pistol"

-- Create gun for player
local function createGunForPlayer(player, tool)
	-- Clean up existing gun if any
	if PlayerGuns[player] then
		PlayerGuns[player].Gun:Unequip()
		PlayerGuns[player] = nil
	end

	-- Create new gun instance
	local gun = GunSystem.new(PistolConfig)
	gun:Initialize(tool, player)

	-- Store gun instance
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
	-- Check if tool is equipped or in backpack
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

	-- Clean up connections when tool is removed
	tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(game) then
			equippedConnection:Disconnect()
			unequippedConnection:Disconnect()
			removeGunForPlayer(player)
		end
	end)
end

-- Find pistol tool in player's backpack or character
local function findPistolTool(player)
	local character = player.Character
	local backpack = player:FindFirstChild("Backpack")

	-- Check character first (equipped)
	if character then
		local tool = character:FindFirstChild(TOOL_NAME)
		if tool and tool:IsA("Tool") then
			return tool
		end
	end

	-- Check backpack
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
	-- Wait for character
	local character = player.Character or player.CharacterAdded:Wait()

	-- Wait a bit for tools to load
	task.wait(0.5)

	-- Look for pistol tool
	local pistolTool = findPistolTool(player)

	if pistolTool then
		print("Found Pistol for " .. player.Name)
		createGunForPlayer(player, pistolTool)
		setupToolMonitoring(player, pistolTool)
	else
		print("No Pistol found for " .. player.Name)
	end

	-- Monitor backpack for pistol being added
	local backpack = player:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(function(child)
		if child.Name == TOOL_NAME and child:IsA("Tool") then
			print("Pistol added to backpack for " .. player.Name)
			createGunForPlayer(player, child)
			setupToolMonitoring(player, child)
		end
	end)

	-- Monitor character for pistol being equipped
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

-- Handle fire requests from client
FireGunRemote.OnServerEvent:Connect(function(player, targetPosition)
	-- Validate player has gun
	local playerData = PlayerGuns[player]
	if not playerData then
		warn("Player " .. player.Name .. " tried to fire without gun!")
		return
	end

	if not playerData.IsEquipped then
		warn("Player " .. player.Name .. " tried to fire unequipped gun!")
		return
	end

	-- Validate target position
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

-- Handle reload requests from client
ReloadGunRemote.OnServerEvent:Connect(function(player)
	-- Validate player has gun
	local playerData = PlayerGuns[player]
	if not playerData then
		return
	end
	if not playerData.IsEquipped then
		return
	end

	-- Reload the gun
	playerData.Gun:Reload()
end)

-- Update spread recovery for all active guns
RunService.Heartbeat:Connect(function(deltaTime)
	for player, data in pairs(PlayerGuns) do
		if data.IsEquipped then
			data.Gun:UpdateSpread(deltaTime)
		end
	end
end)

print("Pistol Server Handler loaded successfully!")

-- ═══════════════════════════════════════════════════════════
--  NOTES
-- ═══════════════════════════════════════════════════════════

--[[
	TO USE THIS SYSTEM:
	
	1. Place this script in ServerScriptService
	2. Create a Tool named "Pistol" in StarterPack or ServerStorage
	3. The tool should have:
	   - Handle (Part)
	   - GunMesh (MeshPart)
	   - Muzzle (Part/Attachment) - at barrel tip
	   - EjectionPort (Part/Attachment, optional) - at ejection port
	
	4. Give the tool to players (via StarterPack, game script, etc)
	5. The system will automatically detect and setup the gun!
	
	TOOL HIERARCHY:
	Pistol (Tool)
	├── Handle (Part)
	├── GunMesh (MeshPart)
	├── Muzzle (Part) - Position at barrel end
	└── EjectionPort (Part, optional) - Position at ejection port
]]
