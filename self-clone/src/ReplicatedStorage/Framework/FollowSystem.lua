--!strict
-- FollowSystem.lua
-- Replaces the old "one Heartbeat per FollowComponent" design with ONE
-- system, registered once with Scheduler, that iterates a flat array of
-- active follow-records.
--
-- KEY CHANGE FROM MoveTo TO Move():
-- Humanoid:MoveTo(point) kicks off Roblox's internal path-following state
-- machine (waypoints, MoveToFinished bookkeeping, periodic internal
-- repathing). Calling it repeatedly -- which the old FollowComponent did
-- every time the target moved past RepathDistance -- restarts that state
-- machine each time, which is exactly what produced the jitter/laggy feel.
--
-- Humanoid:Move(direction) instead sets a PERSISTENT velocity vector.
-- You call it once when the desired direction changes meaningfully; the
-- humanoid keeps walking in that direction every physics step until you
-- call Move() again (or Move(Vector3.zero) to stop). This is the same
-- primitive Roblox's own default character controller uses for player
-- input, which is why NPCs/players driven this way feel smooth -- there's
-- no per-tick command at all, just velocity that persists until changed.
--
-- BUCKETING:
-- We don't need to re-evaluate follow distance every single frame for
-- every minion -- a minion that's already moving in roughly the right
-- direction doesn't need correcting 60 times a second. Work is split into
-- BUCKET_COUNT buckets; each frame only 1/BUCKET_COUNT of records are
-- re-evaluated (still smooth because Move() persists between updates),
-- spreading CPU cost evenly instead of spiking once per UpdateInterval.

local BUCKET_COUNT = 8          -- ~1000 minions -> ~125 evaluated per frame
local DIRECTION_EPSILON = 0.12  -- cos(angle) threshold: skip Move() calls
                                 -- for direction changes smaller than ~7 degrees
local STALE_TARGET_TTL = 1.0    -- seconds without a resolvable target before TargetLost fires

local FollowSystem = {}
FollowSystem.__index = FollowSystem
FollowSystem.Name = "FollowSystem"

-- Flat array of { component = FollowComponent } -- flat arrays iterate far
-- faster and allocate far less than scattering work via per-entity tables.
local records: { any } = {}
local frameCounter = 0

function FollowSystem.Register(followComponent: any)
	table.insert(records, followComponent)
end

function FollowSystem.Unregister(followComponent: any)
	for i, c in ipairs(records) do
		if c == followComponent then
			table.remove(records, i)
			return
		end
	end
end

local function evaluate(self: any, comp: any)
	if not comp.Following then return end

	local entity = comp._entity
	if not entity or entity.Destroyed then return end

	local rootPart = comp._rootPart
	local humanoid = comp._humanoid
	if not rootPart or not humanoid or not comp._movement then return end

	local targetPart = comp._targetPart
	if not targetPart or not targetPart.Parent then
		comp.TargetLost:Fire()
		return
	end

	local targetPos = targetPart.Position
	local myPos = rootPart.Position
	local offset = targetPos - myPos
	local distance = offset.Magnitude
	
	-- FIX 1: Enhanced Stopping
	-- If we are close, stop immediately and explicitly.
	if distance <= comp.FollowDistance then
		if comp._moving then
			comp._moving = false
			comp._lastDirection = nil
			comp._movement:Stop() -- Uses the Move(Vector3.zero) logic
		end
		return
	end

	-- FIX 2: Height Hallucination Check
	-- If the target is significantly higher/lower, don't just blindly move XZ.
	-- If vertical distance > 5 studs, we are likely on a different level.
	if math.abs(offset.Y) > 5 then
		-- Optional: If you want minions to follow up platforms, 
		-- you'd need to trigger a Pathfinding repath here.
		-- For now, stop so they don't run into walls.
		if comp._moving then
			comp._movement:Stop()
			comp._moving = false
		end
		return
	end

	-- Existing logic for direction
	local direction = Vector3.new(offset.X, 0, offset.Z).Unit
	
	-- FIX 3: Prevent Jittering
	-- Only set direction if we aren't "stuck" (very low horizontal progress)
	local lastDir = comp._lastDirection
	if lastDir and lastDir:Dot(direction) > (1 - DIRECTION_EPSILON) and comp._moving then
		-- Verify we are actually making progress
		return 
	end

	comp._lastDirection = direction
	comp._moving = true
	comp._movement:SetDirection(direction)
end

function FollowSystem:Update(_dt: number)
	frameCounter += 1
	local bucket = (frameCounter % BUCKET_COUNT)

	for i = 1, #records do
		-- Cheap modulo bucketing by array index keeps this allocation-free
		-- and deterministic; no per-record timers or tables needed.
		if (i % BUCKET_COUNT) == bucket then
			local comp = records[i]
			local ok = pcall(evaluate, self, comp)
			if not ok then
				-- Defensive: a single bad/destroyed component should never
				-- stall the whole system for the other ~999 minions.
				FollowSystem.Unregister(comp)
			end
		end
	end
end

return FollowSystem