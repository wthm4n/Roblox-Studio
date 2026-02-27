--[[
	NPCSpawner.lua  (ServerScript — place in ServerScriptService)
	Manages spawning NPC instances with their brains.

	Setup:
	  1. Place this script in ServerScriptService
	  2. Create a folder called "NPCSpawnPoints" in Workspace
	     Each SpawnPoint should be a BasePart with optional attributes:
	       - PatrolFolder: string  — name of a Folder in Workspace containing patrol BaseParts
	       - RespawnDelay: number  — override respawn time (default 10s)
	  3. Put your NPC model in ReplicatedStorage.NPCAssets
	     The model needs: Humanoid, HumanoidRootPart, (optional) AttackAnim
--]]

local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local ServerScriptService  = game:GetService("ServerScriptService")

-- Adjust these paths to match your project layout
local NPCController = require(game.ServerScriptService.NPCAIModule.NPCController) -- Server folder
local Config        = require(game.ReplicatedStorage.Shared.Config) -- ReplicatedStorage.Shared folder

local NPCAssets     = ReplicatedStorage:WaitForChild("NPCAssets")
local SpawnFolder   = workspace:WaitForChild("NPCSpawnPoints")

local RESPAWN_DELAY = 10  -- seconds, default

-- ─── Spawner ───────────────────────────────────────────────────────────────

local NPCSpawner = {}

local activeNPCs: { [Model]: any } = {}  -- model → NPCController

local function getPatrolPoints(spawnPart: BasePart): { BasePart }
	local folderName = spawnPart:GetAttribute("PatrolFolder")
	if folderName then
		local folder = workspace:FindFirstChild(folderName)
		if folder then
			return folder:GetChildren() :: { BasePart }
		end
	end
	return {}
end

local function spawnNPC(templateName: string, spawnPart: BasePart)
	local template = NPCAssets:FindFirstChild(templateName)
	if not template then
		warn("[NPCSpawner] Template not found: " .. templateName)
		return
	end

	local npc = template:Clone() :: Model
	npc.Name  = templateName .. "_" .. tostring(math.random(1000, 9999))
	npc:SetAttribute("NPCID", math.random(10000, 99999))

	-- Position at spawn point
	local root = npc:FindFirstChild("HumanoidRootPart") :: BasePart
	if root then
		root.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
	end

	npc.Parent = workspace

	local patrolPoints = getPatrolPoints(spawnPart)
	local brain        = NPCController.new(npc, patrolPoints)
	activeNPCs[npc]   = brain

	-- Auto-respawn on death
	local hum = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	hum.Died:Connect(function()
		activeNPCs[npc] = nil
		local delay = spawnPart:GetAttribute("RespawnDelay") or RESPAWN_DELAY
		task.delay(delay, function()
			if spawnPart.Parent then  -- spawn point still exists
				spawnNPC(templateName, spawnPart)
			end
		end)
	end)

	print(("[NPCSpawner] Spawned '%s' at %s"):format(npc.Name, tostring(spawnPart.Position)))
	return npc
end

function NPCSpawner.init()
	for _, spawnPart in ipairs(SpawnFolder:GetChildren()) do
		if not spawnPart:IsA("BasePart") then continue end

		local templateName = spawnPart:GetAttribute("NPCTemplate") or "EnemyNPC"
		spawnNPC(templateName, spawnPart)
	end

	-- Handle spawn points added at runtime
	SpawnFolder.ChildAdded:Connect(function(child)
		if child:IsA("BasePart") then
			local templateName = child:GetAttribute("NPCTemplate") or "EnemyNPC"
			task.wait(0.1)  -- let attributes initialize
			spawnNPC(templateName, child)
		end
	end)

	print("[NPCSpawner] Initialized. Active NPCs:", #workspace:GetChildren())
end

-- ─── Optional: expose damage helper for weapons ───────────────────────────
-- Call this from your weapon scripts to properly attribute damage to a player:
--   NPCSpawner.DamageNPC(npcModel, damagingPlayer, damageAmount)

function NPCSpawner.DamageNPC(npc: Model, attacker: Player, amount: number)
	local brain = activeNPCs[npc]
	if brain then
		brain.TargetSys:RegisterThreat(attacker, amount)
		local hum = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
		if hum then
			hum:TakeDamage(amount)
		end
	end
end

-- ─── Boot ──────────────────────────────────────────────────────────────────

NPCSpawner.init()

return NPCSpawner
