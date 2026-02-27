--[[
	AbilityController.lua  (SERVER)
	Central registry + gatekeeper for every ability.
	One instance per player, created and managed by CombatService.

	Place in: ServerScriptService/Modules/AbilityController

	Usage:
		local ac = AbilityController.new(player)

		ac:RegisterAbility("M1", {
			Cooldown    = 0.35,   -- seconds
			StaminaCost = 0,      -- optional future use
			Interruptible = true, -- can another ability cancel this one mid-swing?
		})

		if ac:CanUse("M1") then
			ac:StartCooldown("M1")
			-- … do the thing
		end
]]

local AbilityController = {}
AbilityController.__index = AbilityController

-- ── Services ──────────────────────────────────────────────────────────────────
local RunService = game:GetService("RunService")

-- ── Types ─────────────────────────────────────────────────────────────────────
type AbilityConfig = {
	Cooldown      : number,
	StaminaCost   : number?,
	Interruptible : boolean?,
}

type AbilityState = {
	Config        : AbilityConfig,
	LastUsed      : number,       -- os.clock() timestamp
	OnCooldown    : boolean,
	Active        : boolean,      -- currently in the "executing" window
}

-- ── Constructor ───────────────────────────────────────────────────────────────
function AbilityController.new(player: Player)
	assert(RunService:IsServer(), "AbilityController must only run on the server!")

	local self      = setmetatable({}, AbilityController)
	self._player    = player
	self._abilities = {} :: { [string]: AbilityState }
	self._stamina   = 100           -- future use; max stamina pool
	return self
end

-- ── Public API ────────────────────────────────────────────────────────────────

--[[
	:RegisterAbility(name, config)
	Must be called before any other method referencing this ability name.
]]
function AbilityController:RegisterAbility(name: string, config: AbilityConfig)
	assert(not self._abilities[name], ("Ability '%s' is already registered."):format(name))

	self._abilities[name] = {
		Config     = config,
		LastUsed   = -math.huge,  -- never used
		OnCooldown = false,
		Active     = false,
	}
end

--[[
	:CanUse(name) → boolean, string?
	Returns (true) if the ability may fire now.
	Returns (false, reason) if blocked, with a short reason string for debugging.
]]
function AbilityController:CanUse(name: string): (boolean, string?)
	local state = self._abilities[name]
	if not state then
		return false, "not_registered"
	end

	local now     = os.clock()
	local elapsed = now - state.LastUsed

	if elapsed < state.Config.Cooldown then
		return false, "cooldown"
	end

	if state.Active then
		return false, "active"
	end

	-- Stamina check (stub; always passes for Phase 1)
	local cost = state.Config.StaminaCost or 0
	if cost > 0 and self._stamina < cost then
		return false, "no_stamina"
	end

	return true
end

--[[
	:StartCooldown(name)
	Records the timestamp and marks the ability as active.
	Call this IMMEDIATELY when the ability begins executing so spam-clicks are blocked.
]]
function AbilityController:StartCooldown(name: string)
	local state = self._abilities[name]
	if not state then return end

	state.LastUsed   = os.clock()
	state.OnCooldown = true
	state.Active     = true

	-- Deduct stamina
	local cost = state.Config.StaminaCost or 0
	self._stamina = math.max(0, self._stamina - cost)
end

--[[
	:EndActive(name)
	Call after the ability's active/commit window closes (e.g. after hitbox fires).
	The cooldown continues, but the ability is no longer "Active" so it can be
	interrupted by other abilities marked as Interruptible = false.
]]
function AbilityController:EndActive(name: string)
	local state = self._abilities[name]
	if not state then return end
	state.Active = false
end

--[[
	:InterruptIfAllowed(name)
	Forcibly ends an active ability if it is marked Interruptible.
	Used by e.g. getting hit while mid-swing.
	Returns true if interrupt succeeded.
]]
function AbilityController:InterruptIfAllowed(name: string): boolean
	local state = self._abilities[name]
	if not state then return false end

	if state.Active and state.Config.Interruptible ~= false then
		state.Active = false
		return true
	end
	return false
end

--[[
	:GetCooldownRemaining(name) → number
	Returns seconds remaining on cooldown (0 if ready).
]]
function AbilityController:GetCooldownRemaining(name: string): number
	local state = self._abilities[name]
	if not state then return 0 end

	local elapsed = os.clock() - state.LastUsed
	return math.max(0, state.Config.Cooldown - elapsed)
end

--[[
	:IsActive(name) → boolean
]]
function AbilityController:IsActive(name: string): boolean
	local state = self._abilities[name]
	return state and state.Active or false
end

return AbilityController
