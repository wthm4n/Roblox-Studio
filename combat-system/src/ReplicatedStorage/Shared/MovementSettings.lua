--[[
	MovementSettings.lua
	Shared config for the momentum-driven movement system.
	Place in: ReplicatedStorage/Shared/MovementSettings
]]

local MovementSettings = {}

-- ══════════════════════════════════════════
--  ANIMATIONS
-- ══════════════════════════════════════════
MovementSettings.Animations = {
	Idle         = "rbxassetid://133939959372694",
	Walk         = "rbxassetid://101695660356667",
	Run          = "rbxassetid://110745974890930",
	DashW        = "rbxassetid://88193156661727",
	DashA        = "rbxassetid://74619303114279",
	DashS        = "rbxassetid://115159060573717",
	DashD        = "rbxassetid://119390596531434",
	Slide        = "rbxassetid://79166711928073",
	WallRunLeft  = "rbxassetid://93201209088043",
	WallRunRight = "rbxassetid://78952764830119",
	LedgeHang    = "rbxassetid://130912033735566",
	LedgeClimb   = "rbxassetid://126959978444547",
}

-- ══════════════════════════════════════════
--  BASE SPEEDS  (studs/s)
-- ══════════════════════════════════════════
MovementSettings.Speed = {
	Walk             = 16,
	Sprint           = 28,
	DefaultHipHeight = 2.0,   -- R15 = 2.0 | R6 = 0
	SlideHipHeight   = 0.5,
}

-- ══════════════════════════════════════════
--  MOMENTUM ENERGY  (0-100 float)
--  Accumulated from active movement, decays at rest.
--  Scales dash distance, slide speed, wall run speed.
-- ══════════════════════════════════════════
MovementSettings.Momentum = {
	SprintGain    = 18,   -- per second while sprinting
	WallRunGain   = 22,   -- per second while wall running
	AirGain       = 6,    -- per second while airborne
	IdleDecay     = 38,   -- per second while standing
	WalkDecay     = 18,   -- per second while walking slowly
	DashBonus     = 15,   -- instant on dash
	WallJumpBonus = 20,   -- instant on wall jump
	LandBonus     = 8,    -- instant on landing
	Max           = 100,
}

-- ══════════════════════════════════════════
--  DASH
-- ══════════════════════════════════════════
MovementSettings.Dash = {
	Key            = Enum.KeyCode.Q,
	-- Speed = Base + Energy * EnergyScale  (100 energy → 72+28 = 100 studs/s)
	BaseSpeed      = 72,
	EnergyScale    = 0.28,
	Duration       = 0.18,
	Cooldown       = 0.75,
	IFrameDuration = 0.12,
	AllowAirDash   = true,    -- 1 air dash per airborne phase
	JumpCancelMult = 0.55,    -- Space during dash: convert horiz→vertical
	BufferWindow   = 0.12,    -- Q pressed before landing auto-dashes on touch

	Keys = {
		Forward  = Enum.KeyCode.W,
		Left     = Enum.KeyCode.A,
		Backward = Enum.KeyCode.S,
		Right    = Enum.KeyCode.D,
	},
	Animations = {
		Forward  = "DashW",
		Left     = "DashA",
		Backward = "DashS",
		Right    = "DashD",
	},
}

-- ══════════════════════════════════════════
--  SLIDE
-- ══════════════════════════════════════════
MovementSettings.Slide = {
	SpeedMult        = 1.15,   -- entry speed = current flat velocity * mult
	SpeedMin         = 22,
	SpeedMax         = 58,
	FrictionMult     = 0.87,   -- velocity multiplied each friction tick
	FrictionInterval = 0.05,   -- seconds between friction ticks
	EndSpeed         = 8,      -- auto-end below this speed
	MaxDuration      = 1.4,
	DefaultHipHeight = 2.0,
	CrouchHipHeight  = 0.5,
}

-- ══════════════════════════════════════════
--  WALL RUN
-- ══════════════════════════════════════════
MovementSettings.WallRun = {
	RayLength       = 3.2,
	RayCount        = 3,
	RaySpreadY      = 1.2,
	MinAirTime      = 0.05,
	MinForwardDot   = 0.3,
	EntrySpeedMin   = 18,     -- minimum wall run speed
	EntrySpeedMax   = 42,     -- maximum wall run speed
	RampTime        = 0.65,   -- seconds to reach full speed ramp
	RampAdd         = 14,     -- extra studs/s added at peak of ramp
	GravityFraction = 0.18,   -- how much gravity acts during wall run (natural arc)
	WallJumpH       = 54,
	WallJumpV       = 50,
	MaxDuration     = 2.8,
	MaxSlopeAngle   = 25,
	TiltAngle       = 10,
	CoyoteTime      = 0.15,   -- can attach for this long after leaving a wall
}

-- ══════════════════════════════════════════
--  REMOTES
-- ══════════════════════════════════════════
MovementSettings.Remotes = {
	RequestDash  = "RequestDash",
	RequestSlide = "RequestSlide",
	DashEffect   = "DashEffect",
	SlideStart   = "SlideStart",
	SlideEnd     = "SlideEnd",
	WallRunStart = "WallRunStart",
	WallRunEnd   = "WallRunEnd",
	EnergySync   = "EnergySync",
}

return MovementSettings