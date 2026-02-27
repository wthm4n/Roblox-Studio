--[[
	DamageModule.lua  (SERVER)
	Single source of truth for applying damage, hit reactions, and kill logic.
	Never called from the client.

	Place in: ServerScriptService/Modules/DamageModule
]]

local DamageModule = {}
DamageModule.__index = DamageModule

-- ── Services ──────────────────────────────────────────────────────────────────
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Lazy deps (set via DamageModule.init) ────────────────────────────────────
local _remotes:  { [string]: RemoteEvent } = {}
local _stunModule = nil   -- injected via DamageModule.init
local _stunDurations: { [number]: number } = {}

-- ── Constructor ───────────────────────────────────────────────────────────────
function DamageModule.new(attacker: Player)
	assert(RunService:IsServer(), "DamageModule must only run on the server!")
	local self = setmetatable({}, DamageModule)
	self._attacker = attacker
	return self
end

-- ── Module-level init (call once from CombatService) ─────────────────────────
--[[
	DamageModule.init(remoteTable, stunModule, stunDurations)
	  remoteTable   : { ApplyHitEffect, HitConfirm }
	  stunModule    : StunModule (the require'd module table)
	  stunDurations : CombatSettings.Stun.Duration table
]]
function DamageModule.init(remoteTable, stunModule, stunDurations)
	_remotes       = remoteTable
	_stunModule    = stunModule
	_stunDurations = stunDurations or {}
end

-- ── Private ───────────────────────────────────────────────────────────────────

local HIT_REACTIONS   = { "HitReaction1", "HitReaction2", "HitReaction3", "HitReaction4", "HitReaction5" }
local BLOCK_REACTIONS = { "BlockingHitReaction1", "BlockingHitReaction2", "BlockingHitReaction3", "BlockingHitReaction4", "BlockingHitReaction5" }

local function _pickRandom(t: { string }): string
	return t[math.random(1, #t)]
end

-- ── Public ────────────────────────────────────────────────────────────────────

--[[
	:Apply(victim, amount, comboIndex)
	On success:
	  • TakeDamage on victim's Humanoid
	  • Applies / refreshes stun (WalkSpeed=0, JumpPower=0) for combo duration
	  • Fires ApplyHitEffect → ALL clients  (hit-reaction animation)
	  • Fires HitConfirm     → ALL clients  (highlight + sound + cam shake)
]]
function DamageModule:Apply(victim: Player, amount: number, comboIndex: number): boolean
	local attacker = self._attacker
	if victim == attacker then return false end

	local victimChar = victim.Character
	if not victimChar then return false end

	local humanoid: Humanoid? = victimChar:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	-- ── Damage ───────────────────────────────────────────────────────────────
	humanoid:TakeDamage(amount)

	-- ── Stun — apply / refresh ────────────────────────────────────────────────
	-- Duration is keyed by comboIndex; fall back to index 1 if out of range.
	if _stunModule then
		local duration = _stunDurations[comboIndex] or _stunDurations[1] or 0.55
		_stunModule.Apply(victim, duration)
	end

	-- ── Hit-reaction animation ────────────────────────────────────────────────
	local reactionAnim = _pickRandom(HIT_REACTIONS)
	if _remotes.ApplyHitEffect then
		_remotes.ApplyHitEffect:FireAllClients(victim, reactionAnim, comboIndex)
	end

	-- ── HitConfirm: highlight + hit sound + camera shake ─────────────────────
	if _remotes.HitConfirm then
		_remotes.HitConfirm:FireAllClients(attacker, victim, comboIndex)
	end

	return true
end

--[[
	:ApplyBlocked(victim, amount)
	Chip damage on block. No stun — blocking player keeps mobility.
]]
function DamageModule:ApplyBlocked(victim: Player, amount: number): boolean
	local blockDamage = math.floor(amount * 0.15)
	local victimChar  = victim.Character
	if not victimChar then return false end

	local humanoid: Humanoid? = victimChar:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	humanoid:TakeDamage(blockDamage)

	local reactionAnim = _pickRandom(BLOCK_REACTIONS)
	if _remotes.ApplyHitEffect then
		_remotes.ApplyHitEffect:FireAllClients(victim, reactionAnim, 0)
	end

	return true
end

return DamageModule