local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local AbilitiesFolder = ReplicatedStorage.Modules.Combat:WaitForChild("Abilities")

local AbilityRemotes = Instance.new("Folder")
AbilityRemotes.Name = "AbilityRemotes"
AbilityRemotes.Parent = ReplicatedStorage

local UseAbilityEvent = Instance.new("RemoteEvent")
UseAbilityEvent.Name = "UseAbility"
UseAbilityEvent.Parent = AbilityRemotes

local AbilityResultEvent = Instance.new("RemoteEvent")
AbilityResultEvent.Name = "AbilityResult"
AbilityResultEvent.Parent = AbilityRemotes

local abilityModules = {}

local function LoadAbilityModules()
	local count = 0

	for _, moduleScript in ipairs(AbilitiesFolder:GetChildren()) do
		if moduleScript:IsA("ModuleScript") and moduleScript.Name:match("^Ability%d") then
			local abilityNum = tonumber(moduleScript.Name:match("^Ability(%d)"))

			if abilityNum then
				local success, abilityModule = pcall(require, moduleScript)

				if success then
					abilityModules[abilityNum] = abilityModule
					count = count + 1
				end
			end
		end
	end
end

LoadAbilityModules()

local PlayerAbilityData = {}

local function InitializePlayer(player)
	PlayerAbilityData[player.UserId] = {
		Cooldowns = {},
		LastUsed = {},
		IsUsingAbility = false
	}

	for abilityNum, abilityModule in pairs(abilityModules) do
		PlayerAbilityData[player.UserId].Cooldowns[abilityNum] = 0
		PlayerAbilityData[player.UserId].LastUsed[abilityNum] = 0
	end
end

local function GetTargetsInRange(position, range, attacker)
	local targets = {}

	for _, descendant in pairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") and descendant.Parent ~= attacker then
			local targetChar = descendant.Parent
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

			if targetRoot and descendant.Health > 0 then
				local distance = (position - targetRoot.Position).Magnitude
				if distance <= range then
					table.insert(targets, targetChar)
				end
			end
		end
	end

	return targets
end

local function GetTargetsInCone(position, direction, range, angle, attacker)
	local targets = {}

	for _, descendant in pairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") and descendant.Parent ~= attacker then
			local targetChar = descendant.Parent
			local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")

			if targetRoot and descendant.Health > 0 then
				local distance = (position - targetRoot.Position).Magnitude

				if distance <= range then
					local toTarget = (targetRoot.Position - position).Unit
					local dot = direction:Dot(toTarget)
					local angleToTarget = math.deg(math.acos(dot))

					if angleToTarget <= angle then
						table.insert(targets, targetChar)
					end
				end
			end
		end
	end

	return targets
end

local function ApplyAbilityDamage(targetChar, damage, knockback, attackerRoot)
	local humanoid = targetChar:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	humanoid:TakeDamage(damage)

	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if targetRoot and attackerRoot and knockback then
		local direction = (targetRoot.Position - attackerRoot.Position).Unit

		local bodyVelocity = Instance.new("BodyVelocity")
		bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
		bodyVelocity.Velocity = direction * knockback.Horizontal + Vector3.new(0, knockback.Vertical, 0)
		bodyVelocity.Parent = targetRoot

		Debris:AddItem(bodyVelocity, 0.2)
	end

	return true
end

UseAbilityEvent.OnServerEvent:Connect(function(player, abilityIndex)
	local character = player.Character
	if not character then return end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local data = PlayerAbilityData[player.UserId]
	if not data then return end

	local abilityModule = abilityModules[abilityIndex]
	if not abilityModule then
		return
	end

	if data.IsUsingAbility then
		return
	end

	local currentTime = tick()
	local cooldownRemaining = data.Cooldowns[abilityIndex] - (currentTime - data.LastUsed[abilityIndex])

	if cooldownRemaining > 0 then
		return
	end

	data.IsUsingAbility = true
	data.LastUsed[abilityIndex] = currentTime
	data.Cooldowns[abilityIndex] = abilityModule.Cooldown

	if abilityModule.OnActivate then
		local success, targets = abilityModule:OnActivate(
			player,
			character,
			rootPart,
			GetTargetsInRange,
			GetTargetsInCone,
			ApplyAbilityDamage
		)

		AbilityResultEvent:FireClient(player, abilityIndex, success, targets)
	else
		AbilityResultEvent:FireClient(player, abilityIndex, false, {})
	end

	local animDuration = abilityModule.AnimationDuration or 1.0

	task.delay(animDuration, function()
		data.IsUsingAbility = false
	end)
end)

Players.PlayerAdded:Connect(InitializePlayer)

for _, player in pairs(Players:GetPlayers()) do
	InitializePlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerAbilityData[player.UserId] = nil
end)