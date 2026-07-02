local ResourceService = require(script.Parent.ResourceService)

local TaskService = {}
TaskService.Name = "TaskService"

local HARVEST_DPS_PER_MINION = 8
local HARVEST_SPACING = 5

local _activeHarvests = {} 

local function isMinionInPosition(minion)
	return minion.Movement and not minion.Movement:IsMoving()
end

local function clearTask(army)
	army.Task = nil
	army.TaskTarget = nil
	army.Shape = "Wedge"
	army.FormationConfig = { Angle = 90 }
	army.Spacing = 6

	_activeHarvests[army] = nil
end


function TaskService.AssignHarvest(army, node)
	if not army or not node or node._destroyed then
		return
	end

	if army.Task == "Harvest" and army.TaskTarget == node then
		return 
	end

	army.Task = "Harvest"
	army.TaskTarget = node
	army.Shape = "Circle"
	army.Spacing = HARVEST_SPACING
	army.FormationConfig = { Rings = 1 }
	army.Anchor = node.Model:GetPivot()

	node:AssignArmy(army)
	_activeHarvests[army] = node
end

function TaskService.Update(dt)
	for army, node in pairs(_activeHarvests) do
		if node._destroyed then
			clearTask(army)
			continue
		end

		local damageThisTick = 0
		for _, minion in ipairs(army.Minions) do
			if isMinionInPosition(minion) then
				damageThisTick += HARVEST_DPS_PER_MINION * dt
			end
		end

		if damageThisTick > 0 and node:Harvest(damageThisTick) then
			ResourceService.SpawnPickups(node, army.Owner)
			node:Destroy()
			ResourceService.ScheduleRespawn(node)
			clearTask(army)
		end
	end
end

return TaskService
