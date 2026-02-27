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
local _remotes: { [string]: RemoteEvent } = {}

-- ── Constructor ───────────────────────────────────────────────────────────────
--[[
	DamageModule.new(attacker)
	Creates a scoped damage applier tied to the attacking player.
]]
function DamageModule.new(attacker: Player)
	assert(RunService:IsServer(), "DamageModule must only run on the server!")

	local self = setmetatable({}, DamageModule)
	self._attacker = attacker
	return self
end

-- ── Module-level init (call once from CombatService) ─────────────────────────
--[[
	DamageModule.init(remoteTable)
	remoteTable: { ApplyHitEffect: RemoteEvent, HitConfirm: RemoteEvent }
	Provides the remotes needed for visual/audio feedback.
]]
function DamageModule.init(remoteTable: { [string]: RemoteEvent })
	_remotes = remoteTable
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
		victim     : Player — receiving the hit
		amount     : number — raw damage
		comboIndex : number — which hit in the chain

	Returns true if damage was applied, false if victim was already dead / invalid.

	On success fires:
	  • ApplyHitEffect → ALL clients  (hit-reaction animation on victim)
	  • HitConfirm     → ALL clients  (red highlight on victim + hit sound + cam shake on attacker)
]]
function DamageModule:Apply(victim: Player, amount: number, comboIndex: number): boolean
	local attacker = self._attacker
	if victim == attacker then return false end

	local victimChar = victim.Character
	if not victimChar then return false end

	local humanoid: Humanoid? = victimChar:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	-- ── Apply damage ─────────────────────────────────────────────────────────
	humanoid:TakeDamage(amount)

	-- ── Hit-reaction animation (everyone sees this) ──────────────────────────
	local reactionAnim = _pickRandom(HIT_REACTIONS)
	if _remotes.ApplyHitEffect then
		_remotes.ApplyHitEffect:FireAllClients(victim, reactionAnim, comboIndex)
	end

	-- ── HitConfirm: highlight + hit sound + camera shake ────────────────────
	-- Payload: attacker (for cam shake / hit sound on their client),
	--          victim   (for highlight on all clients),
	--          comboIndex (to pick the right sound / shake profile)
	if _remotes.HitConfirm then
		_remotes.HitConfirm:FireAllClients(attacker, victim, comboIndex)
	end

	return true
end

--[[
	:ApplyBlocked(victim, amount)
	Reduced damage when the victim is blocking; plays a block-reaction animation.
	Does NOT fire HitConfirm (no camera shake / hit sound for blocked hits).
]]
function DamageModule:ApplyBlocked(victim: Player, amount: number): boolean
	local blockDamage = math.floor(amount * 0.15)  -- 15% chip damage on block
	local victimChar  = victim.Character
	if not victimChar then return false end

	local humanoid: Humanoid? = victimChar:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	humanoid:TakeDamage(blockDamage)

	local reactionAnim = _pickRandom(BLOCK_REACTIONS)
	if _remotes.ApplyHitEffect then
		_remotes.ApplyHitEffect:FireAllClients(victim, reactionAnim, 0)
	end

	-- Optionally fire a softer BlockHit confirm here in Phase 2

	return true
end

return DamageModule