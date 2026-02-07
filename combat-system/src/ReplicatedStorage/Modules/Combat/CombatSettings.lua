--[[
	CombatSettings.lua
	
	Professional combat system configuration inspired by TSB.
	Handles M1 combos, heavy attacks, sprint mechanics, and blocking.
	
	Author: [Your Name]
	Last Modified: 2024
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
	SprintSpeed = 27.2, -- 1.7x of walk speed
	BlockSpeed = 8,
	
	-- Sprint settings
	SprintKey = Enum.KeyCode.LeftControl,
	SprintStaminaCost = 0, -- Future: stamina system
}

-- ========================================
-- M1 COMBAT SYSTEM
-- ========================================
CombatSettings.M1 = {
	-- Damage values
	BaseDamage = 8,
	HeavyDamage = 15,
	FinisherDamage = 20,
	
	-- Heavy attack conditions (any of these triggers heavy)
	HeavyConditions = {
		RequiresSprint = true, -- Must be sprinting
		RequiresJump = true, -- OR must be in air
		MinVelocity = 20, -- OR moving faster than this
	},
	
	-- Combo system
	MaxCombo = 4,
	ComboResetTime = 2.5,
	
	-- Timing
	AttackCooldown = 0.35, -- Minimum time between attacks
	AttackRange = 9,
	AttackAngle = 60, -- Degrees for hit detection cone
	
	-- Knockback (horizontal, vertical)
	NormalKnockback = {25, 8},
	HeavyKnockback = {45, 15},
	FinisherKnockback = {65, 25},
	
	-- Stun on finisher
	FinisherStunDuration = 0.8,
}

-- ========================================
-- BLOCKING SYSTEM
-- ========================================
CombatSettings.Block = {
	Key = Enum.KeyCode.F,
	DamageReduction = 0.2, -- Take only 20% damage
	KnockbackReduction = 0.3, -- Take only 30% knockback
	PerfectBlockWindow = 0.15, -- Perfect block within this time
	PerfectBlockReduction = 0.05, -- Take only 5% damage on perfect block
}

-- ========================================
-- DASH SYSTEM
-- ========================================
CombatSettings.Dash = {
	Key = Enum.KeyCode.Q,
	Speed = 80,
	Duration = 0.2,
	Cooldown = 1.2,
}

-- ========================================
-- VISUAL EFFECTS
-- ========================================
CombatSettings.VFX = {
	-- Damage numbers
	DamageNumbers = {
		Enabled = true,
		NormalColor = Color3.fromRGB(255, 255, 255), -- White
		HeavyColor = Color3.fromRGB(255, 120, 0), -- Orange
		FinisherColor = Color3.fromRGB(255, 50, 50), -- Red
		BlockedColor = Color3.fromRGB(100, 200, 255), -- Blue
		CriticalColor = Color3.fromRGB(255, 215, 0), -- Gold
		
		Size = 24,
		Duration = 1.5,
		RiseSpeed = 2,
	},
	
	-- VFX paths (from ReplicatedStorage.Assets.CombatSystem)
	ConstantArmAura = "ConstantArmAura",
	TargetHitVfx = "TargetHitVfx",
	BlockVfx = "BlockVfx",
	
	-- Screen shake
	ScreenShake = {
		Normal = {Magnitude = 0.3, Duration = 0.15},
		Heavy = {Magnitude = 0.6, Duration = 0.25},
		Finisher = {Magnitude = 1.0, Duration = 0.35},
		Blocked = {Magnitude = 0.2, Duration = 0.1},
	},
}

-- ========================================
-- ANIMATIONS
-- ========================================
CombatSettings.Animations = {
	-- Movement
	Walk = "rbxassetid://116220790835806",
	Run = "rbxassetid://76377318361443",
	Sprint = "rbxassetid://76377318361443", -- Use run anim for sprint
	
	-- Dashing
	FrontDash = "rbxassetid://92389271308997",
	BackDash = "rbxassetid://99261664117383",
	SideDashLeft = "rbxassetid://126714519140500",
	SideDashRight = "rbxassetid://119606631904406",
	
	-- M1 Combo (4 attacks)
	M1 = {
		Id = "rbxassetid://108727746476303",
		Duration = 0.45,
		HitFrame = 0.35, -- When to apply damage (% of duration)
	},
	M2 = {
		Id = "rbxassetid://101585643838515",
		Duration = 0.45,
		HitFrame = 0.35,
	},
	M3 = {
		Id = "rbxassetid://138408280930081",
		Duration = 0.5,
		HitFrame = 0.4,
	},
	M4 = {
		Id = "rbxassetid://100818712303477",
		Duration = 0.65,
		HitFrame = 0.45,
	},
}

-- ========================================
-- ANTI-EXPLOIT
-- ========================================
CombatSettings.AntiExploit = {
	MaxAttacksPerSecond = 6,
	MaxDashesPerSecond = 3,
	ServerValidation = true,
	MaxPing = 300,
}

-- ========================================
-- AUDIO
-- ========================================
CombatSettings.Audio = {
	NormalHit = "rbxassetid://72142112079276",
	HeavyHit = "rbxassetid://72142112079276", -- Replace with heavy sound
	BlockHit = "rbxassetid://9114487369",
	Dash = "", -- Add dash sound
	Finisher = "", -- Add finisher sound
	
	Volume = 0.6,
}

return table.freeze(CombatSettings)