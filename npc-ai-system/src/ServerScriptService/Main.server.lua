--[[
	Main.server.lua
	Spawns NPCs. Reads Personality from spawn point attributes.
	
	Spawn point attributes:
	  NPCTemplate  (string)  — model name in NPCAssets (default: "EnemyNPC")
	  Personality  (string)  — "Aggressive" | "Passive" | "Scared" | "Tactical" | nil
	  PatrolFolder (string)  — name of folder in Workspace with patrol BaseParts
	  RespawnDelay (number)  — seconds before respawn (default: 10)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NPCController = require(game.ServerScriptService.NPCAIModule.NPCController)
local Config        = require(game.ReplicatedStorage.Shared.Config)

local NPCAssets   = ReplicatedStorage:WaitForChild("NPCAssets")
local SpawnFolder = workspace:WaitForChild("NPCSpawnPoints")

local RESPAWN_DELAY = 10

local activeNPCs: { [Model]: any } = {}

local function getPatrolPoints(spawnPart: BasePart): { BasePart }
	local folderName = spawnPart:GetAttribute("PatrolFolder")
	if folderName then
		local folder = workspace:FindFirstChild(folderName)
		if folder then return folder:GetChildren() :: { BasePart } end
	end
	return {}
end

local function spawnNPC(templateName: string, spawnPart: BasePart)
	local template = NPCAssets:FindFirstChild(templateName)
	if not template then
		warn("[NPCSpawner] Template not found: '" .. templateName .. "' — make sure it exists in ReplicatedStorage.NPCAssets")
		return
	end

	local npc  = template:Clone() :: Model
	npc.Name   = templateName .. "_" .. tostring(math.random(1000, 9999))
	npc:SetAttribute("NPCID", math.random(10000, 99999))
	npc:SetAttribute("IsNPC", true)

	-- Read personality from spawn point and stamp it on the NPC
	local personality = spawnPart:GetAttribute("Personality")
	if personality then
		npc:SetAttribute("Personality", personality)
	end

	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	if root then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	end

	npc.Parent = workspace

	local patrolPoints = getPatrolPoints(spawnPart)
	local brain        = NPCController.new(npc, patrolPoints)
	activeNPCs[npc]   = brain

	local hum = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.Died:Connect(function()
		activeNPCs[npc] = nil
		local delay = spawnPart:GetAttribute("RespawnDelay") or RESPAWN_DELAY
		task.delay(delay, function()
			if spawnPart.Parent then
				spawnNPC(templateName, spawnPart)
			end
		end)
	end)

	local pLabel = personality and (" [" .. personality .. "]") or ""
	print(("[NPCSpawner] Spawned '%s'%s"):format(npc.Name, pLabel))
	return npc
end

-- Spawn all existing spawn points
for _, spawnPart in ipairs(SpawnFolder:GetChildren()) do
	if spawnPart:IsA("BasePart") then
		local templateName = spawnPart:GetAttribute("NPCTemplate") or "EnemyNPC"
		spawnNPC(templateName, spawnPart)
	end
end

-- Handle spawn points added at runtime
SpawnFolder.ChildAdded:Connect(function(child)
	if child:IsA("BasePart") then
		task.wait(0.1)
		local templateName = child:GetAttribute("NPCTemplate") or "EnemyNPC"
		spawnNPC(templateName, child)
	end
end)

print("[NPCSpawner] Done. Total spawned:", #workspace:GetChildren())

-- Weapon damage helper
local NPCSpawner = {}
function NPCSpawner.DamageNPC(npc: Model, attacker: Player, amount: number)
	local brain = activeNPCs[npc]
	if brain then
		brain.TargetSys:RegisterThreat(attacker, amount)
		local hum = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
		if hum then hum:TakeDamage(amount) end
	end
end

return NPCSpawner