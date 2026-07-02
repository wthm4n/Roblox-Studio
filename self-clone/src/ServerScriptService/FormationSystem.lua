local ArmyService = require(script.Parent.ArmyService)

local FormationSystem = {}
FormationSystem.Name = "FormationSystem"

local function updateAnchor(army)
	if army.Task then
		
		return
	end

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
	army.Shape = "Wedge"
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
