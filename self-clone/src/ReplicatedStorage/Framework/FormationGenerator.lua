-- ReplicatedStorage/Framework/FormationGenerator.lua
-- Pure math. No state, no side effects, no requires from game systems.

local FormationGenerator = {}

-- Returns a Vector3 local-space offset (relative to the army anchor CFrame)
-- for `index` out of `count` minions, arranged in `shape` with `spacing`
-- units between neighbors.
function FormationGenerator.GetOffset(index, count, shape, spacing)
	spacing = spacing or 6

	if shape == "Circle" then
		if count <= 1 then
			return Vector3.new(0, 0, -spacing)
		end

		local angle = (index - 1) / count * math.pi * 2
		local radius = spacing * math.max(1, count / (math.pi * 2))

		return Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
	elseif shape == "Grid" then
		local columns = math.ceil(math.sqrt(count))
		local row = math.floor((index - 1) / columns)
		local col = (index - 1) % columns

		local offsetX = (col - (columns - 1) / 2) * spacing
		local offsetZ = row * spacing + spacing

		return Vector3.new(offsetX, 0, offsetZ)
	end

	-- Fallback: single line behind the anchor
	return Vector3.new(0, 0, index * spacing)
end

return FormationGenerator
