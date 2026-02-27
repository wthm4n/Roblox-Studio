--[[
	Config.lua
	Central configuration for the AI NPC system.
--]]

local Config = {}

-- ─── Detection ─────────────────────────────────────────────────────────────
Config.Detection = {
	SightRange        = 9999,
	SightAngle        = 180,
	HearRange         = 50,
	LoseTargetTime    = 8,
	RaycastCooldown   = 0.05,
}

-- ─── Movement ──────────────────────────────────────────────────────────────
Config.Movement = {
	WalkSpeed         = 14,
	ChaseSpeed        = 24,
	FleeSpeed         = 26,
	JumpPower         = 50,
	PathRecalcDelay   = 0.2,
	StuckTimeout      = 1.2,
	StuckThreshold    = 0.8,
	WaypointReachDist = 1.5,
}

-- ─── Combat ────────────────────────────────────────────────────────────────
Config.Combat = {
	AttackRange       = 7,
	AttackCooldown    = 1.0,
	Damage            = 15,
	FleeHealthPercent = 0.25,
	ThreatDecayRate   = 0.05,
}

-- ─── Patrol ────────────────────────────────────────────────────────────────
Config.Patrol = {
	WaitTime          = 2.5,
	RandomWander      = true,
	WanderRadius      = 30,
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

-- ─── Personalities ─────────────────────────────────────────────────────────

Config.Passive = {
	FleeRadius        = 30,    -- studs; player within this = flee
	HideSearchRadius  = 40,    -- studs; search for cover within this
	AllyAlertRadius   = 50,    -- studs; alert allies within this
	FleeSpeed         = 22,
	HideDuration      = 8,     -- seconds to stay hidden before re-checking
}

Config.Scared = {
	FleeRadius        = 45,
	PanicSpeed        = 20,
	SlowChance        = 0.3,   -- 30% chance to "trip" and slow down
	FreezeChance      = 0.2,   -- 20% chance to freeze briefly
	FreezeDuration    = 1.5,   -- seconds frozen
	SlowMultiplier    = 0.4,   -- speed multiplier when tripped
	SlowDuration      = 2.0,   -- seconds of slow after trip
}

Config.Aggressive = {
	HuntRange         = 150,   -- studs; will path to player even if not in sight
	PredictSteps      = 12,    -- frames ahead to predict player position
	ComboCount        = 3,     -- hits per combo
	ComboWindow       = 0.4,   -- seconds between combo hits
	RetreatingHP      = 0.30,  -- retreat below 30% HP
	RetreatingDist    = 20,    -- studs to back off before re-engaging
	ChaseSpeed        = 28,    -- faster than base
}

Config.Tactical = {
	FlankAngle        = 90,      -- degrees off direct line to flank
	FlankDistance     = 18,      -- studs from target to flank point
	CoverSearchRadius = 35,      -- studs to search for cover
	CoverMinHeight    = 3,       -- minimum part height to count as cover
	CoordRadius       = 60,      -- studs; coordinate with NPCs within this
	LoSCheckInterval  = 0.2,     -- how often to check if exposed
	SuppressTime      = 3,       -- seconds to suppress before pushing
}

return Config
