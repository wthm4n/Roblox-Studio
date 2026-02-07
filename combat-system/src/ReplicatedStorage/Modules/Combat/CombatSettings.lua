--[[
	CombatSettings.lua
	
	Central configuration for the combat system.
	All gameplay balance values in one place for easy tuning.
	
	Author: [Your Name]
	Last Modified: 2024
]]

local CombatSettings = {}

-- ========================================
-- PLAYER STATS
-- ========================================
CombatSettings.Player = {
	MaxHealth = 100,
	HealthRegen = 2, -- HP per second
	NormalMoveSpeed = 16,
	BlockMoveSpeed = 8,
}

-- ========================================
-- M1 COMBAT (Basic Attacks)
-- ========================================
CombatSettings.M1 = {
	-- Damage
	BaseDamage = 10,
	HeavyDamage = 18,
	HeavyVelocityThreshold = 20, -- Speed needed for heavy attack

	-- Combo
	MaxComboCount = 4,
	ComboFinisherMultiplier = 1.5,
	ComboResetTime = 2.0, -- Seconds before combo resets
	ComboFinisherCooldown = 1.0, -- Extra cooldown after 4th hit

	-- Timing
	MinimumAttackDelay = 0.3, -- Minimum time between attacks
	AttackRange = 8,

	-- Knockback
	BaseKnockbackHorizontal = 25,
	BaseKnockbackVertical = 10,
	HeavyKnockbackHorizontal = 50,
	HeavyKnockbackVertical = 20,
	FinisherKnockbackHorizontal = 60,
	FinisherKnockbackVertical = 25,
	ComboKnockbackMultiplier = 0.15, -- +15% per combo hit

	-- Stun
	FinisherStunDuration = 0.5,
	FinisherStunWalkSpeed = 0,
	FinisherStunJumpPower = 0,
}

-- ========================================
-- BLOCKING
-- ========================================
CombatSettings.Block = {
	DamageReduction = 0.8, -- Take 30% of damage when blocking
	KnockbackReduction = 0.6, -- Take 60% less knockback
	StaminaCost = 0, -- Future: Could add stamina system
}

-- ========================================
-- DASH SYSTEM
-- ========================================
CombatSettings.Dash = {
	Speed = 80,
	Duration = 0.2,
	Cooldown = 1.0,
}

-- ========================================
-- ANIMATION IDs
-- ========================================
CombatSettings.Animations = {
	-- Movement
	Walk = "rbxassetid://116220790835806",
	Run = "rbxassetid://76377318361443",

	-- Dash
	FrontDash = "rbxassetid://92389271308997",
	BackDash = "rbxassetid://99261664117383",
	SideDashLeft = "rbxassetid://126714519140500",
	SideDashRight = "rbxassetid://119606631904406",

	-- M1 Attacks
	M1 = {
		Id = "rbxassetid://108727746476303",
		Duration = 0.5,
	},
	M2 = {
		Id = "rbxassetid://101585643838515",
		Duration = 0.5,
	},
	M3 = {
		Id = "rbxassetid://138408280930081",
		Duration = 0.6,
	},
	M4 = {
		Id = "rbxassetid://100818712303477",
		Duration = 0.7,
	},
}

-- ========================================
-- ANTI-EXPLOIT
-- ========================================
CombatSettings.AntiExploit = {
	MaxAttacksPerSecond = 5,
	MaxAbilitiesPerSecond = 3,
	ServerSideValidation = true,
}

-- ========================================
-- VFX SETTINGS
-- ========================================
CombatSettings.VFX = {
	EnableScreenShake = true,
	EnableParticles = true,
	ParticleQuality = "High", -- Low, Medium, High
	MaxDebrisLifetime = 5.0,
}

-- ========================================
-- NETWORKING
-- ========================================
CombatSettings.Network = {
	MaxPing = 300, -- Milliseconds
	PredictionEnabled = true,
	InterpolationFactor = 0.1,
}

return table.freeze(CombatSettings)
