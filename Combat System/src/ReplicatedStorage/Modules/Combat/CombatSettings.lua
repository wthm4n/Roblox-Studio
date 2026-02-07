local CombatSettings = {
	MAX_HEALTH = 100,
	HEALTH_REGEN = 2,
	M1_DAMAGE = 10,
	HEAVY_DAMAGE = 20,
	COMBO_MAX = 4,
	COMBO_RESET_TIME = 2.0,
	COMBO_FINISHER_COOLDOWN = 0.8,
	M1_RANGE = 10,
	HEAVY_VELOCITY_THRESHOLD = 16,
	MINIMUM_ATTACK_DELAY = 0.35,
	ANIM_DURATION_M1 = 0.45,
	ANIM_DURATION_M2 = 0.45,
	ANIM_DURATION_M3 = 0.50,
	ANIM_DURATION_M4 = 0.75,
	BLOCK_DAMAGE_REDUCTION = 0.5,
	BLOCK_MOVE_SPEED = 8,
	NORMAL_MOVE_SPEED = 16,
	PUNCH_VFX_LIFETIME = 1.5,
	BLOCK_VFX_LIFETIME = 2.0,
	DASH_COOLDOWN = 1.0,
	DASH_SPEED = 50,
	DASH_DURATION = 0.3,
	ANIM_M1 = "rbxassetid://108727746476303",
	ANIM_M2 = "rbxassetid://101585643838515",
	ANIM_M3 = "rbxassetid://138408280930081",
	ANIM_M4 = "rbxassetid://100818712303477",
	ANIM_FRONTDASH = "rbxassetid://92389271308997",
	ANIM_RUN = "rbxassetid://76377318361443",
	ANIM_SIDEDASHLEFT = "rbxassetid://126714519140500",
	ANIM_SIDEDASHRIGHT = "rbxassetid://119606631904406",
	ANIM_WALK = "rbxassetid://116220790835806",
	ANIM_BACKDASH = "rbxassetid://99261664117383",
}
return CombatSettings


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
	HeavyVelocityThreshold = 40, -- Speed needed for heavy attack
	
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
	DamageReduction = 0.3, -- Take 30% of damage when blocking
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
	Walk = "rbxassetid://YOUR_WALK_ID",
	Run = "rbxassetid://YOUR_RUN_ID",
	
	-- Dash
	FrontDash = "rbxassetid://YOUR_FRONTDASH_ID",
	BackDash = "rbxassetid://YOUR_BACKDASH_ID",
	SideDashLeft = "rbxassetid://YOUR_SIDEDASHLEFT_ID",
	SideDashRight = "rbxassetid://YOUR_SIDEDASHRIGHT_ID",
	
	-- M1 Attacks
	M1 = {
		Id = "rbxassetid://YOUR_M1_ID",
		Duration = 0.5,
	},
	M2 = {
		Id = "rbxassetid://YOUR_M2_ID",
		Duration = 0.5,
	},
	M3 = {
		Id = "rbxassetid://YOUR_M3_ID",
		Duration = 0.6,
	},
	M4 = {
		Id = "rbxassetid://YOUR_M4_ID",
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