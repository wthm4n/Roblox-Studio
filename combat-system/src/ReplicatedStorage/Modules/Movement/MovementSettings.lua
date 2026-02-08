--[[
    MovementSettings.lua - UPDATED FOR CAMERA CONTROL
    
    Complete movement system configuration
]]
local MovementSettings = {}
-- ========================================
-- PLAYER SETTINGS
-- ========================================
MovementSettings.Player = {
	MaxHealth = 100,
	HealthRegen = 2,
	-- Movement speeds (no run key - automatic based on velocity)
	WalkSpeed = 16,
	RunSpeed = 22, -- Used for animation switching threshold
	-- Character properties
	HipHeight = 2,
}
-- ========================================
-- DASH SYSTEM
-- ========================================
MovementSettings.Dash = {
	Key = Enum.KeyCode.Q,
	Speed = 95, -- Dash speed
	Duration = 0.25, -- How long dash lasts
	Cooldown = 1.0, -- Cooldown between dashes
}
-- ========================================
-- SLIDE SYSTEM
-- ========================================
MovementSettings.Slide = {
	Key = Enum.KeyCode.C,
	Speed = 45, -- Slide speed
	Duration = 1.2, -- How long slide lasts
	Cooldown = 2.0, -- Cooldown between slides
	HipHeight = 0.5, -- Lowered hip height during slide
}
-- ========================================
-- WALL RUN SYSTEM - TRUE CAMERA CONTROL
-- ========================================
MovementSettings.WallRun = {
	-- Detection
	DetectionRange = 3.5, -- How far to detect walls (studs)
	MaxSlopeAngle = 0.3, -- Max Y component of wall normal (0 = vertical, 1 = horizontal)
	MinSpeed = 10, -- Minimum horizontal speed required to wall run
	-- Physics
	Speed = 30, -- Base movement speed (used for both horizontal and vertical)
	-- REMOVED: UpwardForce (camera pitch now controls vertical movement directly)

	-- Timing
	Duration = 4.0, -- Max wall run duration
	GracePeriod = 0.3, -- Time allowed to lose wall contact before ending
	Cooldown = 0.5, -- Cooldown after wall run ends
	-- Jump
	JumpOffForce = 60, -- Boost when jumping off wall
	-- Behavior
	AutoTrigger = true, -- Automatically start wall run when near wall
}
-- ========================================
-- DOUBLE JUMP SYSTEM
-- ========================================
MovementSettings.DoubleJump = {
	Enabled = true,
	Force = 50, -- Upward force for double jump
}
-- ========================================
-- ANIMATIONS
-- ========================================
MovementSettings.Animations = {
	-- Basic movement
	Idle = "rbxassetid://101974040609420",
	Walk = "rbxassetid://101695660356667",
	Run = "rbxassetid://110745974890930",
	-- Dashing
	DashW = "rbxassetid://88193156661727",
	DashA = "rbxassetid://74619303114279",
	DashS = "rbxassetid://115159060573717",
	DashD = "rbxassetid://119390596531434",
	-- Slide
	Slide = "rbxassetid://101974040609420",
	-- Wall running
	WallRunLeft = "rbxassetid://93201209088043",
	WallRunRight = "rbxassetid://78952764830119",

	-- Ledge mechanics
	LedgeHang = "rbxassetid://130912033735566",
	LedgeClimb = "rbxassetid://126959978444547",
}
return table.freeze(MovementSettings)
