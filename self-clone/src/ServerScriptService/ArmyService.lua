local Players = game:GetService("Players")

local Army = require(script.Parent.Army)

local ArmyService = {}
ArmyService._armies = {} 

function ArmyService.CreateArmy(player)
	local army = Army.new(player)
	ArmyService._armies[player] = army
	return army
end

function ArmyService.GetArmy(player)
	return ArmyService._armies[player]
end

function ArmyService.GetAllArmies()
	return ArmyService._armies
end

function ArmyService.RemoveArmy(player)
	local army = ArmyService._armies[player]
	if army then
		army:Destroy()
		ArmyService._armies[player] = nil
	end
end

Players.PlayerRemoving:Connect(function(player)
	ArmyService.RemoveArmy(player)
end)

return ArmyService
