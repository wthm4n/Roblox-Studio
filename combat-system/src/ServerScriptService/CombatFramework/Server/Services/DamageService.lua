--[[
	DamageService.lua
	Calculates and applies damage to players or NPCs.
	Formula: Base × ComboMult × StatMult × CritMult × PositionalBonus − Armor
]]

local DamageService = {}
DamageService.__index = DamageService

local CRIT_CHANCE     = 0.15
local CRIT_MULT       = 1.75
local BACKSTAB_BONUS  = 1.30
local AIRBORNE_BONUS  = 1.20
local BLOCK_REDUCTION = 0.65
local ARMOR_SCALE     = 0.50

function DamageService.new()
	return setmetatable({}, DamageService)
end

-- ─── Calculate ────────────────────────────────────────────────────────────────

function DamageService:Calculate(attackerState, victimState, opts)
	local base = opts.Base or 10

	local comboMult = 1
	if opts.ComboIndex then
		comboMult = 1 + (opts.ComboIndex - 1) * 0.08
	end

	local statMult = 1
	if attackerState then
		statMult = 1 + (attackerState.Stats.Strength - 10) * 0.05
	end

	local isCrit   = false
	local critMult = 1
	if opts.CanCrit and math.random() < CRIT_CHANCE then
		isCrit   = true
		critMult = CRIT_MULT
	end

	local posMult = 1
	if opts.IsBackstab then posMult *= BACKSTAB_BONUS end
	if opts.IsAirborne then posMult *= AIRBORNE_BONUS end

	local armor = victimState and (victimState.Stats.Defense * ARMOR_SCALE) or 0

	local isBlocked = victimState
		and victimState:Is("Blocking")
		and not victimState.GuardBroken

	local blockMult = isBlocked and BLOCK_REDUCTION or 1

	local final = math.max(1, math.floor(
		base * comboMult * statMult * critMult * posMult * blockMult - armor
	))

	return { Final = final, IsCrit = isCrit, IsBlocked = isBlocked }
end

-- ─── Apply ────────────────────────────────────────────────────────────────────

-- target: Player or NPC proxy { _isNPC, Character }
function DamageService:Apply(attackerState, victimState, target, opts)
	local char
	if target._isNPC then
		char = target.Character
	else
		char = target.Character  -- Player
	end

	if not char then return nil end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end

	local result = self:Calculate(attackerState, victimState, opts)

	if result.IsBlocked then
		hum:TakeDamage(result.Final)
		if victimState then
			victimState:DamageGuard(opts.Base * 0.4)
		end
	else
		hum:TakeDamage(result.Final)
	end

	return result
end

return DamageService