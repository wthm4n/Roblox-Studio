--[[
	PersonalityManager.lua
	Factory that creates the right personality for an NPC
	and hooks it into NPCController's update/event cycle.

	Usage (in NPCSpawner, set attributes on spawn point or model):
	  npc:SetAttribute("Personality", "Aggressive")
	  -- Options: "Passive" | "Scared" | "Aggressive" | "Tactical"
	  -- Default (nil): uses Phase 1 base behavior

	  npc:SetAttribute("EnableSquad", true)
	  -- Wraps the personality in SquadBehavior for multi-NPC coordination.
	  -- Works with ANY personality, including nil (base behavior).

	NPCController calls:
	  PersonalityManager.create(self)   in :new()
	  self.Personality:OnUpdate(dt)     in :_update()
	  self.Personality:OnDamaged(...)   in damage tracking
	  self.Personality:OnTargetFound()  in target system update
	  self.Personality:Destroy()        in :Destroy()
--]]

local Passive       = require(game.ServerScriptService.NPCAIModule.Personalities.Passive)
local Scared        = require(game.ServerScriptService.NPCAIModule.Personalities.Scared)
local Aggressive    = require(game.ServerScriptService.NPCAIModule.Personalities.Aggressive)
local Tactical      = require(game.ServerScriptService.NPCAIModule.Personalities.Tactical)
local SquadBehavior = require(game.ServerScriptService.NPCAIModule.Personalities.SquadBehavior)

local PersonalityManager = {}

local REGISTRY = {
	Passive    = Passive,
	Scared     = Scared,
	Aggressive = Aggressive,
	Tactical   = Tactical,
}

-- No-op stub for NPCs with no personality set
local function makeStub(): any
	return {
		Name            = "None",
		OnUpdate        = function() end,
		OnStateChanged  = function() end,
		OnTargetFound   = function() end,
		OnTargetLost    = function() end,
		OnDamaged       = function() end,
		OnSquadAlert    = function() end,
		CanEnterCombat  = function() return true end,
		ShouldForceFlee = function() return false end,
		GetFleeSpeed    = function() return nil end,
		Destroy         = function() end,
	}
end

-- Creates and returns the right personality instance for an NPCController
function PersonalityManager.create(entity: any): any
	local personalityName = entity.NPC:GetAttribute("Personality")
	local enableSquad     = entity.NPC:GetAttribute("EnableSquad") == true

	print("[PM DEBUG] NPC:", entity.NPC.Name,
		"| Personality:", personalityName,
		"| Squad:", enableSquad)

	-- Build base personality
	local instance: any
	local PersonalityClass = personalityName and REGISTRY[personalityName]

	if PersonalityClass then
		instance = PersonalityClass.new(entity)
		print(("[PersonalityManager] '%s' assigned to %s"):format(personalityName, entity.NPC.Name))
	else
		instance = makeStub()
	end

	-- Optionally wrap with squad coordination
	if enableSquad then
		instance = SquadBehavior.wrap(entity, instance)
		print(("[PersonalityManager] Squad layer added to %s"):format(entity.NPC.Name))
	end

	return instance
end

return PersonalityManager