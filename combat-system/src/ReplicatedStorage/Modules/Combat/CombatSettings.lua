--[[
	CombatSettings.lua
	
	TSB-inspired combat system configuration.
	Optimized for multi-target spatial hitbox combat.
	
	Author: Combat System Rewrite
]]

local CombatSettings = {}

-- ========================================
-- PLAYER STATS & MOVEMENT
-- ========================================
CombatSettings.Player = {
	MaxHealth = 100,
	HealthRegen = 2,

	-- Movement speeds
	WalkSpeed = 16,
	SprintSpeed = 27, -- TSB-style sprint
	BlockSpeed = 8,
	DashSpeed = 90, -- Fast dashes

	-- Sprint settings
	SprintKey = Enum.KeyCode.LeftControl,
	SprintStaminaCost = 0,
}

-- ========================================
-- M1 COMBAT SYSTEM
-- ========================================
CombatSettings.M1 = {
	-- Damage values
	BaseDamage = 8,
	HeavyDamage = 15,
	FinisherDamage = 20,

	-- Heavy attack conditions
	HeavyConditions = {
		RequiresSprint = true,
		RequiresJump = true,
		MinVelocity = 20,
	},

	-- Combo system
	MaxCombo = 4,
	ComboResetTime = 2.5,

	-- Timing
	AttackCooldown = 0.25, -- Faster combos (was 0.3)

	-- SPATIAL HITBOX (Multi-Target)
	HitboxRange = 12, -- Sphere radius
	HitboxAngle = 75, -- Cone angle in degrees (wider = easier to hit)
	MaxTargetsPerHit = 5, -- Hit up to 5 enemies at once

	-- Camera-based attacks
	UseCameraDirection = true, -- Attack where you're looking

	-- Knockback
	NormalKnockback = { 25, 8 },
	HeavyKnockback = { 45, 15 },
	FinisherKnockback = { 65, 25 },

	-- Stun
	FinisherStunDuration = 0.8,
}

-- ========================================
-- BLOCKING SYSTEM
-- ========================================
CombatSettings.Block = {
	Key = Enum.KeyCode.F,
	DamageReduction = 0.2,
	KnockbackReduction = 0.3,
	PerfectBlockWindow = 0.15,
	PerfectBlockReduction = 0.05,
}

-- ========================================
-- DASH SYSTEM (TSB-Style)
-- ========================================
CombatSettings.Dash = {
	Key = Enum.KeyCode.Q,
	Speed = 95, -- Very fast
	Duration = 0.25,
	Cooldown = 1.0, -- Fast cooldown

	-- Combat integration
	AllowAttackDuringDash = true, -- Can attack while dashing
	DashAttackHits360 = true, -- Dash attacks hit all around you
	DashAttackRangeMultiplier = 1.3, -- Bigger hitbox when dashing
}

-- ========================================
-- VFX SETTINGS
-- ========================================
CombatSettings.VFX = {
	-- Damage numbers
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

	-- Screen shake
	ScreenShake = {
		Normal = { Magnitude = 0.3, Duration = 0.15 },
		Heavy = { Magnitude = 0.6, Duration = 0.25 },
		Finisher = { Magnitude = 1.0, Duration = 0.35 },
		Blocked = { Magnitude = 0.2, Duration = 0.1 },
	},
}

-- ========================================
-- ANIMATIONS
-- ========================================
CombatSettings.Animations = {
	-- Movement
	Walk = "rbxassetid://116220790835806",
	Sprint = "rbxassetid://76377318361443",

	-- Dashing
	FrontDash = "rbxassetid://92389271308997",
	BackDash = "rbxassetid://99261664117383",
	SideDashLeft = "rbxassetid://126714519140500",
	SideDashRight = "rbxassetid://119606631904406",

	-- M1 Combo
	M1 = {
		Id = "rbxassetid://108727746476303",
		Duration = 0.45,
		HitFrame = 0.15, -- Earlier for instant feel
	},
	M2 = {
		Id = "rbxassetid://101585643838515",
		Duration = 0.45,
		HitFrame = 0.15,
	},
	M3 = {
		Id = "rbxassetid://138408280930081",
		Duration = 0.5,
		HitFrame = 0.2,
	},
	M4 = {
		Id = "rbxassetid://100818712303477",
		Duration = 0.65,
		HitFrame = 0.25,
	},
}

-- ========================================
-- AUDIO
-- ========================================
CombatSettings.Audio = {
	-- M1 Sounds (play on HIT, not on swing)
	M1Sound = "rbxassetid://124916598999754",
	M2Sound = "rbxassetid://77412258788453",
	M3Sound = "rbxassetid://108843398435059",
	M4Sound = "rbxassetid://124916598999754",

	-- Other
	BlockHit = "rbxassetid://137630794322989",
	Dash = "",

	Volume = 0.5,
	HitVolume = 1.0, -- Play at target location
}

-- ========================================
-- ANTI-EXPLOIT
-- ========================================
CombatSettings.AntiExploit = {
	MaxAttacksPerSecond = 6,
	MaxDashesPerSecond = 3,
	ServerValidation = true,
}

return table.freeze(CombatSettings)
