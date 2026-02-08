--[[
    MovementSettings.lua - WITH WEDGE CLIMBING
    
    Complete movement system configuration
]]
local MovementSettings = {}
-- ========================================
-- PLAYER SETTINGS
-- ========================================
MovementSettings.Player = {
	MaxHealth = 100,
	HealthRegen = 2,
	WalkSpeed = 16,
	RunSpeed = 22,
	HipHeight = 2,
}
-- ========================================
-- DASH SYSTEM
-- ========================================
MovementSettings.Dash = {
	Key = Enum.KeyCode.Q,
	Speed = 95,
	Duration = 0.25,
	Cooldown = 1.0,
}
-- ========================================
-- SLIDE SYSTEM
-- ========================================
MovementSettings.Slide = {
	Key = Enum.KeyCode.C,
	Speed = 45,
	Duration = 1.2,
	Cooldown = 2.0,
	HipHeight = 0.5,
}
-- ========================================
-- WALL RUN SYSTEM
-- ========================================
MovementSettings.WallRun = {
	DetectionRange = 3.5,
	MaxSlopeAngle = 0.3,
	MinSpeed = 10,
	Speed = 30,
	Duration = 4.0,
	GracePeriod = 0.3,
	Cooldown = 0.5,
	JumpOffForce = 60,
	AutoTrigger = true,
}
-- ========================================
-- DOUBLE JUMP SYSTEM
-- ========================================
MovementSettings.DoubleJump = {
	Enabled = true,
	Force = 50,
}
-- ========================================
-- WEDGE CLIMBING SYSTEM
-- ========================================
MovementSettings.WedgeClimb = {
	-- Detection
	DetectionRange = 4, -- How far to detect climbable surfaces
	-- Physics
	ClimbSpeed = 12, -- Upward climbing speed
	-- Ledge Grab
	LedgeGrabRange = 3, -- Range to detect ledge edges
	LedgeHangOffset = 2, -- Distance from ledge while hanging
	ClimbUpSpeed = 8, -- Speed when climbing over ledge
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
	-- Wedge climbing
	LedgeHang = "rbxassetid://130912033735566",
	LedgeClimb = "rbxassetid://126959978444547",
}
return table.freeze(MovementSettings)