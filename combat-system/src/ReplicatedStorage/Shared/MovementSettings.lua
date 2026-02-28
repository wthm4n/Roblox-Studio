--[[
	MovementSettings.lua
	Shared configuration for all movement constants and animations.
	Place in: ReplicatedStorage/Shared/MovementSettings
]]

local MovementSettings = {}

-- ══════════════════════════════════════════
--  ANIMATIONS
-- ══════════════════════════════════════════
MovementSettings.Animations = {
	-- Basic movement
	Idle  = "rbxassetid://98255682666444",
	Walk  = "rbxassetid://101695660356667",
	Run   = "rbxassetid://110745974890930",
	-- Dashing
	DashW = "rbxassetid://88193156661727",
	DashA = "rbxassetid://74619303114279",
	DashS = "rbxassetid://115159060573717",
	DashD = "rbxassetid://119390596531434",
	-- Slide
	Slide = "rbxassetid://79166711928073",
	-- Wall running
	WallRunLeft  = "rbxassetid://93201209088043",
	WallRunRight = "rbxassetid://78952764830119",
	-- Ledge
	LedgeHang  = "rbxassetid://130912033735566",
	LedgeClimb = "rbxassetid://126959978444547",
}

-- ══════════════════════════════════════════
--  DASH SETTINGS
-- ══════════════════════════════════════════
MovementSettings.Dash = {
	Key           = Enum.KeyCode.Q,     -- modifier key
	Speed         = 85,                  -- studs/s burst velocity
	Duration      = 0.18,               -- seconds the LinearVelocity is active
	Cooldown      = 0.8,                -- seconds between dashes
	IFrameDuration = 0.12,              -- invincibility window (seconds) — set 0 to disable
	FadeTime      = 0.06,               -- seconds to lerp velocity back to 0 at end of dash

	-- Direction keys (WASD relative to camera)
	Keys = {
		Forward  = Enum.KeyCode.W,
		Left     = Enum.KeyCode.A,
		Backward = Enum.KeyCode.S,
		Right    = Enum.KeyCode.D,
	},

	-- Animation key per direction (maps to MovementSettings.Animations)
	Animations = {
		Forward  = "DashW",
		Left     = "DashA",
		Backward = "DashS",
		Right    = "DashD",
	},
}

-- ══════════════════════════════════════════
--  SLIDE SETTINGS
-- ══════════════════════════════════════════
MovementSettings.Slide = {
	Speed            = 38,    -- studs/s during slide
	Duration         = 0.9,   -- seconds before auto-end
	CrouchHipHeight  = 0.5,   -- hip height while sliding
	DefaultHipHeight = 2.0,   -- restored after slide (R15 = 2.0, R6 = 0)
}

-- ══════════════════════════════════════════
--  WALL RUN SETTINGS
-- ══════════════════════════════════════════
MovementSettings.WallRun = {
	-- Detection raycasts (fired from HRP center)
	RayLength        = 3.2,     -- studs — how far to check for a wall
	RayCount         = 3,       -- rays spread vertically to catch uneven walls
	RaySpreadY       = 1.2,     -- vertical spread between rays (studs)

	-- Activation requirements
	MinAirTime       = 0.05,    -- must have been airborne at least this long
	MinForwardDot    = 0.35,    -- must be moving roughly toward the wall (dot product)

	-- Physics while wall running
	Gravity          = -18,     -- reduced gravity (workspace default ~196.2 studs/s²)
	ForwardSpeed     = 28,      -- studs/s forward along wall
	UpForce          = 0,       -- 0 = flat wall run at same Y; gravity is cancelled by VectorForce
	TiltAngle        = 12,      -- degrees character tilts toward wall
	MaxDuration      = 2.8,     -- seconds before forced detach

	-- Jump off wall
	WallJumpForceH   = 55,      -- horizontal (away from wall)
	WallJumpForceV   = 42,      -- vertical

	-- Surface validation
	MaxSlopeAngle    = 25,      -- degrees — wall must be nearly vertical
	MinWallHeight    = 4,       -- studs — wall must be at least this tall (raycast up check)
}

-- ══════════════════════════════════════════
--  REMOTES  (string keys — actual RemoteEvents in ReplicatedStorage/Remotes)
-- ══════════════════════════════════════════
MovementSettings.Remotes = {
	-- Server → Client: tell the dashing player's screen to play VFX
	DashEffect   = "DashEffect",    -- (player, direction: "Forward"|"Left"|"Backward"|"Right")
	-- Client → Server: request a dash
	RequestDash  = "RequestDash",   -- (direction: string)
	-- Server → All: someone started wall running
	WallRunStart = "WallRunStart",  -- (player, side: "Left"|"Right")
	-- Server → All: someone stopped wall running
	WallRunEnd   = "WallRunEnd",    -- (player)
}

return MovementSettings