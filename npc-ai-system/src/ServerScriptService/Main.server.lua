--[[
	ServerScript.lua (place in ServerScriptService)
	Example of how to spawn and configure NPCs using NPCService
--]]

local ServerScriptService = game:GetService("ServerScriptService")
local NPCService = require(ServerScriptService.NPCAIModule.NPCService)

-- ─────────────────────────────────────────────
--  EXAMPLE 1: Aggressive NPC
-- ─────────────────────────────────────────────
local aggressiveNPC = NPCService.new(
	workspace.AggressiveNPC,  -- your NPC model in Workspace
	{
		defaultState  = "aggressive",
		aggroRange    = 40,
		attackRange   = 5,
		attackDamage  = 15,
		runSpeed      = 20,
		debugMode     = true,
	}
)
aggressiveNPC:Start()


-- ─────────────────────────────────────────────
--  EXAMPLE 2: Scared NPC (flees on sight)
-- ─────────────────────────────────────────────
local scaredNPC = NPCService.new(
	workspace.ScaredNPC,
	{
		defaultState  = "scared",
		fleeRange     = 30,
		runSpeed      = 22,
		dynamicBehavior = false,  -- always scared, never fights
	}
)
scaredNPC:Start()


-- ─────────────────────────────────────────────
--  EXAMPLE 3: Patrol NPC → becomes aggressive
-- ─────────────────────────────────────────────
local patrolNPC = NPCService.new(
	workspace.PatrolNPC,
	{
		defaultState    = "patrol",
		aggroRange      = 25,
		attackRange     = 5,
		attackDamage    = 10,
		dynamicBehavior = true,   -- patrols until player spotted
		patrolLoop      = true,
		patrolWaypoints = {
			Vector3.new(10, 0, 10),
			Vector3.new(50, 0, 10),
			Vector3.new(50, 0, 50),
			Vector3.new(10, 0, 50),
		},
	}
)
patrolNPC:Start()


-- ─────────────────────────────────────────────
--  EXAMPLE 4: Passive wanderer with kill-part avoidance
-- ─────────────────────────────────────────────
local passiveNPC = NPCService.new(
	workspace.PassiveNPC,
	{
		defaultState   = "passive",
		wanderRadius   = 30,
		wanderInterval = { 3, 7 },
		-- Higher cost materials → NPC prefers to walk around them
		materialCosts  = {
			[Enum.Material.Water] = 10,
			[Enum.Material.Lava]  = 100,
		},
	}
)
passiveNPC:Start()


-- ─────────────────────────────────────────────
--  SPAWNING MANY NPCS FROM A FOLDER
-- ─────────────────────────────────────────────
for _, model in ipairs(workspace.NPCFolder:GetChildren()) do
	if model:IsA("Model") and model.PrimaryPart then
		local npc = NPCService.new(model, {
			defaultState    = model:GetAttribute("BehaviorType") or "passive",
			aggroRange      = model:GetAttribute("AggroRange") or 30,
			attackDamage    = model:GetAttribute("Damage") or 10,
			dynamicBehavior = true,
		})
		npc:Start()
	end
end
