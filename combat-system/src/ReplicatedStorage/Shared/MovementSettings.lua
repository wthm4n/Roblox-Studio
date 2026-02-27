--[[
	MovementSettings.lua
	Shared configuration for movement constants and animations.
	Place in: ReplicatedStorage/Shared/MovementSettings
]]

local MovementSettings = {}

MovementSettings.Animations = {
	-- Basic movement
	Idle  = "rbxassetid://133939959372694",
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

return MovementSettings
