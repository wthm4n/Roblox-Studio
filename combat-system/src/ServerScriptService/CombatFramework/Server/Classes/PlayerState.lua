--[[
	PlayerState.lua
	Per-player data object. One instance per player, lives for the session.
	Tracks state machine, stamina, guard, combo, and active statuses.
]]

local PlayerState = {}
PlayerState.__index = PlayerState

-- ─── State Enum ───────────────────────────────────────────────────────────────

PlayerState.States = {
	Idle      = "Idle",
	Attacking = "Attacking",
	Blocking  = "Blocking",
	Dashing   = "Dashing",
	Stunned   = "Stunned",
	Ragdolled = "Ragdolled",
	Dead      = "Dead",
}

-- ─── Constructor ──────────────────────────────────────────────────────────────

function PlayerState.new(player: Player)
	local self = setmetatable({}, PlayerState)

	self.Player     = player
	self.State      = PlayerState.States.Idle

	-- Stamina
	self.Stamina    = 100
	self.MaxStamina = 100

	-- Guard / block meter
	self.GuardMeter    = 100
	self.MaxGuardMeter = 100
	self.GuardBroken   = false

	-- Combo tracking
	self.ComboIndex   = 0
	self.LastHitClock = 0

	-- Active status effects: { [statusName] = StatusEffect instance }
	self.Statuses = {}

	-- RPG stats (can be driven by DataStore)
	self.Stats = {
		Strength = 10,
		Defense  = 5,
		Speed    = 16,
		Level    = 1,
	}

	return self
end

-- ─── State Machine ────────────────────────────────────────────────────────────

function PlayerState:SetState(newState: string)
	assert(PlayerState.States[newState], "[PlayerState] Unknown state: " .. tostring(newState))
	self.State = PlayerState.States[newState]
end

function PlayerState:Is(state: string): boolean
	return self.State == PlayerState.States[state]
end

-- Returns true if the player is allowed to initiate an ability
function PlayerState:CanAct(): boolean
	return self.State == PlayerState.States.Idle
		or self.State == PlayerState.States.Attacking
end

function PlayerState:CanBlock(): boolean
	return self.State == PlayerState.States.Idle
end

function PlayerState:CanDash(): boolean
	return self.State ~= PlayerState.States.Stunned
		and self.State ~= PlayerState.States.Ragdolled
		and self.State ~= PlayerState.States.Dead
end

-- ─── Stamina ──────────────────────────────────────────────────────────────────

function PlayerState:HasStamina(amount: number): boolean
	return self.Stamina >= amount
end

-- Returns false if not enough stamina — caller should abort ability
function PlayerState:ConsumeStamina(amount: number): boolean
	if self.Stamina < amount then
		return false
	end
	self.Stamina = math.clamp(self.Stamina - amount, 0, self.MaxStamina)
	return true
end

function PlayerState:RestoreStamina(amount: number)
	self.Stamina = math.clamp(self.Stamina + amount, 0, self.MaxStamina)
end

-- ─── Guard ────────────────────────────────────────────────────────────────────

function PlayerState:DamageGuard(amount: number)
	if self.GuardBroken then return end
	self.GuardMeter = math.clamp(self.GuardMeter - amount, 0, self.MaxGuardMeter)
	if self.GuardMeter <= 0 then
		self.GuardBroken = true
	end
end

function PlayerState:RestoreGuard()
	self.GuardMeter = self.MaxGuardMeter
	self.GuardBroken = false
end

-- ─── Status Tracking ─────────────────────────────────────────────────────────

function PlayerState:HasStatus(name: string): boolean
	return self.Statuses[name] ~= nil
end

function PlayerState:AddStatus(name: string, effectInstance)
	self.Statuses[name] = effectInstance
end

function PlayerState:RemoveStatus(name: string)
	self.Statuses[name] = nil
end

-- ─── Cleanup ──────────────────────────────────────────────────────────────────

function PlayerState:Destroy()
	-- Cancel all running status threads before GC
	for _, effect in pairs(self.Statuses) do
		if effect.Cancel then
			effect:Cancel()
		end
	end
	self.Statuses = {}
end

return PlayerState