--!strict
-- FormationGenerator.lua
-- Pure, stateless math: GetOffset(shape, slotId, spacing) -> (Vector3 offset, Vector3 jitter)
--
-- The critical property: every shape here is a CLOSED-FORM function of
-- slotId alone (plus spacing). Computing slot #501's offset never requires
-- knowing about slots #1-500, and never requires iterating or regenerating
-- the rest of the formation. This is what lets FormationComponent allocate
-- exactly one slot on join and free exactly one slot on leave, instead of
-- rebuilding the whole formation array (the spec's "never regenerate the
-- entire formation" requirement).
--
-- Changing formation SHAPE is still O(n) -- every existing slot's offset
-- has to be recomputed because the shape function changed -- but that is
-- the one explicitly-allowed O(n) "Formation rebuild" in the spec, and it
-- reuses the existing slot tables (FormationComponent:SetShape), it does
-- not reallocate them.

export type ShapeName = "Circle" | "Ring" | "Square" | "Triangle" | "Grid"

local FormationGenerator = {}

-- ---------------------------------------------------------------------
-- Deterministic per-slot jitter (idle "breathing" offset). A hash of the
-- slot id, not math.random, so it's stable across reuse/rebuild and never
-- needs to be stored separately from the id that produced it.
-- ---------------------------------------------------------------------
local function jitterFor(slotId: number): Vector3
	local jx = (math.sin(slotId * 12.9898) * 43758.5453) % 1 - 0.5
	local jz = (math.sin(slotId * 78.2330) * 12543.5732) % 1 - 0.5
	return Vector3.new(jx, 0, jz) * 0.35
end

-- ---------------------------------------------------------------------
-- Concentric "ring layer" math shared by Circle/Ring/Square.
-- Layer 0 = the single center slot. Layer k (k>=1) holds 6k slots, so
-- point density per ring stays constant as the formation grows instead of
-- one ring getting more and more crowded. Closed-form (sqrt + a couple of
-- corrective steps for float rounding) -- O(1), not a search loop.
-- ---------------------------------------------------------------------
local function ringLayerOf(slotId: number): (number, number, number)
	local index = slotId -- 1-based
	if index <= 1 then
		return 0, 0, 1
	end

	local m = index - 2 -- 0-based position among all non-center "ring slots"
	local k = math.floor((-1 + math.sqrt(1 + (4 * m) / 3)) / 2)
	if k < 0 then
		k = 0
	end
	-- at most a couple of nudges to correct float rounding at the boundary
	while 3 * k * (k + 1) <= m do
		k += 1
	end
	while k > 0 and 3 * (k - 1) * k > m do
		k -= 1
	end

	local cumulativeBeforeLayer = 3 * k * (k - 1)
	local posInLayer = m - cumulativeBeforeLayer
	local capacity = if k == 0 then 1 else 6 * k
	return k, posInLayer, capacity
end

local function circleOffset(slotId: number, spacing: number): Vector3
	local layer, posInLayer, capacity = ringLayerOf(slotId)
	if layer == 0 then
		return Vector3.zero
	end
	-- stagger alternating layers by half a slot-width so minions don't
	-- line up radially in dead-straight spokes
	local stagger = if layer % 2 == 0 then 0 else (math.pi / capacity)
	local angle = (posInLayer / capacity) * (2 * math.pi) + stagger
	local radius = layer * spacing
	return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
end

local function squareOffset(slotId: number, spacing: number): Vector3
	local layer, posInLayer, _capacity = ringLayerOf(slotId)
	if layer == 0 then
		return Vector3.zero
	end
	-- walk the perimeter of an (2*layer)x(2*layer) square, 8*layer points
	-- evenly spaced, starting at the top-left corner and going clockwise
	local side = layer * 2
	local perim = 8 * layer
	local t = (posInLayer / perim) * (4 * side) -- distance traveled along perimeter, 0..4*side
	local half = layer * spacing
	local seg = 2 * half
	local d = t * (seg / side) -- map back into world units along one side

	if t < side then
		return Vector3.new(-half + d, 0, -half)
	elseif t < side * 2 then
		return Vector3.new(half, 0, -half + (d - seg))
	elseif t < side * 3 then
		return Vector3.new(half - (d - seg * 2), 0, half)
	else
		return Vector3.new(-half, 0, half - (d - seg * 3))
	end
end

-- Triangle / phalanx wedge: row r (0-based) holds (r+1) slots, centered.
-- Row of slotId found via the inverse triangular-number formula, closed
-- form, no search.
local function triangleOffset(slotId: number, spacing: number): Vector3
	local index = slotId - 1 -- 0-based
	local row = math.floor((-1 + math.sqrt(1 + 8 * index)) / 2)
	local rowStart = (row * (row + 1)) // 2
	local posInRow = index - rowStart
	local rowWidth = row + 1
	local x = (posInRow - (rowWidth - 1) / 2) * spacing
	local z = row * spacing
	return Vector3.new(x, 0, z)
end

-- Grid: simple row-major layout, fixed column count derived from spacing
-- alone (not from total population), so slot #N's column/row is O(1).
local GRID_WIDTH = 12
local function gridOffset(slotId: number, spacing: number): Vector3
	local index = slotId - 1 -- 0-based
	local col = index % GRID_WIDTH
	local row = index // GRID_WIDTH
	local x = (col - (GRID_WIDTH - 1) / 2) * spacing
	local z = row * spacing
	return Vector3.new(x, 0, z)
end

local SHAPES: { [ShapeName]: (number, number) -> Vector3 } = {
	Circle = circleOffset,
	Ring = circleOffset, -- alias: same concentric-ring math
	Square = squareOffset,
	Triangle = triangleOffset,
	Grid = gridOffset,
}

-- GetOffset returns both the shape offset AND the deterministic jitter,
-- since callers always want both and computing jitter is free (one hash).
function FormationGenerator.GetOffset(shape: ShapeName, slotId: number, spacing: number): (Vector3, Vector3)
	local fn = SHAPES[shape] or circleOffset
	return fn(slotId, spacing), jitterFor(slotId)
end

function FormationGenerator.IsValidShape(shape: string): boolean
	return SHAPES[shape :: ShapeName] ~= nil
end

return FormationGenerator
