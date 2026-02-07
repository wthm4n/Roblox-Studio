--[[
	CombatServer.lua
	
	Professional server-side combat system inspired by TSB.
	Features: M1 combos, heavy attacks, blocking, damage validation.
	
	Author: [Your Name]
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
-- COMBAT LOGIC
-- ========================================

local CombatService = {}

-- Check if attack should be heavy
function CombatService.IsHeavyAttack(player: Player, rootPart: BasePart): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	
	local conditions = CombatSettings.M1.HeavyConditions
	
	-- Check if sprinting (moving faster than walk speed)
	if conditions.RequiresSprint then
		if humanoid.WalkSpeed > CombatSettings.Player.WalkSpeed then
			return true
		end
	end
	
	-- Check if in air (jumping)
	if conditions.RequiresJump then
		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = {player.Character}
		rayParams.FilterType = Enum.RaycastFilterType.Blacklist
		
		local ray = workspace:Raycast(rootPart.Position, Vector3.new(0, -4, 0), rayParams)
		if not ray then -- Not touching ground
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

-- Calculate damage based on attack type
function CombatService.CalculateDamage(combo: number, isHeavy: boolean, isFinisher: boolean): number
	if isFinisher then
		return CombatSettings.M1.FinisherDamage
	elseif isHeavy then
		return CombatSettings.M1.HeavyDamage
	else
		return CombatSettings.M1.BaseDamage
	end
end

-- Calculate knockback
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

-- Apply damage to target
function CombatService.ApplyDamage(
	attacker: Player,
	targetData: {Character: Model, Humanoid: Humanoid, RootPart: BasePart},
	damage: number,
	knockbackH: number,
	knockbackV: number,
	attackerRoot: BasePart
): (boolean, boolean, boolean) -- success, wasBlocked, wasPerfectBlock
	if not targetData or not targetData.Humanoid or targetData.Humanoid.Health <= 0 then
		return false, false, false
	end
	
	local wasBlocked = false
	local wasPerfectBlock = false
	local targetPlayer = Players:GetPlayerFromCharacter(targetData.Character)
	
	-- Check blocking
	if targetPlayer then
		local targetData = GetPlayerData(targetPlayer)
		if targetData and targetData.IsBlocking then
			wasBlocked = true
			
			-- Check for perfect block (blocked within window)
			local timeSinceBlock = tick() - targetData.LastBlockTime
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

-- Increment combo
function CombatService.IncrementCombo(data): number
	data.Combo = math.min(data.Combo + 1, CombatSettings.M1.MaxCombo)
	
	-- Cancel existing reset
	if data.ComboResetTask then
		task.cancel(data.ComboResetTask)
	end
	
	-- Schedule reset
	data.ComboResetTask = task.delay(CombatSettings.M1.ComboResetTime, function()
		data.Combo = 0
		data.ComboResetTask = nil
	end)
	
	return data.Combo
end

-- ========================================
-- M1 ATTACK HANDLER
-- ========================================

M1Event.OnServerEvent:Connect(function(player: Player)
	-- Validate player
	if not CombatUtilities.ValidatePlayer(player) then return end
	
	local data = GetPlayerData(player)
	if not data then return end
	
	-- Validate character
	local character = player.Character
	local charValid, err, humanoid, rootPart = CombatUtilities.ValidateCharacter(character)
	if not charValid then return end
	
	-- Rate limit
	if not data.RateLimiter.Check(player.UserId) then
		warn(player.Name .. " attacking too fast!")
		return
	end
	
	-- Check state
	if data.IsAttacking or data.IsBlocking then return end
	
	-- Check cooldown
	local currentTime = tick()
	if currentTime - data.LastAttackTime < CombatSettings.M1.AttackCooldown then
		return
	end
	
	-- Check combo reset
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
	local combo = CombatService.IncrementCombo(data)
	
	-- Determine attack type
	local isHeavy = CombatService.IsHeavyAttack(player, rootPart)
	local isFinisher = combo == CombatSettings.M1.MaxCombo
	
	-- Get animation duration
	local animKey = "M" .. combo
	local animData = CombatSettings.Animations[animKey]
	local animDuration = animData and animData.Duration or 0.5
	local hitFrame = animData and animData.HitFrame or 0.4
	
	-- Send to client to play animation
	M1Event:FireClient(player, combo, isHeavy, isFinisher)
	
	-- Schedule hit detection
	task.delay(animDuration * hitFrame, function()
		-- Find target
		local target = CombatUtilities.GetTargetInFront(
			character,
			CombatSettings.M1.AttackRange,
			math.cos(math.rad(CombatSettings.M1.AttackAngle))
		)
		
		if target then
			-- Calculate damage and knockback
			local damage = CombatService.CalculateDamage(combo, isHeavy, isFinisher)
			local knockbackH, knockbackV = CombatService.CalculateKnockback(combo, isHeavy, isFinisher)
			
			-- Apply damage
			local success, wasBlocked, wasPerfectBlock = CombatService.ApplyDamage(
				player,
				target,
				damage,
				knockbackH,
				knockbackV,
				rootPart
			)
			
			-- Apply finisher stun
			if isFinisher and success and not wasBlocked then
				CombatUtilities.ApplyStun(target.Humanoid, CombatSettings.M1.FinisherStunDuration)
			end
			
			-- Send hit event to both players
			if success then
				HitEvent:FireClient(player, target.Character, damage, isHeavy, isFinisher, wasBlocked, wasPerfectBlock)
				
				-- Send hit feedback to target too
				local targetPlayer = Players:GetPlayerFromCharacter(target.Character)
				if targetPlayer then
					HitEvent:FireClient(targetPlayer, target.Character, damage, isHeavy, isFinisher, wasBlocked, wasPerfectBlock)
				end
			end
		end
	end)
	
	-- Schedule attack end
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
	if not data then return end
	
	data.IsBlocking = isBlocking
	
	if isBlocking then
		data.LastBlockTime = tick()
	end
end)

-- ========================================
-- PLAYER LIFECYCLE
-- ========================================

local function OnPlayerAdded(player: Player)
	InitializePlayerData(player)
	
	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid", 5)
		if not humanoid then return end
		
		-- Set health
		humanoid.MaxHealth = CombatSettings.Player.MaxHealth
		humanoid.Health = CombatSettings.Player.MaxHealth
		
		-- Health regen
		task.spawn(function()
			while character.Parent and humanoid.Health > 0 do
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(
						humanoid.Health + CombatSettings.Player.HealthRegen,
						humanoid.MaxHealth
					)
				end
				task.wait(1)
			end
		end)
		
		-- Reset combat state
		local data = GetPlayerData(player)
		if data then
			data.Combo = 0
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

print("✅ CombatServer initialized (TSB-style)")