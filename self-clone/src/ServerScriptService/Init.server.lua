local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scheduler = require(ReplicatedStorage.Framework.Scheduler)

local ArmyService = require(script.Parent.ArmyService)
local MinionService = require(script.Parent.MinionService)
local FormationSystem = require(script.Parent.FormationSystem)
local CollisionService = require(script.Parent.CollisionService)
local ResourceService = require(script.Parent.ResourceService)
local TaskService = require(script.Parent.TaskService)

local STARTING_MINIONS = 6

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		local rootPart = character:WaitForChild("HumanoidRootPart")

		CollisionService.SetupForPlayer(player)
		CollisionService.AssignCharacter(player, character)

		local army = ArmyService.GetArmy(player) or ArmyService.CreateArmy(player)
		army.Anchor = rootPart.CFrame

		
		if #army.Minions == 0 then
			for _ = 1, STARTING_MINIONS do
				MinionService.Spawn(army, rootPart.CFrame)
			end
		end
	end)
end

Players.PlayerAdded:Connect(onPlayerAdded)

ResourceService.Init()

ResourceService.NodeClicked:Connect(function(player, node)
	local army = ArmyService.GetArmy(player)
	if army then
		TaskService.AssignHarvest(army, node)
	end
end)

Scheduler.Register(FormationSystem)
Scheduler.Register(TaskService)
Scheduler.Start()

print("[Init] Phase 1 systems started: Army -> Minions -> Formation -> Movement -> Animation")
print("[Init] Phase 2 systems started: ResourceNode -> ResourceService -> TaskService")
