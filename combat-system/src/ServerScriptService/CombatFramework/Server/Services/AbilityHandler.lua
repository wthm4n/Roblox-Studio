--[[
	AbilityHandler.lua
	Dynamically loads every ModuleScript in the Abilities folder.
	No core edits needed to add a new ability — just drop in a module.

	Each ability module must expose:
	  .Name    : string
	  .Cooldown: number   (seconds)
	  .Stamina : number   (stamina cost)
	  :Execute(player, inputData, ctx)
]]

local AbilityHandler = {}
AbilityHandler.__index = AbilityHandler

-- ─── Constructor ──────────────────────────────────────────────────────────────

function AbilityHandler.new(abilitiesFolder: Folder)
	local self = setmetatable({}, AbilityHandler)
	-- [abilityName] = abilityModule
	self._registry = {}
	self:_LoadAll(abilitiesFolder)
	return self
end

-- ─── Loader ───────────────────────────────────────────────────────────────────

function AbilityHandler:_LoadAll(folder: Folder)
	if not folder then
		warn("[AbilityHandler] No abilities folder provided")
		return
	end

	for _, module in ipairs(folder:GetChildren()) do
		if not module:IsA("ModuleScript") then continue end

		local ok, result = pcall(require, module)
		if not ok then
			warn("[AbilityHandler] Error requiring: " .. module.Name, result)
			continue
		end

		-- Support single ability OR array of abilities from one file
		local list = (type(result) == "table" and result[1]) and result or { result }

		for _, ability in ipairs(list) do
			if ability and ability.Name then
				self._registry[ability.Name] = ability
				print(("[AbilityHandler] Loaded: %s (CD: %ds, Stamina: %d)"):format(
					ability.Name,
					ability.Cooldown or 0,
					ability.Stamina  or 0
				))
			else
				warn("[AbilityHandler] Skipping invalid entry in: " .. module.Name)
			end
		end
	end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
	Execute(player, abilityName, inputData, ctx)

	ctx = {
		hitbox  : HitboxService,
		damage  : DamageService,
		status  : StatusService,
		combo   : ComboService,
		states  : { [userId]: PlayerState },
		events  : RemoteEvent,   -- for firing VFX to clients
	}
]]
function AbilityHandler:Execute(player: Player, abilityName: string, inputData: {}, ctx: {})
	local ability = self._registry[abilityName]
	if not ability then
		warn("[AbilityHandler] Unknown ability: " .. tostring(abilityName))
		return
	end

	ability:Execute(player, inputData, ctx)
end

function AbilityHandler:Has(abilityName: string): boolean
	return self._registry[abilityName] ~= nil
end

function AbilityHandler:GetCooldown(abilityName: string): number
	local ability = self._registry[abilityName]
	return ability and (ability.Cooldown or 0) or 0
end

function AbilityHandler:GetStaminaCost(abilityName: string): number
	local ability = self._registry[abilityName]
	return ability and (ability.Stamina or 0) or 0
end

return AbilityHandler