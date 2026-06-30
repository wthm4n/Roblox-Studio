--!strict
-- FormationSystem.lua
-- The ONE system (registered once with Scheduler, same pattern as
-- FollowSystem) that drives every Army's formation in the game.
--
-- Two passes per tick, deliberately split by cost:
--
--   1. Anchor + interpolation pass -- O(n) over ALL occupied slots, EVERY
--      frame. This is cheap: a CFrame:PointToWorldSpace + a Lerp per
--      slot, no engine calls. Doing this every frame is what keeps
--      formations smooth (spec: "Formation should not snap").
--
--   2. Movement pass -- only actually calls into MovementComponent
--      (:SetDirection), which is the expensive-ish part (touches the
--      Humanoid). Bucketed across BUCKET_COUNT frames exactly like
--      FollowSystem, for the exact same reason: a slot that's already
--      walking in roughly the right direction doesn't need re-aiming
--      every single tick, and persistent-velocity Move() keeps it
--      walking smoothly between re-aims anyway.
--
-- Both passes iterate FLAT arrays (formations list, slots' own _occupied
-- arrays) -- never nested "for every army, for every OTHER army's
-- minions" loops, so this stays O(n) total across the whole game, never
-- O(n^2).

local BUCKET_COUNT = 8
local DIRECTION_EPSILON = 0.12  -- skip re-aiming for ~7 degree direction changes
local ARRIVE_DISTANCE = 1.5     -- stop walking once this close to the slot

local FormationSystem = {}
FormationSystem.__index = FormationSystem
FormationSystem.Name = "FormationSystem"

-- Flat list of every live FormationComponent (one per Army). Iterated in
-- full every frame for pass 1; ~tens of entries even with hundreds of
-- players, so this is not the bottleneck -- the per-slot work inside each
-- formation is.
local formations: { any } = {}
local frameCounter = 0

function FormationSystem.RegisterFormation(formation: any)
	table.insert(formations, formation)
end

function FormationSystem.UnregisterFormation(formation: any)
	for i, f in ipairs(formations) do
		if f == formation then
			table.remove(formations, i)
			return
		end
	end
end

local function evaluateSlotMovement(slot: any)
	if not slot.Occupied then
		return
	end
	local minion = slot.AssignedMinion
	if not minion or minion.Destroyed then
		return
	end

	local movement = slot._movement
	if not movement then
		return
	end

	local model = minion.Model
	local rootPart = model and model:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	local myPos = (rootPart :: BasePart).Position
	local targetPos = slot.WorldPosition
	local offset = targetPos - myPos
	local distance = offset.Magnitude

	if distance <= ARRIVE_DISTANCE then
		if slot._moving then
			slot._moving = false
			slot._lastDirection = nil
			movement:Stop()
		end
		return
	end

	if math.abs(offset.Y) > 6 then
		-- Different level / unreachable height for now; stop rather than
		-- walk into a wall. A future pathfinding-aware system can hook in
		-- here without FormationSystem needing to change.
		if slot._moving then
			movement:Stop()
			slot._moving = false
		end
		return
	end

	local direction = Vector3.new(offset.X, 0, offset.Z).Unit
	local lastDir = slot._lastDirection
	if lastDir and slot._moving and lastDir:Dot(direction) > (1 - DIRECTION_EPSILON) then
		return
	end

	slot._lastDirection = direction
	slot._moving = true
	movement:SetDirection(direction)
end

function FormationSystem:Update(dt: number)
	-- Pass 1: every occupied slot, every frame. Pure math, no engine calls.
	for _, formation in ipairs(formations) do
		formation:InterpolateSlots(dt)
	end

	-- Pass 2: bucketed movement re-aim.
	frameCounter += 1
	local bucket = frameCounter % BUCKET_COUNT

	local globalIndex = 0
	for _, formation in ipairs(formations) do
		local occupied = formation._occupied
		for i = 1, #occupied do
			globalIndex += 1
			if (globalIndex % BUCKET_COUNT) == bucket then
				local slot = occupied[i]
				local ok = pcall(evaluateSlotMovement, slot)
				if not ok then
					-- A single bad slot/minion should never stall every
					-- other army's movement update.
					formation:RemoveMinion(slot.AssignedMinion)
				end
			end
		end
	end
end

return FormationSystem
