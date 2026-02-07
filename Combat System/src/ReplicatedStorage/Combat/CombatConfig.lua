--[[
	COMBAT CONFIG
	
	Abilities contain ZERO logic.
	Abilities are configs.
	
	Defines:
	- Frame data (startup, active, recovery)
	- Hitbox shapes and paths
	- Damage values
	- Armor rules
	- Cancel rules
	- Camera effects
	- Cooldowns
	
	New abilities don't need new scripts.
	Balance is data-only.
]]

local CombatConfig = {}

--[[
	M1 COMBO CONFIGURATIONS
	PROFESSIONAL STRONGEST BATTLEGROUNDS STYLE
	
	Frame Data Philosophy:
	- Startup: Wind-up animation
	- Active: Hitbox is live
	- Recovery: Return to neutral / attack window opens
	
	Attack Windows:
	- Open during late recovery
	- Player must input during window
	- Creates rhythm, prevents spam
]]
CombatConfig.M1Combos = {
	-- First Hit - Quick Jab
	{
		Name = "M1_1",
		StartupFrames = 5,    -- Quick wind-up
		ActiveFrames = 4,     -- Brief active window
		RecoveryFrames = 15,  -- Enough for animation + attack window
		TotalFrames = 24,
		
		-- Attack window opens at frame 8 of recovery (late recovery)
		AttackWindowDelay = 8,   -- Frames into recovery before window opens
		AttackWindowDuration = 12, -- Window lasts 12 frames (0.2s)
		
		Hitbox = {
			Size = Vector3.new(4.5, 4.5, 4.5),
			Offset = Vector3.new(0, 0, -2.5),
			Rotation = Vector3.new(0, 0, 0),
		},
		
		Damage = 8,
		KnockbackForce = 12,
		Hitstun = 10, -- Target frozen for 10 frames
		
		CancelRules = {
			Startup = { Dash = true }, -- Can dash out early
			Active = { Dash = true },
			Recovery = { M1 = true, Dash = true }, -- Can continue combo
		},
		
		Animation = "M1_1",
		RequiredState = "Attacking",
	},
	
	-- Second Hit - Cross Punch
	{
		Name = "M1_2",
		StartupFrames = 6,
		ActiveFrames = 5,
		RecoveryFrames = 16,
		TotalFrames = 27,
		
		AttackWindowDelay = 9,
		AttackWindowDuration = 12,
		
		Hitbox = {
			Size = Vector3.new(5, 5, 5),
			Offset = Vector3.new(0, 0, -3),
			Rotation = Vector3.new(0, 0, 0),
		},
		
		Damage = 10,
		KnockbackForce = 15,
		Hitstun = 12,
		
		CancelRules = {
			Startup = { Dash = true },
			Active = { Dash = true },
			Recovery = { M1 = true, Dash = true, Ability = true },
		},
		
		Animation = "M1_2",
		RequiredState = "Attacking",
	},
	
	-- Third Hit - Heavy Strike
	{
		Name = "M1_3",
		StartupFrames = 7,
		ActiveFrames = 6,
		RecoveryFrames = 18,
		TotalFrames = 31,
		
		AttackWindowDelay = 10,
		AttackWindowDuration = 13,
		
		Hitbox = {
			Size = Vector3.new(5.5, 5.5, 6),
			Offset = Vector3.new(0, 0, -3.5),
			Rotation = Vector3.new(0, 0, 0),
		},
		
		Damage = 13,
		KnockbackForce = 22,
		Hitstun = 15,
		
		HitStop = 0.04, -- Freeze frame on impact
		
		CancelRules = {
			Startup = { Dash = true },
			Active = { Dash = true },
			Recovery = { M1 = true, Dash = true, Ability = true },
		},
		
		Animation = "M1_3",
		RequiredState = "Attacking",
		
		CameraShake = {
			Duration = 0.15,
			Magnitude = 0.4,
		},
	},
	
	-- Fourth Hit - Devastating Finisher
	{
		Name = "M1_4",
		StartupFrames = 10,   -- Slower wind-up for big hit
		ActiveFrames = 7,     -- Longer active window
		RecoveryFrames = 28,  -- Long recovery, no combo after
		TotalFrames = 45,
		
		-- No attack window - this ends the combo
		AttackWindowDelay = 0,
		AttackWindowDuration = 0,
		
		Hitbox = {
			Size = Vector3.new(7, 7, 8),
			Offset = Vector3.new(0, 0, -4),
			Rotation = Vector3.new(0, 0, 0),
		},
		
		Damage = 20,
		KnockbackForce = 90,
		KnockbackDirection = Vector3.new(0, 0.5, 1), -- Launch upward
		Hitstun = 25, -- Long stun on finisher
		
		HitStop = 0.1, -- Strong freeze frame
		
		CancelRules = {
			Startup = { Dash = true },
			Active = {},  -- Cannot cancel during active
			Recovery = { Dash = true, Ability = true }, -- Can use abilities after
		},
		
		Animation = "M1_4",
		RequiredState = "Attacking",
		
		CameraShake = {
			Duration = 0.3,
			Magnitude = 0.8,
		},
		
		-- This ends the combo and forces cooldown
		ForceComboEnd = true,
	},
}

--[[
	DASH CONFIGURATIONS
]]
CombatConfig.Dashes = {
	Front = {
		Name = "DashFront",
		StartupFrames = 2,
		ActiveFrames = 10,
		RecoveryFrames = 5,
		TotalFrames = 17,
		
		Speed = 80,
		Direction = "Front",
		
		Invincibility = true, -- I-frames during active
		
		CancelRules = {
			Startup = {},
			Active = { M1 = true },
			Recovery = { M1 = true, Ability = true },
		},
		
		Animation = "DashFront",
		RequiredState = "Dashing",
	},
	
	Back = {
		Name = "DashBack",
		StartupFrames = 2,
		ActiveFrames = 10,
		RecoveryFrames = 5,
		TotalFrames = 17,
		
		Speed = 70,
		Direction = "Back",
		
		Invincibility = true,
		
		CancelRules = {
			Startup = {},
			Active = { M1 = true },
			Recovery = { M1 = true, Ability = true },
		},
		
		Animation = "DashBack",
		RequiredState = "Dashing",
	},
	
	Left = {
		Name = "DashLeft",
		StartupFrames = 2,
		ActiveFrames = 8,
		RecoveryFrames = 5,
		TotalFrames = 15,
		
		Speed = 75,
		Direction = "Left",
		
		Invincibility = false, -- Side dashes have no i-frames
		
		CancelRules = {
			Startup = {},
			Active = { M1 = true },
			Recovery = { M1 = true, Ability = true },
		},
		
		Animation = "DashLeft",
		RequiredState = "Dashing",
	},
	
	Right = {
		Name = "DashRight",
		StartupFrames = 2,
		ActiveFrames = 8,
		RecoveryFrames = 5,
		TotalFrames = 15,
		
		Speed = 75,
		Direction = "Right",
		
		Invincibility = false,
		
		CancelRules = {
			Startup = {},
			Active = { M1 = true },
			Recovery = { M1 = true, Ability = true },
		},
		
		Animation = "DashRight",
		RequiredState = "Dashing",
	},
}

--[[
	ABILITY CONFIGURATIONS
	Add your custom abilities here
]]
CombatConfig.Abilities = {
	-- Example ability
	FireBlast = {
		Name = "FireBlast",
		StartupFrames = 12,
		ActiveFrames = 8,
		RecoveryFrames = 20,
		TotalFrames = 40,
		
		Hitbox = {
			Size = Vector3.new(8, 8, 12),
			Offset = Vector3.new(0, 0, -6),
			Rotation = Vector3.new(0, 0, 0),
			Type = "Projectile", -- Could spawn actual projectile
		},
		
		Damage = 35,
		KnockbackForce = 80,
		
		Cooldown = 180, -- 3 seconds at 60fps
		
		CancelRules = {
			Startup = { Dash = true },
			Active = {},
			Recovery = { Dash = true },
		},
		
		Animation = "FireBlast",
		RequiredState = "Attacking",
		
		-- VFX
		Effect = "FireBlastVFX",
		
		-- Camera
		CameraShake = {
			Duration = 0.3,
			Magnitude = 0.8,
		},
	},
	
	-- Counter ability example
	Counter = {
		Name = "Counter",
		StartupFrames = 5,
		ActiveFrames = 20, -- Long counter window
		RecoveryFrames = 10,
		TotalFrames = 35,
		
		Hitbox = {
			Size = Vector3.new(0, 0, 0), -- No hitbox, it's a counter
		},
		
		Damage = 50, -- High damage if counter succeeds
		KnockbackForce = 100,
		
		Cooldown = 240, -- 4 seconds
		
		-- Special counter logic would be in AbilityEffects module
		IsCounter = true,
		
		CancelRules = {
			Startup = {},
			Active = {},
			Recovery = {},
		},
		
		Animation = "Counter",
		RequiredState = "Attacking",
		
		-- Super armor during active frames
		SuperArmor = true,
	},
}

--[[
	ANIMATION IDS
	Map animation names to Roblox asset IDs
	REPLACE THESE WITH YOUR ACTUAL ANIMATION IDS
]]
CombatConfig.AnimationIds = {
	-- M1 Combos
	M1_1 = "rbxassetid://0000000001", -- REPLACE
	M1_2 = "rbxassetid://0000000002", -- REPLACE
	M1_3 = "rbxassetid://0000000003", -- REPLACE
	M1_4 = "rbxassetid://0000000004", -- REPLACE
	
	-- Dashes
	DashFront = "rbxassetid://0000000010", -- REPLACE
	DashBack = "rbxassetid://0000000011", -- REPLACE
	DashLeft = "rbxassetid://0000000012", -- REPLACE
	DashRight = "rbxassetid://0000000013", -- REPLACE
	
	-- Hit reactions
	Hit = "rbxassetid://0000000020", -- REPLACE
	Knockback = "rbxassetid://0000000021", -- REPLACE
	
	-- Abilities
	FireBlast = "rbxassetid://0000000030", -- REPLACE
	Counter = "rbxassetid://0000000031", -- REPLACE
}

--[[
	GET CONFIG FUNCTIONS
	Used by Core to load action configs
]]
function CombatConfig.GetM1Config(comboIndex: number)
	local index = ((comboIndex - 1) % #CombatConfig.M1Combos) + 1
	return CombatConfig.M1Combos[index]
end

function CombatConfig.GetDashConfig(direction: string)
	return CombatConfig.Dashes[direction]
end

function CombatConfig.GetAbilityConfig(abilityName: string)
	return CombatConfig.Abilities[abilityName]
end

function CombatConfig.GetAnimationId(animationName: string)
	return CombatConfig.AnimationIds[animationName]
end

return CombatConfig