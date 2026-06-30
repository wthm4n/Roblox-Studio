--!strict
-- Scheduler.lua
-- The ONLY RunService.Heartbeat connection in the whole minion framework.
-- Systems register themselves once; the scheduler ticks them in order.
--
-- Why this exists: per-component Heartbeat connections (the old design)
-- mean N closures, N upvalue tables, and N independent dispatch overheads
-- at N minions. One Heartbeat driving M systems (M is small and fixed,
-- e.g. 2-4) scales as O(1) connections regardless of minion count.
--
-- Systems that need to stagger work across frames (e.g. FollowSystem,
-- which doesn't need every minion repathed every single frame) use the
-- bucket helpers below instead of processing their whole entity list
-- every tick.

local RunService = game:GetService("RunService")

export type System = {
	Name: string,
	Update: (self: System, dt: number) -> (),
}

local Scheduler = {}

local systems: { System } = {}
local connection: RBXScriptConnection? = nil

function Scheduler.RegisterSystem(system: System)
	table.insert(systems, system)
end

function Scheduler.UnregisterSystem(system: System)
	for i, s in ipairs(systems) do
		if s == system then
			table.remove(systems, i)
			return
		end
	end
end

function Scheduler.Start()
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(function(dt: number)
		for _, system in ipairs(systems) do
			system:Update(dt)
		end
	end)
end

function Scheduler.Stop()
	if connection then
		connection:Disconnect()
		connection = nil
	end
end

--[[
	Bucket helper: given a frame counter and a bucket count, returns which
	bucket index (1..bucketCount) is "active" this frame. Systems use this
	to spread O(n) work across multiple frames instead of doing all n
	items on every single tick.

	Example: 1000 follow-records, BUCKET_COUNT = 10 -> each frame only
	~100 records get their distance/direction re-evaluated, so the full
	population is refreshed every 10 frames (~0.16s at 60fps) instead of
	every frame. Combined with Move()'s persistent-velocity semantics
	(see MovementComponent), minions keep moving smoothly between
	refreshes instead of stalling.
]]
function Scheduler.GetBucket(frameCounter: number, bucketCount: number): number
	return (frameCounter % bucketCount) + 1
end

return Scheduler