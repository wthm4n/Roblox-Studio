--[[
	CombatUtilities.lua
	
	Professional combat utilities with spatial hitbox system.
	Supports multi-target hits, camera-based detection, and dash combat.
	
	Author: Combat System Rewrite
]]

local Players = game:GetService("Players")

local CombatUtilities = {}

-- ========================================
-- VALIDATION
-- ========================================

function CombatUtilities.ValidatePlayer(player: Player): boolean
	return player and player:IsA("Player") and player.Parent
end

function CombatUtilities.ValidateCharacter(character: Model): (boolean, string?, Humanoid?, BasePart?)
	if not character or not character.Parent then
		return false, "No character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false, "Dead or no humanoid"
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return false, "No HumanoidRootPart"
	end

	return true, nil, humanoid, rootPart
end

-- ========================================
-- SPATIAL HITBOX SYSTEM (Multi-Target)
-- ========================================

--[[
	Gets ALL valid targets in a spherical hitbox around the attacker.
	Supports:
	- Multiple targets at once
	- Camera-relative direction checking
	- Dash combat (ignores angle when dashing)
	- Customizable range and angle
]]
function CombatUtilities.GetTargetsInHitbox(
	attackerCharacter: Model,
	range: number,
	maxAngle: number, -- In degrees (e.g., 60 = 60 degree cone)
	cameraLookVector: Vector3?, -- Optional: for camera-based attacks
	isDashing: boolean? -- If true, hits in all directions
): { { Character: Model, Humanoid: Humanoid, RootPart: BasePart } }
	local targets = {}

	local attackerRoot = attackerCharacter:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then
		return targets
	end

	-- Determine forward direction (camera or character facing)
	local forwardVector = cameraLookVector or attackerRoot.CFrame.LookVector
	local attackerPos = attackerRoot.Position

	-- Find all characters in range
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character and character ~= attackerCharacter then
			local isValid, _, targetHumanoid, targetRoot = CombatUtilities.ValidateCharacter(character)

			if isValid then
				local distance = (targetRoot.Position - attackerPos).Magnitude

				-- Check range
				if distance <= range then
					-- Check angle (unless dashing = 360 degree hits)
					local angleCheck = true

					if not isDashing then
						local toTarget = (targetRoot.Position - attackerPos).Unit
						local dotProduct = forwardVector:Dot(toTarget)
						local angleInDegrees = math.deg(math.acos(dotProduct))

						angleCheck = angleInDegrees <= maxAngle
					end

					if angleCheck then
						table.insert(targets, {
							Character = character,
							Humanoid = targetHumanoid,
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

-- ========================================
-- KNOCKBACK SYSTEM
-- ========================================

function CombatUtilities.ApplyKnockback(
	targetRoot: BasePart,
	direction: Vector3,
	horizontalForce: number,
	verticalForce: number,
	duration: number
)
	-- Remove existing knockback
	local existingKB = targetRoot:FindFirstChild("CombatKnockback")
	if existingKB then
		existingKB:Destroy()
	end

	-- Create new knockback
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.Name = "CombatKnockback"
	bodyVelocity.MaxForce = Vector3.new(100000, 100000, 100000)

	-- Calculate velocity (horizontal + vertical)
	local horizontalDir = Vector3.new(direction.X, 0, direction.Z).Unit
	local velocity = (horizontalDir * horizontalForce) + Vector3.new(0, verticalForce, 0)

	bodyVelocity.Velocity = velocity
	bodyVelocity.Parent = targetRoot

	-- Remove after duration
	task.delay(duration, function()
		if bodyVelocity.Parent then
			bodyVelocity:Destroy()
		end
	end)
end

-- ========================================
-- STUN SYSTEM
-- ========================================

function CombatUtilities.ApplyStun(humanoid: Humanoid, duration: number)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Store original WalkSpeed
	local originalSpeed = humanoid.WalkSpeed
	humanoid.WalkSpeed = 0

	-- Restore after duration
	task.delay(duration, function()
		if humanoid and humanoid.Health > 0 then
			humanoid.WalkSpeed = originalSpeed
		end
	end)
end

-- ========================================
-- ANTI-EXPLOIT
-- ========================================

function CombatUtilities.CreateRateLimiter(maxPerSecond: number)
	local tracker = {}

	return {
		Check = function(userId: number): boolean
			local currentTime = tick()

			if not tracker[userId] then
				tracker[userId] = { count = 1, lastReset = currentTime }
				return true
			end

			local data = tracker[userId]

			-- Reset if 1 second has passed
			if currentTime - data.lastReset >= 1 then
				data.count = 1
				data.lastReset = currentTime
				return true
			end

			-- Check limit
			if data.count >= maxPerSecond then
				return false
			end

			data.count += 1
			return true
		end,
	}
end

function CombatUtilities.CreateCooldownTracker()
	local cooldowns = {}

	return {
		IsOnCooldown = function(key: string, duration: number): boolean
			local currentTime = tick()

			if cooldowns[key] and currentTime < cooldowns[key] then
				return true
			end

			cooldowns[key] = currentTime + duration
			return false
		end,

		Reset = function(key: string)
			cooldowns[key] = nil
		end,
	}
end

return CombatUtilities
