--[[
	CombatSettings.lua
	Shared configuration for all combat-related constants.
	Place in: ReplicatedStorage/Shared/CombatSettings
]]

local CombatSettings = {}

-- ══════════════════════════════════════════
--  M1 COMBO SETTINGS
-- ══════════════════════════════════════════
CombatSettings.Combo = {
	MaxHits        = 4,          -- M1 through M4 (M5 is finisher)
	ResetDelay     = 1.2,        -- seconds before combo resets
	HitboxSize     = Vector3.new(5, 5, 4),
	HitboxOffset   = Vector3.new(0, 0, -3),  -- in front of player
	MaxReach       = 8,          -- studs; server validates
	MinDotProduct  = 0.3,        -- facing direction threshold (cos angle)
	Damage         = { 12, 14, 16, 20, 30 },  -- per hit in combo, index 5 = finisher
	MovementMult   = 0.4,        -- speed multiplier during swing
}

-- ══════════════════════════════════════════
--  COOLDOWNS  (seconds)
-- ══════════════════════════════════════════
CombatSettings.Cooldowns = {
	M1 = 0.35,
}

-- ══════════════════════════════════════════
--  ANIMATIONS
-- ══════════════════════════════════════════
CombatSettings.Animations = {
	-- M1-M5 Combo (ADD "Hit" MARKER TO EACH!)
	M1 = {
		Id       = "rbxassetid://108566685589624",
		Duration = 0.45,
		HitFrame = 0.15,
	},
	M2 = {
		Id       = "rbxassetid://121076535244470",
		Duration = 0.45,
		HitFrame = 0.15,
	},
	M3 = {
		Id       = "rbxassetid://118197196863834",
		Duration = 0.5,
		HitFrame = 0.2,
	},
	M4 = {
		Id       = "rbxassetid://76404683651972",
		Duration = 0.6,
		HitFrame = 0.25,
	},
	M5 = {
		Id       = "rbxassetid://105629270009427",  -- Finisher
		Duration = 0.75,
		HitFrame = 0.3,
	},

	-- Blocking
	Block              = "rbxassetid://133189311751347",
	BlockingHitReaction1 = "rbxassetid://74809674784324",
	BlockingHitReaction2 = "rbxassetid://139217606379358",
	BlockingHitReaction3 = "rbxassetid://131983705093197",
	BlockingHitReaction4 = "rbxassetid://116379344332047",
	BlockingHitReaction5 = "rbxassetid://109762979660797",
	BlockBroken        = "rbxassetid://110600332239093",

	-- Hit Reactions (when not blocking)
	HitReaction1 = "rbxassetid://135435525629845",
	HitReaction2 = "rbxassetid://90491820229603",
	HitReaction3 = "rbxassetid://133746302611824",
	HitReaction4 = "rbxassetid://98605161276665",
	HitReaction5 = "rbxassetid://95965894669114",
}

-- ══════════════════════════════════════════
--  AUDIO
--  Hit sounds play ONLY on confirmed hits (via HitConfirm remote).
--  Swing "whoosh" sounds are NOT played — add them here later if desired.
-- ══════════════════════════════════════════
CombatSettings.Audio = {
	-- Played on the attacker's client when a hit is confirmed by the server.
	M1Sound    = "rbxassetid://137630794322989",
	M2Sound    = "rbxassetid://137630794322989",
	M3Sound    = "rbxassetid://137630794322989",
	M4Sound    = "rbxassetid://137630794322989",
	M5Sound    = "rbxassetid://137630794322989",
	BlockHit   = "rbxassetid://137630794322989",
	BlockBreak = "rbxassetid://137630794322989",
}

-- ══════════════════════════════════════════
--  HIT HIGHLIGHT  (red flash on damaged character)
-- ══════════════════════════════════════════
CombatSettings.HitHighlight = {
	FillColor       = Color3.fromRGB(255, 40, 40),
	OutlineColor    = Color3.fromRGB(255, 0, 0),
	FillTransparency    = 0.35,
	OutlineTransparency = 0,
	Duration        = 0.18,   -- seconds before highlight is removed
}

-- ══════════════════════════════════════════
--  CAMERA SHAKE  (attacker's local camera on each M1 hit)
-- ══════════════════════════════════════════
CombatSettings.CameraShake = {
	-- Per combo hit: { magnitude, duration (s), frequency }
	-- Finisher (M5) is index 5 and hits harder.
	[1] = { Magnitude = 0.25, Duration = 0.12, Frequency = 18 },
	[2] = { Magnitude = 0.28, Duration = 0.12, Frequency = 18 },
	[3] = { Magnitude = 0.32, Duration = 0.14, Frequency = 20 },
	[4] = { Magnitude = 0.38, Duration = 0.15, Frequency = 20 },
	[5] = { Magnitude = 0.65, Duration = 0.22, Frequency = 14 },  -- finisher
}

-- ══════════════════════════════════════════
--  STUN SYSTEM
-- ══════════════════════════════════════════
CombatSettings.Stun = {
	-- Stun duration per combo hit index (seconds).
	-- Each hit REFRESHES the timer — victim stays locked for the full window of the NEXT hit.
	-- These are intentionally long so the ragdoll plays out properly.
	-- Index 5 = M5 finisher — longest stun, combo resets after it anyway.
	Duration = {
		[1] = 1.0,    -- M1
		[2] = 1.0,    -- M2
		[3] = 1.1,    -- M3
		[4] = 1.2,    -- M4
		[5] = 2.0,    -- M5 finisher — full knockdown
	},

	-- Tech Roll — the victim's escape option.
	TechRoll = {
		Key            = "Q",      -- Enum.KeyCode string, resolved on client
		Cooldown       = 8,        -- seconds between tech rolls
		LaunchForce    = 60,       -- backward velocity (studs/s)
		EarliestWindow = 0.08,     -- ignore input in first N seconds (anti-mash)
	},
}

-- ══════════════════════════════════════════
--  RAGDOLL SYSTEM
-- ══════════════════════════════════════════
CombatSettings.Ragdoll = {
	-- Launch force applied away from attacker on each hit (studs/s).
	-- Increases with combo depth so later hits feel heavier.
	LaunchForce = {
		[1] = 28,    -- M1
		[2] = 30,    -- M2
		[3] = 33,    -- M3
		[4] = 38,    -- M4
		[5] = 60,    -- M5 finisher — big knockback
	},
	-- Ragdoll duration mirrors stun duration (both come from CombatSettings.Stun.Duration).
	-- Player is in ragdoll state the ENTIRE time they are stunned.
}

-- ══════════════════════════════════════════
--  REMOTES  (string keys only – actual RemoteEvents live in ReplicatedStorage)
-- ══════════════════════════════════════════
CombatSettings.Remotes = {
	UsedM1          = "UsedM1",
	ApplyHitEffect  = "ApplyHitEffect",
	HitConfirm      = "HitConfirm",   -- (attacker, victim, comboIndex) on confirmed hit

	-- Stun
	StunApplied     = "StunApplied",   -- (victim, duration)
	StunReleased    = "StunReleased",  -- (victim, reason: "expired"|"techroll"|"forced"|"ragdoll_recover")
	TechRoll        = "TechRoll",      -- FireServer from victim (intent only)

	-- Ragdoll
	-- Ragdoll    → FireAllClients(victim, true)   — start ragdoll, disable Animate
	-- RagdollEnd → FireAllClients(victim)         — recover, re-enable Animate
	Ragdoll         = "Ragdoll",
	RagdollEnd      = "RagdollEnd",
}

return CombatSettings