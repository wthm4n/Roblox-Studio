local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local SETTINGS = require(ReplicatedStorage.Modules.Combat:WaitForChild("CombatSettings"))

local RemoteFolder = Instance.new("Folder")
RemoteFolder.Name = "CombatRemotes"
RemoteFolder.Parent = ReplicatedStorage

local M1Event = Instance.new("RemoteEvent")
M1Event.Name = "M1Attack"
M1Event.Parent = RemoteFolder

local BlockEvent = Instance.new("RemoteEvent")
BlockEvent.Name = "Block"
BlockEvent.Parent = RemoteFolder

local DamageEvent = Instance.new("RemoteEvent")
DamageEvent.Name = "DamageRequest"
DamageEvent.Parent = RemoteFolder

local PlayerData = {}

local AttackTracking = {}

local function InitializePlayer(player)
	PlayerData[player.UserId] = {
		Combo = 0,
		LastM1 = 0,
		LastDamageRequest = 0,
		IsBlocking = false,
		ComboResetScheduled = false,
		AttackCount = 0,
		IsAttacking = false,
	}

	AttackTracking[player.UserId] = {
		AttacksInLastSecond = 0,
		LastResetTime = tick(),
	}

	player.CharacterAdded:Connect(function(character)
		local humanoid = character:WaitForChild("Humanoid")
		humanoid.MaxHealth = SETTINGS.MAX_HEALTH
		humanoid.Health = SETTINGS.MAX_HEALTH

		local data = PlayerData[player.UserId]
		if data then
			data.Combo = 0
			data.LastM1 = 0
			data.LastDamageRequest = 0
			data.IsBlocking = false
			data.ComboResetScheduled = false
			data.AttackCount = 0
			data.IsAttacking = false
		end

		task.spawn(function()
			while character.Parent and humanoid.Health > 0 do
				if humanoid.Health < humanoid.MaxHealth then
					humanoid.Health = math.min(humanoid.Health + SETTINGS.HEALTH_REGEN, humanoid.MaxHealth)
				end
				task.wait(1)
			end
		end)
	end)
end

local function CheckExploit(player)
	local userId = player.UserId
	local tracking = AttackTracking[userId]
	if not tracking then
		return false
	end

	local currentTime = tick()

	if currentTime - tracking.LastResetTime >= 1 then
		tracking.AttacksInLastSecond = 0
		tracking.LastResetTime = currentTime
	end

	tracking.AttacksInLastSecond = tracking.AttacksInLastSecond + 1

	if tracking.AttacksInLastSecond > 5 then
		return true
	end

	return false
end

local function GetTarget(attacker, range)
	local character = attacker.Character
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local closestTarget = nil
	local closestDistance = range

	for _, descendant in pairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") and descendant.Parent ~= character then
			local targetCharacter = descendant.Parent
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")

			if targetRoot and descendant.Health > 0 then
				local distance = (rootPart.Position - targetRoot.Position).Magnitude

				if distance < closestDistance then
					local direction = (targetRoot.Position - rootPart.Position).Unit
					local lookVector = rootPart.CFrame.LookVector
					local dot = direction:Dot(lookVector)

					if dot > 0.5 then
						closestDistance = distance
						closestTarget = targetCharacter
					end
				end
			end
		end
	end

	return closestTarget
end

local function ApplyDamage(targetCharacter, damage, isHeavy, attackerPlayer, attackerRoot, combo)
	if not targetCharacter then
		return false, false
	end

	local humanoid = targetCharacter:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, false
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	local isBlocking = false

	if targetPlayer then
		local targetData = PlayerData[targetPlayer.UserId]
		if targetData and targetData.IsBlocking then
			isBlocking = true
			damage = damage * SETTINGS.BLOCK_DAMAGE_REDUCTION
			BlockEvent:FireClient(targetPlayer, "blocked")
		end
	end

	humanoid:TakeDamage(damage)

	local rootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	if rootPart and attackerRoot then
		local knockbackPower = 25
		local knockbackHeight = 10

		local comboMultiplier = 1 + (combo * 0.15)

		if isBlocking then
			knockbackPower = 15
			knockbackHeight = 5
			comboMultiplier = 1
		elseif isHeavy then
			knockbackPower = 50
			knockbackHeight = 20
		elseif combo == 4 then
			knockbackPower = 60
			knockbackHeight = 25
		end

		knockbackPower = knockbackPower * comboMultiplier
		knockbackHeight = knockbackHeight * comboMultiplier

		local direction = (rootPart.Position - attackerRoot.Position).Unit

		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
		bodyVelocity.Velocity = direction * knockbackPower + Vector3.new(0, knockbackHeight, 0)
		bodyVelocity.Parent = rootPart

		Debris:AddItem(bodyVelocity, 0.15)

		if combo == 4 and not isBlocking then
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			task.delay(0.5, function()
				if humanoid.Parent then
					humanoid.WalkSpeed = 16
					humanoid.JumpPower = 50
				end
			end)
		end
	end

	return true, isBlocking
end

M1Event.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local data = PlayerData[player.UserId]
	if not data then
		return
	end

	if CheckExploit(player) then
		return
	end

	if data.IsBlocking then
		return
	end

	if data.IsAttacking then
		return
	end

	local currentTime = tick()

	if currentTime - data.LastM1 < SETTINGS.MINIMUM_ATTACK_DELAY then
		return
	end

	if data.LastM1 > 0 and currentTime - data.LastM1 > SETTINGS.COMBO_RESET_TIME then
		data.Combo = 0
	end

	data.Combo = data.Combo + 1
	if data.Combo > SETTINGS.COMBO_MAX then
		data.Combo = 1
	end

	data.IsAttacking = true
	data.LastM1 = currentTime
	data.AttackCount = data.AttackCount + 1

	M1Event:FireClient(player, data.Combo)

	local animDuration
	if data.Combo == 1 then
		animDuration = SETTINGS.ANIM_DURATION_M1
	elseif data.Combo == 2 then
		animDuration = SETTINGS.ANIM_DURATION_M2
	elseif data.Combo == 3 then
		animDuration = SETTINGS.ANIM_DURATION_M3
	elseif data.Combo == 4 then
		animDuration = SETTINGS.ANIM_DURATION_M4
	else
		animDuration = SETTINGS.ANIM_DURATION_M1
	end

	if data.Combo >= SETTINGS.COMBO_MAX and not data.ComboResetScheduled then
		data.ComboResetScheduled = true
		task.delay(SETTINGS.COMBO_FINISHER_COOLDOWN + animDuration, function()
			data.Combo = 0
			data.ComboResetScheduled = false
		end)
	end

	task.delay(animDuration, function()
		data.IsAttacking = false
	end)
end)

DamageEvent.OnServerEvent:Connect(function(player, combo)
	local character = player.Character
	if not character then
		return
	end

	local data = PlayerData[player.UserId]
	if not data then
		return
	end

	local currentTime = tick()

	if currentTime - data.LastDamageRequest < 0.2 then
		return
	end

	data.LastDamageRequest = currentTime

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local targetCharacter = GetTarget(player, SETTINGS.M1_RANGE)

	local velocity = rootPart.AssemblyLinearVelocity.Magnitude
	local isHeavy = velocity > SETTINGS.HEAVY_VELOCITY_THRESHOLD

	local hitSuccess = false
	local wasBlocked = false

	if targetCharacter then
		local damage = isHeavy and SETTINGS.HEAVY_DAMAGE or SETTINGS.M1_DAMAGE

		if combo == 4 then
			damage = damage * 1.5
		end

		hitSuccess, wasBlocked = ApplyDamage(targetCharacter, damage, isHeavy, player, rootPart, combo)

		DamageEvent:FireClient(player, targetCharacter, true, wasBlocked)
	else
		DamageEvent:FireClient(player, nil, false, false)
	end
end)

BlockEvent.OnServerEvent:Connect(function(player, isBlocking)
	local data = PlayerData[player.UserId]
	if not data then
		return
	end

	data.IsBlocking = isBlocking
end)

Players.PlayerAdded:Connect(InitializePlayer)

for _, player in pairs(Players:GetPlayers()) do
	InitializePlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData[player.UserId] = nil
	AttackTracking[player.UserId] = nil
end)

task.spawn(function()
	while true do
		task.wait(60)
		for userId, data in pairs(PlayerData) do
			local player = Players:GetPlayerByUserId(userId)
		end
	end
end)
