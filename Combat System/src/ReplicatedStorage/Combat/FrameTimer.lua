--[[
	FRAME TIMER
	
	Provides deterministic frame counting.
	All combat timing is frame-based, not time-based.
	
	60 FPS is the target, but this handles variable framerates.
]]

local FrameTimer = {}
FrameTimer.__index = FrameTimer

local TARGET_FPS = 60
local FRAME_TIME = 1 / TARGET_FPS

function FrameTimer.new()
	local self = setmetatable({}, FrameTimer)
	
	self.FrameCount = 0
	self.AccumulatedTime = 0
	self.LastTickTime = tick()
	
	-- For frame-rate independent timing
	self.FixedDeltaTime = FRAME_TIME
	
	return self
end

--[[
	Tick the frame timer
	Returns the current frame count
]]
function FrameTimer:Tick(deltaTime: number): number
	self.AccumulatedTime = self.AccumulatedTime + deltaTime
	
	-- Fixed timestep: process frames in fixed increments
	-- This keeps combat timing consistent regardless of actual FPS
	while self.AccumulatedTime >= self.FixedDeltaTime do
		self.AccumulatedTime = self.AccumulatedTime - self.FixedDeltaTime
		self.FrameCount = self.FrameCount + 1
	end
	
	return self.FrameCount
end

--[[
	Get current frame
]]
function FrameTimer:GetFrame(): number
	return self.FrameCount
end

--[[
	Convert frames to seconds
]]
function FrameTimer:FramesToSeconds(frames: number): number
	return frames / TARGET_FPS
end

--[[
	Convert seconds to frames
]]
function FrameTimer:SecondsToFrames(seconds: number): number
	return math.floor(seconds * TARGET_FPS)
end

--[[
	Reset frame count (useful for testing)
]]
function FrameTimer:Reset()
	self.FrameCount = 0
	self.AccumulatedTime = 0
end

return FrameTimer
