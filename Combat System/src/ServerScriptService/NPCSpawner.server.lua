--[[
	NPC SPAWNER EXAMPLE
	
	Place this in ServerScriptService
	Shows how to spawn NPCs that use the combat system
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Wait for combat system
local CombatInitializer = ReplicatedStorage:WaitForChild("Combat"):WaitForChild("CombatInitializer")
CombatInitializer = require(CombatInitializer)

--[[
	Spawn a combat NPC
	@param position - Where to spawn
	@param npcConfig - AI behavior configuration
]]
local function SpawnCombatNPC(position: Vector3, npcConfig: any?)
	-- Create NPC character (assuming you have an R6 rig in ServerStorage)
	local npcTemplate = ServerStorage:FindFirstChild("NPCTemplate")

	if not npcTemplate then
		warn("No NPCTemplate found in ServerStorage. Creating basic R6 rig...")
		-- You would normally have a pre-made R6 rig template
		-- For this example, we'll just warn
		return
	end

	local npc = npcTemplate:Clone()
	npc.Name = "CombatNPC_" .. tostring(tick())

	-- Position the NPC
	local hrp = npc:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = CFrame.new(position)
	end

	-- Parent to workspace
	npc.Parent = workspace

	-- Initialize combat system for NPC
	local combatInstance = CombatInitializer.InitializeCharacter(
		npc,
		true, -- isServer
		true, -- isNPC
		npcConfig
			or {
				AggroRange = 40,
				AttackRange = 7,
				ComboChance = 0.8, -- 80% chance to continue combos
				DashChance = 0.2, -- 20% chance to dash
				ReactionTime = 0.15,
			}
	)

	print("Spawned combat NPC:", npc.Name)

	return npc, combatInstance
end

--[[
	EXAMPLE USAGE
]]

-- Spawn a few NPCs in a circle
local spawnCenter = Vector3.new(0, 5, 0)
local radius = 20
local npcCount = 3

for i = 1, npcCount do
	local angle = (i / npcCount) * math.pi * 2
	local position = spawnCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)

	-- Different configs for variety
	local config = {
		AggroRange = 30 + (i * 10),
		AttackRange = 6 + (i * 1),
		ComboChance = 0.5 + (i * 0.1),
		DashChance = 0.1 + (i * 0.05),
		ReactionTime = 0.1 + (i * 0.05),
	}

	SpawnCombatNPC(position, config)
end

print("[NPC SPAWNER] Spawned", npcCount, "combat NPCs")

--[[
	You can also manually control NPCs by getting their combat instance:
	
	local combatInstance = CombatInitializer.GetCombatInstance(npcCharacter)
	
	-- Force attack
	combatInstance.Core:QueueInput("M1", { ComboIndex = 1 })
	
	-- Set specific target
	combatInstance.NPCController:SetTarget(playerCharacter)
	
	-- Adjust behavior
	combatInstance.NPCController:SetAggroRange(100)
]]
