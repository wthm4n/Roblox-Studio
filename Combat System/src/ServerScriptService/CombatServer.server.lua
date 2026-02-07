--[[
	CombatServer.lua
	
	Server-side combat logic for M1 attacks and blocking.
	Handles validation, damage calculation, and state management.
	
	Architecture:
	- Event-driven design
	- Rate limiting & anti-exploit
	- Server-authoritative damage
	- Clean state management
	
	Author: [Your Name]
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Modules
local CombatSettings = require(ReplicatedStorage.Modules.Combat.CombatSettings)
local CombatUtilities = require(ReplicatedStorage.Modules.Combat.CombatUtilities)

-- ========================================
-- SETUP REMOTES
-- ========================================

local RemoteFolder = ReplicatedStorage:FindFirstChild("CombatRemotes")
if not RemoteFolder then
	RemoteFolder = Instance.new("Folder")
	RemoteFolder.Name = "CombatRemotes"
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

local M1Event = CreateRemote("M1Attack", "RemoteEvent")
local BlockEvent = CreateRemote("Block", "RemoteEvent")
local DamageEvent = CreateRemote("DamageRequest", "RemoteEvent")
local HitResultEvent = CreateRemote("HitResult", "RemoteEvent")

-- ========================================
-- PLAYER DATA
-- ========================================

local PlayerData = {}

local function InitializePlayerData(player: Player)
	PlayerData[player.UserId] = {
		-- Combat State
		Combo = 0,
		LastAttackTime = 0,
		IsAttacking = false,
		IsBlocking = false,

		-- Cooldown Management
		Cooldowns = CombatUtilities.CreateCooldownTracker(),

		-- Anti-Exploit
		RateLimiter = CombatUtilities.CreateRateLimiter(CombatSettings.AntiExploit.MaxAttacksPerSecond),

		-- Scheduled Tasks
		ComboResetTask = nil,
		AttackEndTask = nil,
	}
end

local function GetPlayerData(player: Player)
	return PlayerData[player.UserId]
end

local function CleanupPlayerData(player: Player)
	local data = PlayerData[player.UserId]
	if data then
		-- Cancel any scheduled tasks
		if data.ComboResetTask then
			task.cancel(data.ComboResetTask)
		end
		if data.AttackEndTask then
			task.cancel(data.AttackEndTask)
		end
	end
	PlayerData[player.UserId] = nil
end

-- ========================================
-- DAMAGE SYSTEM
-- ========================================

local DamageService = {}

function DamageService.CalculateDamage(combo: number, isHeavy: boolean): number
	local baseDamage = isHeavy and CombatSettings.M1.HeavyDamage or CombatSettings.M1.BaseDamage

	-- Apply finisher multiplier
	if combo == CombatSettings.M1.MaxComboCount then
		baseDamage *= CombatSettings.M1.ComboFinisherMultiplier
	end

	return baseDamage
end

function DamageService.CalculateKnockback(combo: number, isHeavy: boolean, isBlocking: boolean)
	local horizontal, vertical

	if isBlocking then
		horizontal = CombatSettings.M1.BaseKnockbackHorizontal * CombatSettings.Block.KnockbackReduction
		vertical = CombatSettings.M1.BaseKnockbackVertical * CombatSettings.Block.KnockbackReduction
	elseif combo == CombatSettings.M1.MaxComboCount then
		horizontal = CombatSettings.M1.FinisherKnockbackHorizontal
		vertical = CombatSettings.M1.FinisherKnockbackVertical
	elseif isHeavy then
		horizontal = CombatSettings.M1.HeavyKnockbackHorizontal
		vertical = CombatSettings.M1.HeavyKnockbackVertical
	else
		horizontal = CombatSettings.M1.BaseKnockbackHorizontal
		vertical = CombatSettings.M1.BaseKnockbackVertical

		-- Apply combo multiplier
		local multiplier = 1 + (combo * CombatSettings.M1.ComboKnockbackMultiplier)
		horizontal *= multiplier
		vertical *= multiplier
	end

	return horizontal, vertical
end

function DamageService.ApplyDamage(
	attacker: Player,
	targetData: { Character: Model, Humanoid: Humanoid, RootPart: BasePart },
	damage: number,
	knockbackH: number,
	knockbackV: number,
	attackerRoot: BasePart
): (boolean, boolean) -- success, wasBlocked
	if not targetData or not targetData.Humanoid or targetData.Humanoid.Health <= 0 then
		return false, false
	end

	local wasBlocked = false
	local targetPlayer = Players:GetPlayerFromCharacter(targetData.Character)

	-- Check if target is blocking
	if targetPlayer then
		local targetPlayerData = GetPlayerData(targetPlayer)
		if targetPlayerData and targetPlayerData.IsBlocking then
			wasBlocked = true
			damage *= CombatSettings.Block.DamageReduction
			BlockEvent:FireClient(targetPlayer, "blocked")
		end
	end

	-- Apply damage
	targetData.Humanoid:TakeDamage(damage)

	-- Apply knockback
	if targetData.RootPart and attackerRoot then
		local direction = (targetData.RootPart.Position - attackerRoot.Position).Unit
		CombatUtilities.ApplyKnockback(targetData.RootPart, direction, knockbackH, knockbackV, 0.15)
	end

	return true, wasBlocked
end

-- ========================================
-- COMBO SYSTEM
-- ========================================

local ComboService = {}

function ComboService.IncrementCombo(data)
	data.Combo = math.min(data.Combo + 1, CombatSettings.M1.MaxComboCount)

	-- Cancel existing combo reset
	if data.ComboResetTask then
		task.cancel(data.ComboResetTask)
	end

	-- Schedule combo reset
	if data.Combo < CombatSettings.M1.MaxComboCount then
		data.ComboResetTask = task.delay(CombatSettings.M1.ComboResetTime, function()
			data.Combo = 0
			data.ComboResetTask = nil
		end)
	else
		-- Finisher - reset after cooldown
		data.ComboResetTask = task.delay(CombatSettings.M1.ComboFinisherCooldown, function()
			data.Combo = 0
			data.ComboResetTask = nil
		end)
	end

	return data.Combo
end

function ComboService.ResetCombo(data)
	if data.ComboResetTask then
		task.cancel(data.ComboResetTask)
		data.ComboResetTask = nil
	end
	data.Combo = 0
end

-- ========================================
-- ATTACK HANDLING
-- ========================================

local function GetAnimationDuration(combo: number): number
	local animData = CombatSettings.Animations["M" .. combo]
	if animData and animData.Duration then
		return animData.Duration
	end
	return 0.5 -- Default fallback
end

M1Event.OnServerEvent:Connect(function(player: Player)
	-- Validate player
	local valid = CombatUtilities.ValidatePlayer(player)
	if not valid then
		return
	end

	local data = GetPlayerData(player)
	if not data then
		return
	end

	-- Validate character
	local character = player.Character
	local charValid, err, humanoid, rootPart = CombatUtilities.ValidateCharacter(character)
	if not charValid then
		return
	end

	-- Rate limiting
	if not data.RateLimiter.Check(player.UserId) then
		warn(player.Name .. " is attacking too fast!")
		return
	end

	-- Check if can attack
	if data.IsAttacking or data.IsBlocking then
		return
	end

	local currentTime = tick()
	if currentTime - data.LastAttackTime < CombatSettings.M1.MinimumAttackDelay then
		return
	end

	-- Check combo reset
	if currentTime - data.LastAttackTime > CombatSettings.M1.ComboResetTime then
		ComboService.ResetCombo(data)
	end

	-- Update state
	data.IsAttacking = true
	data.LastAttackTime = currentTime
	local combo = ComboService.IncrementCombo(data)

	-- Fire to client
	M1Event:FireClient(player, combo)

	-- Schedule attack end
	local animDuration = GetAnimationDuration(combo)
	data.AttackEndTask = task.delay(animDuration, function()
		data.IsAttacking = false
		data.AttackEndTask = nil
	end)
end)

-- ========================================
-- DAMAGE REQUEST HANDLING
-- ========================================

DamageEvent.OnServerEvent:Connect(function(player: Player, combo: number)
	local data = GetPlayerData(player)
	if not data then
		return
	end

	local character = player.Character
	local charValid, err, humanoid, rootPart = CombatUtilities.ValidateCharacter(character)
	if not charValid then
		return
	end

	-- Validate combo matches server state (anti-cheat)
	if combo ~= data.Combo then
		warn(player.Name .. " sent mismatched combo!")
		return
	end

	-- Find target
	local target = CombatUtilities.GetTargetInFront(
		character,
		CombatSettings.M1.AttackRange,
		0.5 -- Angle threshold
	)

	if not target then
		HitResultEvent:FireClient(player, nil, false, false)
		return
	end

	-- Calculate damage and knockback
	local velocity = rootPart.AssemblyLinearVelocity.Magnitude
	local isHeavy = velocity > CombatSettings.M1.HeavyVelocityThreshold

	local damage = DamageService.CalculateDamage(combo, isHeavy)
	local knockbackH, knockbackV = DamageService.CalculateKnockback(combo, isHeavy, false)

	-- Apply damage
	local success, wasBlocked = DamageService.ApplyDamage(player, target, damage, knockbackH, knockbackV, rootPart)

	-- Apply finisher stun
	if combo == CombatSettings.M1.MaxComboCount and success and not wasBlocked then
		CombatUtilities.ApplyStun(target.Humanoid, CombatSettings.M1.FinisherStunDuration)
	end

	-- Send result to client
	HitResultEvent:FireClient(player, target.Character, success, wasBlocked)
end)

-- ========================================
-- BLOCKING
-- ========================================

BlockEvent.OnServerEvent:Connect(function(player: Player, isBlocking: boolean)
	local data = GetPlayerData(player)
	if not data then
		return
	end

	data.IsBlocking = isBlocking
end)

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

		-- Set health
		humanoid.MaxHealth = CombatSettings.Player.MaxHealth
		humanoid.Health = CombatSettings.Player.MaxHealth

		-- Health regeneration
		task.spawn(function()
			while character.Parent and humanoid.Health > 0 do
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.Health + CombatSettings.Player.HealthRegen, humanoid.MaxHealth)
				end
				task.wait(1)
			end
		end)

		-- Reset combat state on respawn
		local data = GetPlayerData(player)
		if data then
			ComboService.ResetCombo(data)
			data.IsAttacking = false
			data.IsBlocking = false
			data.LastAttackTime = 0
		end
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(CleanupPlayerData)

-- Initialize existing players
for _, player in Players:GetPlayers() do
	task.spawn(OnPlayerAdded, player)
end

print("✅ CombatServer initialized")
