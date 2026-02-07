--[[
	CombatServer.lua
	
	TSB-inspired server combat with spatial hitbox system.
	Features: Multi-target hits, camera-based attacks, dash combat.
	
	Author: Combat System Rewrite
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local HitEvent = CreateRemote("Hit", "RemoteEvent")
local DashEvent = CreateRemote("Dash", "RemoteEvent")
local SoundEvent = CreateRemote("PlaySound", "UnreliableRemoteEvent") -- For instant sound sync

-- ========================================
-- PLAYER DATA
-- ========================================

local PlayerData = {}

local function InitializePlayerData(player: Player)
	PlayerData[player.UserId] = {
		-- Combat state
		Combo = 0,
		IsAttacking = false,
		IsBlocking = false,
		IsDashing = false,
		LastBlockTime = 0,

		-- Timing
		LastAttackTime = 0,
		ComboResetTask = nil,
		AttackEndTask = nil,

		-- Anti-exploit
		Cooldowns = CombatUtilities.CreateCooldownTracker(),
		RateLimiter = CombatUtilities.CreateRateLimiter(CombatSettings.AntiExploit.MaxAttacksPerSecond),
	}
end

local function GetPlayerData(player: Player)
	return PlayerData[player.UserId]
end

local function CleanupPlayerData(player: Player)
	local data = PlayerData[player.UserId]
	if data then
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
-- COMBAT SERVICE
-- ========================================

local CombatService = {}

function CombatService.IsHeavyAttack(player: Player, rootPart: BasePart, isDashing: boolean): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local conditions = CombatSettings.M1.HeavyConditions

	-- Dashing = always heavy
	if isDashing then
		return true
	end

	-- Check sprint
	if conditions.RequiresSprint then
		if humanoid.WalkSpeed > CombatSettings.Player.WalkSpeed then
			return true
		end
	end

	-- Check airborne
	if conditions.RequiresJump then
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { player.Character }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local ray = workspace:Raycast(rootPart.Position, Vector3.new(0, -4, 0), rayParams)
		if not ray then
			return true
		end
	end

	-- Check velocity
	if conditions.MinVelocity then
		local velocity = rootPart.AssemblyLinearVelocity.Magnitude
		if velocity > conditions.MinVelocity then
			return true
		end
	end

	return false
end

function CombatService.CalculateDamage(combo: number, isHeavy: boolean, isFinisher: boolean): number
	if isFinisher then
		return CombatSettings.M1.FinisherDamage
	elseif isHeavy then
		return CombatSettings.M1.HeavyDamage
	else
		return CombatSettings.M1.BaseDamage
	end
end

function CombatService.CalculateKnockback(combo: number, isHeavy: boolean, isFinisher: boolean)
	local kb
	if isFinisher then
		kb = CombatSettings.M1.FinisherKnockback
	elseif isHeavy then
		kb = CombatSettings.M1.HeavyKnockback
	else
		kb = CombatSettings.M1.NormalKnockback
	end

	return kb[1], kb[2]
end

function CombatService.ApplyDamage(
	attacker: Player,
	targetData: { Character: Model, Humanoid: Humanoid, RootPart: BasePart },
	damage: number,
	knockbackH: number,
	knockbackV: number,
	attackerRoot: BasePart
): (boolean, boolean, boolean)
	if not targetData or not targetData.Humanoid or targetData.Humanoid.Health <= 0 then
		return false, false, false
	end

	local wasBlocked = false
	local wasPerfectBlock = false
	local targetPlayer = Players:GetPlayerFromCharacter(targetData.Character)

	-- Check blocking
	if targetPlayer then
		local data = GetPlayerData(targetPlayer)
		if data and data.IsBlocking then
			wasBlocked = true

			-- Perfect block check
			local timeSinceBlock = tick() - data.LastBlockTime
			if timeSinceBlock <= CombatSettings.Block.PerfectBlockWindow then
				wasPerfectBlock = true
				damage *= CombatSettings.Block.PerfectBlockReduction
				knockbackH *= CombatSettings.Block.KnockbackReduction * 0.5
				knockbackV *= CombatSettings.Block.KnockbackReduction * 0.5
			else
				damage *= CombatSettings.Block.DamageReduction
				knockbackH *= CombatSettings.Block.KnockbackReduction
				knockbackV *= CombatSettings.Block.KnockbackReduction
			end

			-- Notify blocker
			BlockEvent:FireClient(targetPlayer, "blocked", wasPerfectBlock)
		end
	end

	-- Apply damage
	targetData.Humanoid:TakeDamage(damage)

	-- Apply knockback
	if targetData.RootPart and attackerRoot then
		local direction = (targetData.RootPart.Position - attackerRoot.Position).Unit
		CombatUtilities.ApplyKnockback(targetData.RootPart, direction, knockbackH, knockbackV, 0.15)
	end

	return true, wasBlocked, wasPerfectBlock
end

function CombatService.IncrementCombo(data): number
	data.Combo = math.min(data.Combo + 1, CombatSettings.M1.MaxCombo)

	if data.ComboResetTask then
		task.cancel(data.ComboResetTask)
	end

	data.ComboResetTask = task.delay(CombatSettings.M1.ComboResetTime, function()
		data.Combo = 0
		data.ComboResetTask = nil
	end)

	return data.Combo
end

-- ========================================
-- M1 ATTACK HANDLER (Multi-Target)
-- ========================================

M1Event.OnServerEvent:Connect(function(player: Player, cameraLookVector: Vector3?)
	-- Validate
	if not CombatUtilities.ValidatePlayer(player) then
		return
	end

	local data = GetPlayerData(player)
	if not data then
		return
	end

	local character = player.Character
	local charValid, err, humanoid, rootPart = CombatUtilities.ValidateCharacter(character)
	if not charValid then
		return
	end

	-- Rate limit
	if not data.RateLimiter.Check(player.UserId) then
		warn(player.Name .. " attacking too fast!")
		return
	end

	-- State checks
	if data.IsAttacking or data.IsBlocking then
		return
	end

	-- Cooldown check
	local currentTime = tick()
	if currentTime - data.LastAttackTime < CombatSettings.M1.AttackCooldown then
		return
	end

	-- Combo reset check
	if currentTime - data.LastAttackTime > CombatSettings.M1.ComboResetTime then
		data.Combo = 0
		if data.ComboResetTask then
			task.cancel(data.ComboResetTask)
			data.ComboResetTask = nil
		end
	end

	-- Update state
	data.IsAttacking = true
	data.LastAttackTime = currentTime

	-- Increment combo BEFORE checking max
	local combo = CombatService.IncrementCombo(data)

	-- Check if this was the finisher (M4)
	local isFinisher = combo == CombatSettings.M1.MaxCombo

	-- COMBO LOOP FIX: Reset to 1 after M4
	if isFinisher then
		-- Schedule combo reset to M1 after this attack
		if data.ComboResetTask then
			task.cancel(data.ComboResetTask)
		end
		data.ComboResetTask = task.delay(0.1, function()
			data.Combo = 0 -- Will become 1 on next attack
			data.ComboResetTask = nil
		end)
	end

	-- Determine attack type
	local isHeavy = CombatService.IsHeavyAttack(player, rootPart, data.IsDashing)

	-- Animation data
	local animKey = "M" .. combo
	local animData = CombatSettings.Animations[animKey]
	local animDuration = animData and animData.Duration or 0.5
	local hitFrame = animData and animData.HitFrame or 0.15

	-- Send animation to client
	M1Event:FireClient(player, combo, isHeavy, isFinisher)

	-- Schedule hit detection (EARLIER for snappier feel)
	task.delay(animDuration * hitFrame, function()
		-- Calculate hitbox parameters
		local range = CombatSettings.M1.HitboxRange
		local angle = CombatSettings.M1.HitboxAngle

		-- Dash attacks have bigger range and hit 360
		if data.IsDashing and CombatSettings.Dash.AllowAttackDuringDash then
			range *= CombatSettings.Dash.DashAttackRangeMultiplier
			if CombatSettings.Dash.DashAttackHits360 then
				angle = 180 -- Full circle
			end
		end

		-- Get ALL targets in hitbox (MULTI-TARGET)
		local targets = CombatUtilities.GetTargetsInHitbox(
			character,
			range,
			angle,
			cameraLookVector, -- Camera-based if provided
			data.IsDashing
		)

		-- Limit max targets
		local maxTargets = CombatSettings.M1.MaxTargetsPerHit
		for i = 1, math.min(#targets, maxTargets) do
			local target = targets[i]

			-- Calculate damage and knockback
			local damage = CombatService.CalculateDamage(combo, isHeavy, isFinisher)
			local knockbackH, knockbackV = CombatService.CalculateKnockback(combo, isHeavy, isFinisher)

			-- Apply damage
			local success, wasBlocked, wasPerfectBlock =
				CombatService.ApplyDamage(player, target, damage, knockbackH, knockbackV, rootPart)

			-- Apply finisher stun
			if isFinisher and success and not wasBlocked then
				CombatUtilities.ApplyStun(target.Humanoid, CombatSettings.M1.FinisherStunDuration)
			end

			-- INSTANT VFX: Send hit event immediately when damage applies
			if success then
				-- Attacker sees hit
				HitEvent:FireClient(
					player,
					target.Character,
					damage,
					combo,
					isHeavy,
					isFinisher,
					wasBlocked,
					wasPerfectBlock
				)

				-- Target sees hit
				local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
				if targetPlayer then
					HitEvent:FireClient(
						targetPlayer,
						target.Character,
						damage,
						combo,
						isHeavy,
						isFinisher,
						wasBlocked,
						wasPerfectBlock
					)
				end

				-- INSTANT SOUND: unreliable network for lowest latency
				local soundId
				if wasBlocked then
					soundId = "BlockHit"
				else
					if combo == 1 then
						soundId = "M1Sound"
					elseif combo == 2 then
						soundId = "M2Sound"
					elseif combo == 3 then
						soundId = "M3Sound"
					elseif combo == 4 then
						soundId = "M4Sound"
					end
				end
				SoundEvent:FireClient(player, target.RootPart.Position, soundId)
				for _, p in Players:GetPlayers() do
					if p ~= player and p.Character then
						local r = p.Character:FindFirstChild("HumanoidRootPart")
						if r and (r.Position - target.RootPart.Position).Magnitude < 100 then
							SoundEvent:FireClient(p, target.RootPart.Position, soundId)
						end
					end
				end
			end
		end
	end)

	-- End attack state
	data.AttackEndTask = task.delay(animDuration, function()
		data.IsAttacking = false
		data.AttackEndTask = nil
	end)
end)

-- ========================================
-- BLOCKING HANDLER
-- ========================================

BlockEvent.OnServerEvent:Connect(function(player: Player, isBlocking: boolean)
	local data = GetPlayerData(player)
	if not data then
		return
	end

	data.IsBlocking = isBlocking

	if isBlocking then
		data.LastBlockTime = tick()
	end
end)

-- ========================================
-- DASH HANDLER
-- ========================================

DashEvent.OnServerEvent:Connect(function(player: Player, isDashing: boolean)
	local data = GetPlayerData(player)
	if not data then
		return
	end

	data.IsDashing = isDashing
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

		-- Health regen
		task.spawn(function()
			while character.Parent and humanoid.Health > 0 do
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.Health + CombatSettings.Player.HealthRegen, humanoid.MaxHealth)
				end
				task.wait(1)
			end
		end)

		-- Reset state
		local data = GetPlayerData(player)
		if data then
			data.Combo = 0
			data.IsAttacking = false
			data.IsBlocking = false
			data.IsDashing = false
			data.LastAttackTime = 0
		end
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(CleanupPlayerData)

for _, player in Players:GetPlayers() do
	task.spawn(OnPlayerAdded, player)
end

print("✅ CombatServer initialized (TSB Multi-Target)")
