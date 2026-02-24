--[[
	MovementServer.lua
	
	Server-side movement state tracking
	(Ledge system removed)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementSettings = require(ReplicatedStorage.Modules.Movement.MovementSettings)

-- ========================================
-- SETUP REMOTES
-- ========================================

local RemoteFolder = ReplicatedStorage:FindFirstChild("MovementRemotes")
if not RemoteFolder then
	RemoteFolder = Instance.new("Folder")
	RemoteFolder.Name = "MovementRemotes"
	RemoteFolder.Parent = ReplicatedStorage
end

local function CreateRemote(name: string, class: string)
	local remote = RemoteFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = RemoteFolder
	end
	return remote
end

local MovementEvent = CreateRemote("MovementUpdate", "RemoteEvent")
local DashEvent = CreateRemote("Dash", "RemoteEvent")

-- ========================================
-- PLAYER DATA
-- ========================================

local PlayerData = {}

local function InitializePlayerData(player: Player)
	PlayerData[player.UserId] = {
		isDashing = false,
		isWallRunning = false,
		wallRunDirection = "None",
		isSliding = false,
	}
end

local function GetPlayerData(player: Player)
	return PlayerData[player.UserId]
end

local function CleanupPlayerData(player: Player)
	PlayerData[player.UserId] = nil
end

-- ========================================
-- MOVEMENT STATE HANDLERS
-- ========================================

MovementEvent.OnServerEvent:Connect(function(player: Player, action: string, value: boolean, extra: any)
	local data = GetPlayerData(player)
	if not data then
		return
	end

	if action == "wallRun" then
		data.isWallRunning = value
		if extra then
			data.wallRunDirection = extra
		end
	elseif action == "slide" then
		data.isSliding = value
	end
end)

DashEvent.OnServerEvent:Connect(function(player: Player, isDashing: boolean, direction: string)
	local data = GetPlayerData(player)
	if not data then
		return
	end

	data.isDashing = isDashing
end)

-- ========================================
-- PUBLIC API
-- ========================================

local MovementServer = {}

function MovementServer.GetPlayerState(player: Player)
	return GetPlayerData(player)
end

function MovementServer.IsPlayerDashing(player: Player): boolean
	local data = GetPlayerData(player)
	return data and data.isDashing or false
end

function MovementServer.IsPlayerWallRunning(player: Player): boolean
	local data = GetPlayerData(player)
	return data and data.isWallRunning or false
end

function MovementServer.IsPlayerSliding(player: Player): boolean
	local data = GetPlayerData(player)
	return data and data.isSliding or false
end

-- ========================================
-- PLAYER LIFECYCLE
-- ========================================

local function OnPlayerAdded(player: Player)
	InitializePlayerData(player)

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then
			return
		end

		humanoid.MaxHealth = MovementSettings.Player.MaxHealth
		humanoid.Health = MovementSettings.Player.MaxHealth

		-- Health regen
		task.spawn(function()
			while character.Parent and humanoid.Health > 0 do
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health =
						math.min(humanoid.Health + MovementSettings.Player.HealthRegen, humanoid.MaxHealth)
				end
				task.wait(1)
			end
		end)

		-- Reset state
		local data = GetPlayerData(player)
		if data then
			data.isDashing = false
			data.isWallRunning = false
			data.wallRunDirection = "None"
			data.isSliding = false
		end
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(CleanupPlayerData)

for _, player in Players:GetPlayers() do
	task.spawn(OnPlayerAdded, player)
end

print("✅ MovementServer initialized")

return MovementServer
