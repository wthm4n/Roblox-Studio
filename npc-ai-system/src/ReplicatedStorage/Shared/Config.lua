--[[
	Config.lua
	Central configuration for the AI NPC system.
	Adjust values here — do not hardcode them elsewhere.
--]]

local Config = {}

-- ─── Detection ─────────────────────────────────────────────────────────────
Config.Detection = {
	SightRange        = 500,   -- studs; max distance NPC can "see"
	SightAngle        = 180,   -- degrees total FOV (180 = full front hemisphere)
	HearRange         = 500,    -- studs; sound-based detection (no LoS needed)
	LoseTargetTime    = 8,     -- seconds before NPC gives up on last known pos
	RaycastCooldown   = 0.05,  -- seconds between LoS raycasts (faster checks)
}

-- ─── Movement ──────────────────────────────────────────────────────────────
Config.Movement = {
	WalkSpeed         = 14,
	ChaseSpeed        = 24,    -- noticeably faster than player (default player = 16)
	FleeSpeed         = 26,
	JumpPower         = 50,
	PathRecalcDelay   = 0.2,   -- recalc path twice as often for tighter tracking
	StuckTimeout      = 1.2,   -- catch stuck faster   -- detect stuck faster
	StuckThreshold    = 0.8,   -- lower = more sensitive to not moving   -- studs moved; below this = possibly stuck
	WaypointReachDist = 1.5,   -- tighter = better cornering around walls     -- studs; close enough to advance to next waypoint
}

-- ─── Combat ────────────────────────────────────────────────────────────────
Config.Combat = {
	AttackRange       = 7,     -- studs; slightly more generous melee range
	AttackCooldown    = 1.0,   -- slightly faster attacks
	Damage            = 15,
	FleeHealthPercent = 0.25,  -- flee when HP drops below 25%
	ThreatDecayRate   = 0.05,  -- slower threat decay so NPC stays angry longer
}

-- ─── Patrol ────────────────────────────────────────────────────────────────
Config.Patrol = {
	WaitTime          = 2.5,   -- seconds to wait at each patrol point
	RandomWander      = true,  -- if no patrol points set, wander randomly
	WanderRadius      = 30,    -- studs radius for random wander
}

-- ─── Debug ─────────────────────────────────────────────────────────────────
Config.Debug = {
	Enabled           = true,
	ShowPath          = true,
	ShowSightCone     = false,
	ShowStateLabel    = true,
	PathColor         = Color3.fromRGB(0, 200, 255),
	WaypointColor     = Color3.fromRGB(255, 100, 0),
}

return Config