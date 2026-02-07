--[[
	SERVER SCRIPT
	
	Place this in: ServerScriptService
	
	This initializes the combat system on the server (authoritative).
]]
-- !strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for combat system
local CombatInitializer = ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatInitializer")
CombatInitializer = require(CombatInitializer)

-- Initialize server
CombatInitializer.SetupServer()

print("[COMBAT SYSTEM] Server initialized")

--[[
	DAMAGE PROCESSING
	Server listens for confirmed hits and applies damage
]]

local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		-- Wait a bit for combat system to initialize on the character
		task.wait(0.5)

		local combatInstance = CombatInitializer.GetCombatInstance(character)
		if not combatInstance then
			warn("No combat instance found for", player.Name)
			return
		end

		local core = combatInstance.Core

		-- Listen for hit confirmations
		core.Events.HitConfirmed.Event:Connect(function(hitData)
			local target = hitData.Target
			local damage = hitData.Damage
			local knockback = hitData.Knockback

			-- Apply damage
			local targetHumanoid = target:FindFirstChild("Humanoid")
			if targetHumanoid then
				targetHumanoid:TakeDamage(damage)

				-- Apply knockback
				local targetHRP = target:FindFirstChild("HumanoidRootPart")
				if targetHRP then
					-- Apply velocity
					targetHRP.AssemblyVelocity = knockback

					-- Force hitstun on target
					local targetCombat = CombatInitializer.GetCombatInstance(target)
					if targetCombat then
						targetCombat.Core.StateManager:ForceState("Hitstun", 15)
					end
				end
			end

			print(player.Name, "hit", target.Name, "for", damage, "damage")
		end)
	end)
end)

--[[
	ANTI-EXPLOIT CHECKS
	Server validates that actions are legal
]]

-- Example: Check for impossible combos
-- Example: Check for cooldown violations
-- Example: Check for speed exploits

-- These would be implemented in NetworkSync module
