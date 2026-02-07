--[[
	CombatUtilities.lua
	
	Shared utility functions for combat system.
	Includes validation, math helpers, and common operations.
	
	Author: [Your Name]
]]

local CombatUtilities = {}

-- ========================================
-- VALIDATION
-- ========================================

function CombatUtilities.ValidateCharacter(character)
	if not character or not character:IsDescendantOf(workspace) then
		return false, "Invalid character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "Character is dead or has no humanoid"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "Character has no HumanoidRootPart"
	end

	return true, nil, humanoid, rootPart
end

function CombatUtilities.ValidatePlayer(player)
	if not player or not player:IsDescendantOf(game:GetService("Players")) then
		return false, "Invalid player"
	end
	return true
end

-- ========================================
-- TARGETING
-- ========================================

function CombatUtilities.GetTargetsInRadius(origin: Vector3, radius: number, excludeCharacter: Model): { Model }
	local targets = {}

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Humanoid") and descendant.Parent ~= excludeCharacter then
			local targetCharacter = descendant.Parent
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")

			if targetRoot and descendant.Health > 0 then
				local distance = (origin - targetRoot.Position).Magnitude
				if distance <= radius then
					table.insert(targets, {
						Character = targetCharacter,
						Humanoid = descendant,
						RootPart = targetRoot,
						Distance = distance,
					})
				end
			end
		end
	end

	-- Sort by distance (closest first)
	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	return targets
end

function CombatUtilities.GetTargetsInCone(
	origin: Vector3,
	direction: Vector3,
	range: number,
	angleInDegrees: number,
	excludeCharacter: Model
): { Model }
	local targets = {}
	local cosAngle = math.cos(math.rad(angleInDegrees))

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Humanoid") and descendant.Parent ~= excludeCharacter then
			local targetCharacter = descendant.Parent
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")

			if targetRoot and descendant.Health > 0 then
				local distance = (origin - targetRoot.Position).Magnitude

				if distance <= range then
					local toTarget = (targetRoot.Position - origin).Unit
					local dot = direction:Dot(toTarget)

					if dot >= cosAngle then
						table.insert(targets, {
							Character = targetCharacter,
							Humanoid = descendant,
							RootPart = targetRoot,
							Distance = distance,
						})
					end
				end
			end
		end
	end

	-- Sort by distance (closest first)
	table.sort(targets, function(a, b)
		return a.Distance < b.Distance
	end)

	return targets
end

function CombatUtilities.GetTargetInFront(character: Model, range: number, angleThreshold: number): Model?
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return nil
	end

	local closestTarget = nil
	local closestDistance = range

	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("Humanoid") and descendant.Parent ~= character then
			local targetCharacter = descendant.Parent
			local targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")

			if targetRoot and descendant.Health > 0 then
				local distance = (rootPart.Position - targetRoot.Position).Magnitude

				if distance < closestDistance then
					local direction = (targetRoot.Position - rootPart.Position).Unit
					local lookVector = rootPart.CFrame.LookVector
					local dot = direction:Dot(lookVector)

					if dot > angleThreshold then
						closestDistance = distance
						closestTarget = {
							Character = targetCharacter,
							Humanoid = descendant,
							RootPart = targetRoot,
							Distance = distance,
						}
					end
				end
			end
		end
	end

	return closestTarget
end

-- ========================================
-- PHYSICS & KNOCKBACK
-- ========================================

function CombatUtilities.ApplyKnockback(
	targetRoot: BasePart,
	direction: Vector3,
	horizontalPower: number,
	verticalPower: number,
	duration: number
)
	if not targetRoot or not targetRoot:IsDescendantOf(workspace) then
		return
	end

	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)
	bodyVelocity.Velocity = (direction * horizontalPower) + Vector3.new(0, verticalPower, 0)
	bodyVelocity.Parent = targetRoot

	game:GetService("Debris"):AddItem(bodyVelocity, duration or 0.2)
end

function CombatUtilities.ApplyStun(humanoid: Humanoid, duration: number)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local originalWalkSpeed = humanoid.WalkSpeed
	local originalJumpPower = humanoid.JumpPower

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	task.delay(duration, function()
		if humanoid and humanoid.Parent then
			humanoid.WalkSpeed = originalWalkSpeed
			humanoid.JumpPower = originalJumpPower
		end
	end)
end

-- ========================================
-- MATH HELPERS
-- ========================================

function CombatUtilities.Lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function CombatUtilities.Clamp(value: number, min: number, max: number): number
	return math.min(math.max(value, min), max)
end

function CombatUtilities.RandomVector3(min: number, max: number): Vector3
	return Vector3.new(math.random(min, max), math.random(min, max), math.random(min, max))
end

function CombatUtilities.RandomInRadius(center: Vector3, radius: number): Vector3
	local angle = math.random() * math.pi * 2
	local distance = math.random() * radius

	return center + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

-- ========================================
-- TIMING & COOLDOWNS
-- ========================================

function CombatUtilities.CreateCooldownTracker()
	local cooldowns = {}

	return {
		Set = function(key: string, duration: number)
			cooldowns[key] = tick() + duration
		end,

		Get = function(key: string): number
			local endTime = cooldowns[key]
			if not endTime then
				return 0
			end

			local remaining = endTime - tick()
			return math.max(0, remaining)
		end,

		IsReady = function(key: string): boolean
			return (cooldowns[key] or 0) <= tick()
		end,

		Reset = function(key: string)
			cooldowns[key] = nil
		end,

		ResetAll = function()
			cooldowns = {}
		end,
	}
end

-- ========================================
-- ANTI-EXPLOIT
-- ========================================

function CombatUtilities.CreateRateLimiter(maxPerSecond: number)
	local requests = {}

	return {
		Check = function(key: string): boolean
			local currentTime = tick()

			-- Clean old requests
			if requests[key] then
				requests[key] = table.create(#requests[key])
				for _, timestamp in requests[key] do
					if currentTime - timestamp < 1 then
						table.insert(requests[key], timestamp)
					end
				end
			else
				requests[key] = {}
			end

			-- Check if over limit
			if #requests[key] >= maxPerSecond then
				return false
			end

			-- Add new request
			table.insert(requests[key], currentTime)
			return true
		end,

		Reset = function(key: string)
			requests[key] = nil
		end,
	}
end

return table.freeze(CombatUtilities)
