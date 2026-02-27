--[[
	PersonalityManager.lua
	Factory that creates the right personality for an NPC
	and hooks it into NPCController's update/event cycle.

	Usage (in NPCSpawner, set attribute on model):
	  npc:SetAttribute("Personality", "Aggressive")
	  -- Options: "Passive" | "Scared" | "Aggressive" | "Tactical"
	  -- Default (nil): uses Phase 1 base behavior

	NPCController calls:
	  PersonalityManager.attach(self)   in :new()
	  self.Personality:OnUpdate(dt)     in :_update()
	  self.Personality:OnDamaged(...)   in damage tracking
	  self.Personality:OnTargetFound()  in target system update
	  self.Personality:Destroy()        in :Destroy()
--]]

local Passive    = require(game.ServerScriptService.NPCAIModule.Personalities.Passive)
local Scared     = require(game.ServerScriptService.NPCAIModule.Personalities.Scared)
local Aggressive = require(game.ServerScriptService.NPCAIModule.Personalities.Aggressive)
local Tactical   = require(game.ServerScriptService.NPCAIModule.Personalities.Tactical)

local PersonalityManager = {}

local REGISTRY = {
	Passive    = Passive,
	Scared     = Scared,
	Aggressive = Aggressive,
	Tactical   = Tactical,
}

-- Creates and returns the right personality instance for an NPCController
function PersonalityManager.create(entity: any): any
	local personalityName = entity.NPC:GetAttribute("Personality")

	if not personalityName or not REGISTRY[personalityName] then
		-- No personality set — return a no-op stub
		return {
			Name            = "None",
			OnUpdate        = function() end,
			OnStateChanged  = function() end,
			OnTargetFound   = function() end,
			OnTargetLost    = function() end,
			OnDamaged       = function() end,
			Destroy         = function() end,
		}
	end

	local PersonalityClass = REGISTRY[personalityName]
	local instance = PersonalityClass.new(entity)

	print(("[PersonalityManager] '%s' assigned to %s"):format(personalityName, entity.NPC.Name))
	return instance
end

return PersonalityManager
