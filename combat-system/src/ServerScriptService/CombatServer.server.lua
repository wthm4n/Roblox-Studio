--[[
	AdvancedCombatServer.lua
	
	Advanced server combat with:
	- Block durability system
	- Block breaking mechanic
	- Hit reaction triggers
	- M1-M5 combo
	
	Author: Advanced Combat System
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatSettings = require(ReplicatedStorage.Modules.Combat.CombatSettings)
local CombatUtilities = require(ReplicatedStorage.Modules.Combat.CombatUtilities)

local MovementServer = nil
pcall(function()
	MovementServer = require(ReplicatedStorage.Modules.Movement.MovementServer)
end)

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

local HitRequestEvent = CreateRemote("HitRequest", "RemoteEvent")
local HitResultEvent = CreateRemote("HitResult", "RemoteEvent")
local BlockEvent = CreateRemote("Block", "RemoteEvent")
local BlockDamageEvent = CreateRemote("BlockDamage", "RemoteEvent")

-- ========================================
-- PLAYER DATA
-- ========================================

local PlayerData = {}

local function InitializePlayerData(player: Player)
	PlayerData[player.UserId] = {
		-- Combat state
		IsBlocking = false,
		LastBlockTime = 0,
		BlockHealth = CombatSettings.Block.MaxHealth,

		-- Timing
		LastHitRequestTime = 0,

		-- Anti-exploit
		Cooldowns = CombatUtilities.CreateCooldownTracker(),
		RateLimiter = CombatUtilities.CreateRateLimiter(CombatSettings.AntiExploit.MaxAttacksPerSecond),
	}
end

local function GetPlayerData(player: Player)
	return PlayerData[player.UserId]
end

local function CleanupPlayerData(player: Player)
	PlayerData[player.UserId] = nil
end

-- ========================================
-- COMBAT SERVICE
-- ========================================

local CombatService = {}

function CombatService.IsHeavyAttack(player: Player, rootPart: BasePart): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	local conditions = CombatSettings.M1.HeavyConditions

	if conditions.RequiresSprint then
		if MovementServer and MovementServer.IsPlayerSprinting(player) then
			return true
		elseif humanoid.WalkSpeed > CombatSettings.Player.WalkSpeed then
			return true
		end
	end

	if conditions.RequiresJump then
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { player.Character }
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local ray = workspace:Raycast(rootPart.Position, Vector3.new(0, -4, 0), rayParams)
		if not ray then
			return true
		end
	end

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
	attackerRoot: BasePart,
	attackerCombo: number
): (boolean, boolean, boolean, boolean)
	if not targetData or not targetData.Humanoid or targetData.Humanoid.Health <= 0 then
		return false, false, false, false
	end

	local wasBlocked = false
	local wasPerfectBlock = false
	local blockBroken = false
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

			-- Reduce block health
			local blockDamage = CombatSettings.Block.DamagePerHit
			data.BlockHealth = math.max(0, data.BlockHealth - blockDamage)

			-- Send block damage event to client (triggers blocking hit reaction)
			BlockDamageEvent:FireClient(targetPlayer, blockDamage, attackerCombo)

			-- Check if block broken
			if data.BlockHealth <= 0 then
				blockBroken = true
				data.IsBlocking = false
				data.BlockHealth = 0

				-- Apply stun
				CombatUtilities.ApplyStun(targetData.Humanoid, CombatSettings.Block.BreakStunDuration)

				-- Increase damage/knockback for block break
				damage *= 1.5
				knockbackH *= 2
				knockbackV *= 2
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

	return true, wasBlocked, wasPerfectBlock, blockBroken
end

-- ========================================
-- HIT REQUEST HANDLER
-- ========================================

HitRequestEvent.OnServerEvent:Connect(function(player: Player, combo: number, cameraLookVector: Vector3?)
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

	-- Cooldown check
	local currentTime = tick()
	if currentTime - data.LastHitRequestTime < CombatSettings.M1.HitRequestCooldown then
		return
	end
	data.LastHitRequestTime = currentTime

	-- Validate combo (1-5)
	if not combo or combo < 1 or combo > CombatSettings.M1.MaxCombo then
		warn(player.Name .. " sent invalid combo: " .. tostring(combo))
		return
	end

	if data.IsBlocking then
		return
	end

	-- Determine attack type
	local isFinisher = combo == CombatSettings.M1.MaxCombo
	local isHeavy = CombatService.IsHeavyAttack(player, rootPart)

	local range = CombatSettings.M1.HitboxRange
	local angle = CombatSettings.M1.HitboxAngle

	-- Get targets
	local targets = CombatUtilities.GetTargetsInHitbox(character, range, angle, cameraLookVector, false)

	local maxTargets = CombatSettings.M1.MaxTargetsPerHit

	for i = 1, math.min(#targets, maxTargets) do
		local target = targets[i]

		local damage = CombatService.CalculateDamage(combo, isHeavy, isFinisher)
		local knockbackH, knockbackV = CombatService.CalculateKnockback(combo, isHeavy, isFinisher)

		local success, wasBlocked, wasPerfectBlock, blockBroken =
			CombatService.ApplyDamage(player, target, damage, knockbackH, knockbackV, rootPart, combo)

		-- Apply finisher stun (if not blocked and not already stunned from block break)
		if isFinisher and success and not wasBlocked and not blockBroken then
			CombatUtilities.ApplyStun(target.Humanoid, CombatSettings.M1.FinisherStunDuration)
		end

		if success then
			local hitData = {
				targetChar = target.Character,
				damage = damage,
				combo = combo,
				isHeavy = isHeavy,
				isFinisher = isFinisher,
				wasBlocked = wasBlocked,
				wasPerfectBlock = wasPerfectBlock,
				blockBroken = blockBroken,
			}

			-- Send to attacker
			HitResultEvent:FireClient(player, hitData)

			-- Send to target
			local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
			if targetPlayer then
				HitResultEvent:FireClient(targetPlayer, hitData)
			end

			-- Send to spectators
			for _, otherPlayer in Players:GetPlayers() do
				if otherPlayer ~= player and otherPlayer ~= targetPlayer then
					if otherPlayer.Character then
						local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
						if otherRoot and (otherRoot.Position - target.RootPart.Position).Magnitude < 100 then
							HitResultEvent:FireClient(otherPlayer, hitData)
						end
					end
				end
			end
		end
	end
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
		-- Reset block health when starting to block
		data.BlockHealth = CombatSettings.Block.MaxHealth
	end
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

		humanoid.MaxHealth = CombatSettings.Player.MaxHealth
		humanoid.Health = CombatSettings.Player.MaxHealth

		local data = GetPlayerData(player)
		if data then
			data.IsBlocking = false
			data.BlockHealth = CombatSettings.Block.MaxHealth
			data.LastHitRequestTime = 0
		end
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(CleanupPlayerData)

for _, player in Players:GetPlayers() do
	task.spawn(OnPlayerAdded, player)
end

print("✅ AdvancedCombatServer initialized")
