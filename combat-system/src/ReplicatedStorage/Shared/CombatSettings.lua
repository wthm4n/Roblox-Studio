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
-- ══════════════════════════════════════════
CombatSettings.Audio = {
	M1Sound    = "rbxassetid://137630794322989",
	M2Sound    = "rbxassetid://137630794322989",
	M3Sound    = "rbxassetid://137630794322989",
	M4Sound    = "rbxassetid://137630794322989",
	M5Sound    = "rbxassetid://137630794322989",
	BlockHit   = "rbxassetid://137630794322989",
	BlockBreak = "rbxassetid://137630794322989",
}

-- ══════════════════════════════════════════
--  REMOTES  (string keys only – actual RemoteEvents live in ReplicatedStorage)
-- ══════════════════════════════════════════
CombatSettings.Remotes = {
	UsedM1          = "UsedM1",
	ApplyHitEffect  = "ApplyHitEffect",
}

return CombatSettings
