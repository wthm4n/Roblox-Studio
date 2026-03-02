--[[
	CombatService.lua  (SERVER — Script inside ServerScriptService)
	The top-level server authority for Phase 1 combat.

	Responsibilities:
	  • Create / destroy per-player AbilityController instances
	  • Listen for client intents (UsedM1)
	  • Validate every request (cooldown, distance, facing, LOS)
	  • Spawn server hitbox and apply damage

	Place in: ServerScriptService/CombatService

	FIXES vs original:
	  • EndActive("M1") is now ALWAYS called after hitbox fires, even on a miss.
	    Previously it was only called inside the victim loop — if no victims were
	    found, Active stayed true permanently and CanUse returned "active" until
	    the combo reset. This was the main cause of "stops working for a second".
]]

print("CombatService loaded")

-- ── Services ──────────────────────────────────────────────────────────────────
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- ── Module references ─────────────────────────────────────────────────────────
local Modules = ServerScriptService:WaitForChild("Modules")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local AbilityController = require(Modules:WaitForChild("AbilityController"))
local HitboxModule = require(Modules:WaitForChild("HitboxModule"))
local DamageModule = require(Modules:WaitForChild("DamageModule"))
local StunModule = require(Modules:WaitForChild("StunModule"))
local RagdollModule = require(Modules:WaitForChild("RagdollModule"))
local CombatSettings = require(Shared:WaitForChild("CombatSettings"))

-- ── Remotes setup ─────────────────────────────────────────────────────────────
local RemotesFolder: Folder = ReplicatedStorage:WaitForChild("Remotes")

local function _getRemote(name: string): RemoteEvent
	local r = RemotesFolder:WaitForChild(name)
	assert(r and r:IsA("RemoteEvent"), ("Remote '%s' not found or wrong type"):format(name))
	return r :: RemoteEvent
end

local RE_UsedM1 = _getRemote(CombatSettings.Remotes.UsedM1)
local RE_ApplyHitEffect = _getRemote(CombatSettings.Remotes.ApplyHitEffect)
local RE_HitConfirm = _getRemote(CombatSettings.Remotes.HitConfirm)
local RE_StunApplied = _getRemote(CombatSettings.Remotes.StunApplied)
local RE_StunReleased = _getRemote(CombatSettings.Remotes.StunReleased)
local RE_TechRoll = _getRemote(CombatSettings.Remotes.TechRoll)
local RE_Ragdoll = _getRemote(CombatSettings.Remotes.Ragdoll)
local RE_RagdollEnd = _getRemote(CombatSettings.Remotes.RagdollEnd)

-- Initialise StunModule first (RagdollModule depends on it)
StunModule.init(
	{ StunApplied = RE_StunApplied, StunReleased = RE_StunReleased, TechRoll = RE_TechRoll },
	CombatSettings.Stun
)

-- Initialise RagdollModule (depends on StunModule)
RagdollModule.init({ Ragdoll = RE_Ragdoll, RagdollEnd = RE_RagdollEnd }, StunModule)

-- Initialise DamageModule with all dependencies
DamageModule.init(
	{ ApplyHitEffect = RE_ApplyHitEffect, HitConfirm = RE_HitConfirm },
	StunModule,
	RagdollModule,
	CombatSettings.Ragdoll,
	CombatSettings.Stun.Duration
)

-- ── Per-player state ──────────────────────────────────────────────────────────
type PlayerCombatState = {
	Controller: typeof(AbilityController.new(...)),
	ComboIndex: number,
	ComboTimer: thread?,
}

local playerStates: { [Player]: PlayerCombatState } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function _isFacing(attackerHRP: BasePart, targetPos: Vector3): boolean
	local dir = (targetPos - attackerHRP.Position)
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	if flatDir.Magnitude < 0.001 then
		return true
	end

	local look = attackerHRP.CFrame.LookVector
	local dot = look:Dot(flatDir.Unit)
	return dot >= CombatSettings.Combo.MinDotProduct
end

local function _hasLOS(attacker: Player, victim: Player): boolean
	local aHRP = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart")
	local vHRP = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	if not aHRP or not vHRP then
		return false
	end

	local origin = aHRP.Position
	local direction = (vHRP.Position - origin)

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { attacker.Character, victim.Character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local result = workspace:Raycast(origin, direction, rayParams)
	return result == nil
end

local function _scheduleComboReset(state: PlayerCombatState)
	if state.ComboTimer then
		task.cancel(state.ComboTimer)
	end
	state.ComboTimer = task.delay(CombatSettings.Combo.ResetDelay, function()
		state.ComboIndex = 0
		state.ComboTimer = nil
	end)
end

-- ── Player lifecycle ──────────────────────────────────────────────────────────

local function _onPlayerAdded(player: Player)
	local controller = AbilityController.new(player)
	controller:RegisterAbility("M1", {
		Cooldown = CombatSettings.Cooldowns.M1,
		StaminaCost = 0,
		Interruptible = true,
	})
	playerStates[player] = {
		Controller = controller,
		ComboIndex = 0,
		ComboTimer = nil,
	}
end

local function _onPlayerRemoving(player: Player)
	local state = playerStates[player]
	if state and state.ComboTimer then
		task.cancel(state.ComboTimer)
	end
	playerStates[player] = nil
end

Players.PlayerAdded:Connect(_onPlayerAdded)
Players.PlayerRemoving:Connect(_onPlayerRemoving)

for _, player in ipairs(Players:GetPlayers()) do
	_onPlayerAdded(player)
end

-- ── M1 Intent Handler ─────────────────────────────────────────────────────────

RE_UsedM1.OnServerEvent:Connect(function(attacker: Player)
	local state = playerStates[attacker]
	if not state then
		return
	end

	local controller = state.Controller

	-- ── 1. Cooldown gate ────────────────────────────────────────────────────
	local canUse, _reason = controller:CanUse("M1")
	if not canUse then
		return
	end

	-- ── 1b. Stun / ragdoll gate ──────────────────────────────────────────────
	if StunModule.IsStunned(attacker) or RagdollModule.IsRagdolled(attacker) then
		return
	end

	-- ── 2. Character sanity ─────────────────────────────────────────────────
	local character = attacker.Character
	if not character then
		return
	end
	local hrp: BasePart? = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- ── 3. Advance combo index ───────────────────────────────────────────────
	state.ComboIndex = (state.ComboIndex % CombatSettings.Combo.MaxHits) + 1
	local comboIndex = state.ComboIndex

	local animKey = "M" .. tostring(comboIndex)
	local animData = CombatSettings.Animations[animKey]
	if not animData then
		return
	end

	-- ── 4. Commit: start cooldown immediately ────────────────────────────────
	controller:StartCooldown("M1")

	-- ── 5. Apply movement slow ───────────────────────────────────────────────
	humanoid.WalkSpeed = humanoid.WalkSpeed * CombatSettings.Combo.MovementMult

	-- ── 6. Tell all clients to play the swing animation ──────────────────────
	-- Fired BEFORE the hitbox delay so clients get the anim + speculative
	-- sound/shake immediately (CombatClient plays those on ApplyHitEffect).
	RE_ApplyHitEffect:FireAllClients(attacker, animKey, comboIndex)

	-- ── 7. Wait for HitFrame, then fire hitbox ───────────────────────────────
	task.delay(animData.HitFrame, function()
		if not attacker.Character then
			-- Player left during windup — still end Active so it doesn't get stuck
			controller:EndActive("M1")
			return
		end

		local damage = CombatSettings.Combo.Damage[comboIndex]
			or CombatSettings.Combo.Damage[#CombatSettings.Combo.Damage]

		local hitbox = HitboxModule.new(
			attacker,
			CombatSettings.Combo.HitboxSize,
			CombatSettings.Combo.HitboxOffset,
			CombatSettings.Combo.MaxReach
		)

		local victims = hitbox:Fire()
		local damager = DamageModule.new(attacker)

		for _, victim in ipairs(victims) do
			local victimChar = victim.Character
			local victimHRP = victimChar and victimChar:FindFirstChild("HumanoidRootPart")
			if not victimHRP then
				continue
			end
			if not _isFacing(hrp, victimHRP.Position) then
				continue
			end
			if not _hasLOS(attacker, victim) then
				continue
			end
			damager:Apply(victim, damage, comboIndex)
		end

		-- ── FIX: EndActive ALWAYS called here, hit or miss ───────────────────
		-- Previously this was inside the victim loop, so a complete miss left
		-- state.Active = true forever, blocking all future M1s until combo reset.
		controller:EndActive("M1")
	end)

	-- ── 8. Restore walk speed after animation ────────────────────────────────
	task.delay(animData.Duration, function()
		if attacker.Character then
			local hum: Humanoid? = attacker.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.WalkSpeed = hum.WalkSpeed / CombatSettings.Combo.MovementMult
			end
		end
	end)

	-- ── 9. Schedule combo reset ───────────────────────────────────────────────
	_scheduleComboReset(state)
end)
