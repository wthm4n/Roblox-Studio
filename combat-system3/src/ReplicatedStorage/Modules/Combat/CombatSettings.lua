--[[
	AdvancedCombatSettings.lua
	
	Configuration for advanced combat system with:
	- M1-M5 combo
	- Block system with durability
	- Hit reactions (blocking and normal)
	- Block breaking
	- BEAST MODE (10s damage boost)
	- Debug hitbox visualizer
]]

local CombatSettings = {}

-- ========================================
-- PLAYER STATS
-- ========================================
CombatSettings.Player = {
	MaxHealth = 100,
	HealthRegen = 2,
	WalkSpeed = 16,
	RunSpeed = 22,
	BlockSpeed = 8,
}

-- ========================================
-- M1-M5 COMBAT SYSTEM
-- ========================================
CombatSettings.M1 = {
	-- Damage values (NORMAL MODE)
	BaseDamage = 8,
	HeavyDamage = 15,
	FinisherDamage = 25,

	-- Heavy attack conditions
	HeavyConditions = {
		RequiresSprint = true,
		RequiresJump = true,
		MinVelocity = 20,
	},

	-- Combo system (5 attacks now)
	MaxCombo = 5,
	ComboResetTime = 2.5,

	-- Timing
	AttackCooldown = 0.25,
	HitRequestCooldown = 0.15,

	-- SPATIAL HITBOX
	HitboxRange = 5,
	HitboxAngle = 75,
	MaxTargetsPerHit = 5,

	-- Camera-based attacks
	UseCameraDirection = true,

	-- Knockback
	NormalKnockback = { 25, 8 },
	HeavyKnockback = { 45, 15 },
	FinisherKnockback = { 70, 30 },

	-- Stun
	FinisherStunDuration = 1.0,
}

-- ========================================
-- BEAST MODE SYSTEM
-- ========================================
CombatSettings.BeastMode = {
	-- Activation
	ActivationKey = Enum.KeyCode.G, -- Press G to activate
	ActivationAnimation = "rbxassetid://136605012097315", -- Animation played before activation

	-- Duration
	Duration = 10, -- 10 seconds
	Cooldown = 3, -- 3 second cooldown after it ends

	-- Damage multipliers
	DamageMultiplier = 2.0, -- 2x damage

	-- Visual effects during beast mode
	ArmAuraEnabled = true, -- Constant arm aura VFX only
}

-- ========================================
-- DEBUG SETTINGS
-- ========================================
CombatSettings.Debug = {
	-- Hitbox Visualizer
	ShowHitbox = false, -- Set to true to see hitbox sphere
	HitboxColor = Color3.fromRGB(255, 0, 0), -- Red sphere
	HitboxTransparency = 0.7,

	ShowTargets = false, -- Show detected targets with markers
	TargetMarkerColor = Color3.fromRGB(0, 255, 0), -- Green markers

	-- Console logging
	LogHits = false,
	LogBeastMode = true,
}

-- ========================================
-- BLOCKING SYSTEM
-- ========================================
CombatSettings.Block = {
	Key = Enum.KeyCode.F,

	-- Block durability
	MaxHealth = 100,
	DamagePerHit = 15, -- How much block health each hit removes

	-- Damage reduction
	DamageReduction = 0.2,
	KnockbackReduction = 0.3,

	-- Perfect block
	PerfectBlockWindow = 0.15,
	PerfectBlockReduction = 0.05,

	-- Block breaking
	BreakStunDuration = 1.5, -- Stun duration when block breaks
}

-- ========================================
-- VFX SETTINGS
-- ========================================
CombatSettings.VFX = {
	DamageNumbers = {
		Enabled = true,
		NormalColor = Color3.fromRGB(255, 255, 255),
		HeavyColor = Color3.fromRGB(255, 120, 0),
		FinisherColor = Color3.fromRGB(255, 50, 50),
		BlockedColor = Color3.fromRGB(100, 200, 255),
		CriticalColor = Color3.fromRGB(255, 215, 0),

		Size = 24,
		Duration = 1.5,
		RiseSpeed = 2,
	},

	ScreenShake = {
		Normal = { Magnitude = 0.3, Duration = 0.15 },
		Heavy = { Magnitude = 0.6, Duration = 0.25 },
		Finisher = { Magnitude = 1.0, Duration = 0.35 },
		Blocked = { Magnitude = 0.2, Duration = 0.1 },
		BlockBroken = { Magnitude = 1.2, Duration = 0.5 },
	},
}

-- ========================================
-- ANIMATIONS
-- ========================================
CombatSettings.Animations = {
	-- M1-M5 Combo (ADD "Hit" MARKER TO EACH!)
	M1 = {
		Id = "rbxassetid://108566685589624",
		Duration = 0.45,
		HitFrame = 0.15,
	},
	M2 = {
		Id = "rbxassetid://121076535244470",
		Duration = 0.45,
		HitFrame = 0.15,
	},
	M3 = {
		Id = "rbxassetid://118197196863834",
		Duration = 0.5,
		HitFrame = 0.2,
	},
	M4 = {
		Id = "rbxassetid://76404683651972",
		Duration = 0.6,
		HitFrame = 0.25,
	},
	M5 = {
		Id = "rbxassetid://105629270009427", -- Finisher
		Duration = 0.75,
		HitFrame = 0.3,
	},

	-- Blocking
	Block = "rbxassetid://133189311751347",
	BlockingHitReaction1 = "rbxassetid://74809674784324",
	BlockingHitReaction2 = "rbxassetid://139217606379358",
	BlockingHitReaction3 = "rbxassetid://131983705093197",
	BlockingHitReaction4 = "rbxassetid://116379344332047",
	BlockingHitReaction5 = "rbxassetid://109762979660797",
	BlockBroken = "rbxassetid://110600332239093",

	-- Hit Reactions (when not blocking)
	HitReaction1 = "rbxassetid://135435525629845",
	HitReaction2 = "rbxassetid://90491820229603",
	HitReaction3 = "rbxassetid://133746302611824",
	HitReaction4 = "rbxassetid://98605161276665",
	HitReaction5 = "rbxassetid://95965894669114",
}

-- ========================================
-- AUDIO
-- ========================================
CombatSettings.Audio = {
	-- M1-M5 Sounds
	M1Sound = "rbxassetid://137630794322989",
	M2Sound = "rbxassetid://137630794322989",
	M3Sound = "rbxassetid://137630794322989",
	M4Sound = "rbxassetid://137630794322989",
	M5Sound = "rbxassetid://137630794322989",

	-- Other
	BlockHit = "rbxassetid://137630794322989",
	BlockBreak = "rbxassetid://137630794322989",

	-- Beast Mode (PUT YOUR SOUND ID HERE)
	BeastModeActivate = "rbxassetid://133092149239445", -- Sound when activating
	BeastModeDeactivate = "rbxassetid://137630794322989", -- When it ends

	Volume = 0.5,
	HitVolume = 5.0,
}

-- ========================================
-- ANTI-EXPLOIT
-- ========================================
CombatSettings.AntiExploit = {
	MaxAttacksPerSecond = 6,
	ServerValidation = true,
}

return table.freeze(CombatSettings)
