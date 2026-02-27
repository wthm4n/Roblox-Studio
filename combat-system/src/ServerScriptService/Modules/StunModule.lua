--[[
	StunModule.lua  (SERVER)
	Manages the stun state for every player.
	One global instance — call StunModule.init() once, then use the API anywhere.

	What "stun" means in this system:
	  • Victim's WalkSpeed  → 0  (can't walk away)
	  • Victim's JumpPower  → 0  (can't jump out)
	  • Victim can't fire abilities (AbilityController gates on IsStunned)
	  • Stun auto-expires after its duration
	  • A new hit REFRESHES the stun timer (keeps them locked in combo)
	  • Finisher hit (M5) applies a longer stun since combo is resetting anyway

	ESCAPE MECHANIC — "Tech Roll":
	  • While stunned, victim can press the configured key (default: Q) to attempt
	    a tech roll — a timed escape that breaks the stun early and launches them
	    slightly backward out of combo range.
	  • Tech roll has its own cooldown so it can't be spammed.
	  • Server validates: if the roll is on cooldown or they're not stunned, ignore.

	Place in: ServerScriptService/Modules/StunModule
]]

local StunModule = {}
StunModule.__index = StunModule

-- ── Services ──────────────────────────────────────────────────────────────────
local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

-- ── Lazy init ─────────────────────────────────────────────────────────────────
local _remotes: { [string]: RemoteEvent } = {}
local _settings = nil  -- set via StunModule.init()

-- ── Per-player stun state ─────────────────────────────────────────────────────
type StunState = {
	IsStunned      : boolean,
	StunTimer      : thread?,    -- task.delay handle; cancel to refresh
	BaseWalkSpeed  : number,     -- stored so we restore the right value
	BaseJumpPower  : number,
	LastTechRoll   : number,     -- os.clock() of last successful tech roll
}

local _states: { [Player]: StunState } = {}

-- ── Module-level init ─────────────────────────────────────────────────────────
--[[
	StunModule.init(remotes, settings)
	  remotes  : { StunApplied: RemoteEvent, StunReleased: RemoteEvent }
	  settings : CombatSettings.Stun table
]]
function StunModule.init(remotes: { [string]: RemoteEvent }, settings: table)
	_remotes  = remotes
	_settings = settings

	-- Register / clean up per-player state
	Players.PlayerAdded:Connect(function(p)
		_states[p] = _newState()
	end)
	Players.PlayerRemoving:Connect(function(p)
		local s = _states[p]
		if s and s.StunTimer then task.cancel(s.StunTimer) end
		_states[p] = nil
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		_states[p] = _newState()
	end

	-- Tech roll remote listener (client sends TechRoll intent)
	if _remotes.TechRoll then
		_remotes.TechRoll.OnServerEvent:Connect(function(player: Player)
			StunModule.TryTechRoll(player)
		end)
	end
end

function _newState(): StunState
	return {
		IsStunned     = false,
		StunTimer     = nil,
		BaseWalkSpeed = 16,
		BaseJumpPower = 50,
		LastTechRoll  = -math.huge,
	}
end

-- ── Private helpers ───────────────────────────────────────────────────────────

local function _setState(player: Player): StunState?
	return _states[player]
end

-- Restore mobility to the victim. Called automatically on expiry or tech roll.
local function _release(player: Player, reason: string)
	local s = _states[player]
	if not s then return end
	if not s.IsStunned then return end

	s.IsStunned = false
	if s.StunTimer then
		task.cancel(s.StunTimer)
		s.StunTimer = nil
	end

	local char     = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = s.BaseWalkSpeed
		humanoid.JumpPower = s.BaseJumpPower
	end

	-- Notify clients (victim needs to play recovery anim; everyone sees it)
	if _remotes.StunReleased then
		_remotes.StunReleased:FireAllClients(player, reason)
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

--[[
	StunModule.Apply(victim, duration)
	  victim   : Player
	  duration : number  — seconds to stun

	If already stunned, refreshes/extends the timer (combo keeps them locked).
	Stores current WalkSpeed/JumpPower before zeroing them.
]]
function StunModule.Apply(victim: Player, duration: number)
	assert(RunService:IsServer(), "StunModule.Apply must only run on the server!")

	local s = _states[victim]
	if not s then return end

	local char     = victim.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Cancel existing timer (refresh, don't stack)
	if s.StunTimer then
		task.cancel(s.StunTimer)
		s.StunTimer = nil
	end

	-- Save base speeds only when applying fresh (not on refresh)
	if not s.IsStunned then
		s.BaseWalkSpeed = humanoid.WalkSpeed
		s.BaseJumpPower = humanoid.JumpPower
	end

	s.IsStunned        = true
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0

	-- Auto-release after duration
	s.StunTimer = task.delay(duration, function()
		s.StunTimer = nil
		_release(victim, "expired")
	end)

	-- Notify clients so the victim's screen can show a stun indicator
	if _remotes.StunApplied then
		_remotes.StunApplied:FireAllClients(victim, duration)
	end
end

--[[
	StunModule.Release(victim, reason?)
	Force-release stun immediately (e.g. on death, round end).
]]
function StunModule.Release(victim: Player, reason: string?)
	_release(victim, reason or "forced")
end

--[[
	StunModule.IsStunned(player) → boolean
]]
function StunModule.IsStunned(player: Player): boolean
	local s = _states[player]
	return s ~= nil and s.IsStunned
end

--[[
	StunModule.TryTechRoll(player)
	Called when the victim presses the escape key while stunned.
	Validates cooldown, breaks the stun, and launches the player backward.
	Returns true if the roll succeeded.
]]
function StunModule.TryTechRoll(player: Player): boolean
	assert(RunService:IsServer(), "TryTechRoll must only run on the server!")

	local s = _states[player]
	if not s then return false end
	if not s.IsStunned then return false end  -- not stunned, ignore

	-- Cooldown check
	local now = os.clock()
	local cfg  = _settings and _settings.TechRoll
	local cd   = cfg and cfg.Cooldown or 8
	if now - s.LastTechRoll < cd then return false end

	s.LastTechRoll = now

	-- Break the stun
	_release(player, "techroll")

	-- Launch player backward (away from last attacker direction)
	local char = player.Character
	local hrp: BasePart? = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local launchForce = cfg and cfg.LaunchForce or 55
		-- Backward = opposite of HRP's look vector, slight upward arc
		local dir = (-hrp.CFrame.LookVector + Vector3.new(0, 0.35, 0)).Unit
		hrp.AssemblyLinearVelocity = dir * launchForce
	end

	-- Tell clients to play the tech roll animation on this player
	if _remotes.StunReleased then
		-- reason = "techroll" is already sent by _release above; clients branch on it
	end

	return true
end

return StunModule