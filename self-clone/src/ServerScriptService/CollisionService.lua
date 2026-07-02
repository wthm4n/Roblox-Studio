local PhysicsService = game:GetService("PhysicsService")

local CollisionService = {}

local _registeredGroups = {} 

local function ensureGroup(name)
	if _registeredGroups[name] then
		return
	end

	
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)

	_registeredGroups[name] = true
end

local function groupNames(player)
	local id = player.UserId
	return ("Player_%d"):format(id), ("Minions_%d"):format(id)
end

local function assignGroupToDescendants(model, groupName)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end

	
	model.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = groupName
		end
	end)
end


function CollisionService.SetupForPlayer(player)
	local playerGroup, minionGroup = groupNames(player)
	ensureGroup(playerGroup)
	ensureGroup(minionGroup)

	
	PhysicsService:CollisionGroupSetCollidable(playerGroup, minionGroup, false)
end


function CollisionService.AssignCharacter(player, character)
	local playerGroup = groupNames(player)
	assignGroupToDescendants(character, playerGroup)
end


function CollisionService.AssignMinion(player, minionModel)
	local _, minionGroup = groupNames(player)
	assignGroupToDescendants(minionModel, minionGroup)
end

return CollisionService
