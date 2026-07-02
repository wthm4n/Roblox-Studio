local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FormationGenerator = require(ReplicatedStorage.Framework.FormationGenerator)

local Army = {}
Army.__index = Army


function Army.new(owner)
	return setmetatable({
		Owner = owner,
		Minions = {},
		Shape = "Wedge",
		Spacing = 6,
		FormationConfig = {
    		Angle = 30,
		},
		Anchor = CFrame.new(),

		Task = nil,       
		TaskTarget = nil, 
	}, Army)
end

function Army:AddMinion(minion)
	table.insert(self.Minions, minion)
end

function Army:RemoveMinion(minion)
	local index = table.find(self.Minions, minion)
	if index then
		table.remove(self.Minions, index)
	end
end

function Army:GetDesiredPosition(minion)
	local index = table.find(self.Minions, minion)
	if not index then
		return self.Anchor.Position
	end

	local offset = FormationGenerator.GetOffset(index, #self.Minions, self.Shape, self.Spacing, self.FormationConfig)
	return (self.Anchor * CFrame.new(offset)).Position
end

function Army:Destroy()
	for _, minion in ipairs(self.Minions) do
		if minion.Destroy then
			minion:Destroy()
		end
	end
	table.clear(self.Minions)
end

return Army
