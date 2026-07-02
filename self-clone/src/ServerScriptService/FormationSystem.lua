-- ServerScriptService/FormationSystem.lua
-- Runs every Heartbeat via the Scheduler. This is the entire Phase 1
-- gameplay loop:
--
--   for every army
--       update anchor
--       for every minion
--           desiredPosition
--           movement:SetTarget()
--           animation:SetMoving()

local ArmyService = require(script.Parent.ArmyService)

local FormationSystem = {}
FormationSystem.Name = "FormationSystem"

local function updateAnchor(army)
	local owner = army.Owner
	local character = owner.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end

	army.Anchor = rootPart.CFrame
end

function FormationSystem.Update(_dt)
	for _, army in pairs(ArmyService.GetAllArmies()) do
		updateAnchor(army)

		for _, minion in ipairs(army.Minions) do
			local desiredPosition = army:GetDesiredPosition(minion)

			minion.Movement:SetTarget(desiredPosition)
			local isMoving = minion.Movement:Move()

			minion.Animation:SetMoving(isMoving)
		end
	end
end

return FormationSystem
