local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scheduler = require(ReplicatedStorage.Framework.Scheduler)

local ArmyService = require(script.Parent.ArmyService)
local MinionService = require(script.Parent.MinionService)
local FormationSystem = require(script.Parent.FormationSystem)
local CollisionService = require(script.Parent.CollisionService)

local STARTING_MINIONS = 100

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

Scheduler.Register(FormationSystem)
Scheduler.Start()

print("[Init] Phase 1 systems started: Army -> Minions -> Formation -> Movement -> Animation")
