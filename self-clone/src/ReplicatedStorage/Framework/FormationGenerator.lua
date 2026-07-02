local FormationGenerator = {}

local function computeCircle(index, count, spacing, config)
	if count <= 1 then
		return Vector3.new(0, 0, -spacing)
	end

	
	local rings = (config and config.Rings) or 1
	rings = math.clamp(rings, 1, count)

	local perRing = math.ceil(count / rings)
	local ring = math.floor((index - 1) / perRing)
	local indexInRing = (index - 1) % perRing
	local countInRing = math.min(perRing, count - ring * perRing)

	local angle = (countInRing <= 1) and 0 or (indexInRing / countInRing) * math.pi * 2
	local radius = spacing * (ring + 1) * math.max(1, countInRing / (math.pi * 2))

	return Vector3.new(math.sin(angle) * radius, 0, math.cos(angle) * radius)
end

local function computeGrid(index, count, spacing, config)
	
	local columns = (config and config.Columns) or math.ceil(math.sqrt(count))
	local row = math.floor((index - 1) / columns)
	local col = (index - 1) % columns

	local offsetX = (col - (columns - 1) / 2) * spacing
	local offsetZ = row * spacing + spacing

	return Vector3.new(offsetX, 0, offsetZ)
end

local function computeLine(index, count, spacing, config)
	
	local axis = (config and config.Axis) or "X"

	if axis == "Z" then
		return Vector3.new(0, 0, index * spacing)
	end

	local centered = (index - 1) - (count - 1) / 2
	return Vector3.new(centered * spacing, 0, spacing)
end

local function computeWedge(index, count, spacing, config)
	
	local angle = math.rad((config and config.Angle) or 30)
	local row = math.ceil(index / 2)
	local side = (index % 2 == 0) and 1 or -1

	local offsetX = side * row * spacing * math.sin(angle)
	local offsetZ = row * spacing * math.cos(angle)

	return Vector3.new(offsetX, 0, offsetZ)
end

local function computeBox(index, count, spacing, config)
	
	
	local halfSize = (config and config.Size) or (spacing * math.max(1, math.ceil(count / 4)) / 2)
	local angle = (count <= 1) and 0 or (index - 1) / count * math.pi * 2

	local dirX, dirZ = math.sin(angle), math.cos(angle)
	local scale = halfSize / math.max(math.abs(dirX), math.abs(dirZ), 0.0001)

	return Vector3.new(dirX * scale, 0, dirZ * scale)
end


function FormationGenerator.GetOffset(index, count, shape, spacing, config)
	spacing = spacing or 6

	if shape == "Circle" then
		return computeCircle(index, count, spacing, config)
	elseif shape == "Grid" then
		return computeGrid(index, count, spacing, config)
	elseif shape == "Line" then
		return computeLine(index, count, spacing, config)
	elseif shape == "Wedge" then
		return computeWedge(index, count, spacing, config)
	elseif shape == "Box" then
		return computeBox(index, count, spacing, config)
	end

	
	return Vector3.new(0, 0, index * spacing)
end

return FormationGenerator
