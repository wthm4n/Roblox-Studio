--[[
	Config.lua
	Central configuration for the AI NPC system.
--]]

local Config = {}

-- ─── Detection ─────────────────────────────────────────────────────────────
Config.Detection = {
	SightRange        = 120,   -- restore to sane value — 9999 breaks personalities
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
	FleeRadius        = 30,
	HideSearchRadius  = 40,
	AllyAlertRadius   = 50,
	FleeSpeed         = 22,
	HideDuration      = 8,
	RetreatingHP      = 0.30,
}

Config.Scared = {
	FleeRadius        = 45,
	PanicSpeed        = 20,
	SlowChance        = 0.3,
	FreezeChance      = 0.2,
	FreezeDuration    = 1.5,
	SlowMultiplier    = 0.4,
	SlowDuration      = 2.0,
}

Config.Aggressive = {
	HuntRange         = 150,
	PredictSteps      = 12,
	ComboCount        = 3,
	ComboWindow       = 0.4,
	RetreatingHP      = 0.30,
	RetreatingDist    = 20,
	ChaseSpeed        = 28,
}

Config.Tactical = {
	FlankAngle        = 90,
	FlankDistance     = 18,
	CoverSearchRadius = 35,
	CoverMinHeight    = 3,
	CoordRadius       = 60,
	LoSCheckInterval  = 0.2,
	SuppressTime      = 3,
}

return Config