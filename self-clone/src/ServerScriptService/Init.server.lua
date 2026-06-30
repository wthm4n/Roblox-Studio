--!strict
-- Init.server.lua
-- Spawns multiple mini versions of the player's own avatar (via RigBuilder)
-- and wires up Health, Movement, Follow, Animation, and OverheadGui.
--
-- Scheduler/systems are GLOBAL and started exactly once.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MinionService = require(script.Parent.MinionService)
local RigBuilder = require(ReplicatedStorage.Framework.RigBuilder)
local Scheduler = require(ReplicatedStorage.Framework.Scheduler)
local ArmyService = require(script.Parent.ArmyService)
local FormationSystem = require(ReplicatedStorage.Framework.FormationSystem)

local Components = ReplicatedStorage:FindFirstChild("Components")
	or ServerScriptService:FindFirstChild("Components")

assert(Components, "Components folder not found in ReplicatedStorage or ServerScriptService")

local HealthComponent = require(Components.HealthComponent)
local MovementComponent = require(Components.MovementComponent)
local AnimationComponent = require(Components.AnimationComponent)
local OverheadGuiComponent = require(Components.OverheadGuiComponent)
-- FollowComponent intentionally NOT used here: minions belong to an Army
-- now, and FormationSystem (driven by ArmyService's anchor-follow
-- Heartbeat) is the single movement authority for them. FollowComponent
-- stays available in Components/ for future non-Army NPCs only.

-- One-time, global. NOT per-minion.
Scheduler.RegisterSystem(FormationSystem)
Scheduler.Start()

local MINION_COUNT = 10
local SPAWN_RADIUS = 5

local function log(...: any)
	print("[MinionTest]", ...)
end

local function spawnMiniMeFor(player: Player, index: number)
	log(string.format("Building mini-%s #%d...", player.Name, index))

	local model = RigBuilder.BuildFromPlayer(player, {
		UniformScale = 0.55,
		HeadScale = 1.0,
		KeepFace = true,
		KeepHair = true,
		MaxAccessories = 99,
	})

	model.Parent = workspace

	if player.Character and player.Character.PrimaryPart then
		local angle = ((index - 1) / MINION_COUNT) * math.pi * 2
		local offset = Vector3.new(
			math.cos(angle) * SPAWN_RADIUS,
			0,
			math.sin(angle) * SPAWN_RADIUS
		)

		model:PivotTo(player.Character.PrimaryPart.CFrame + offset)
	end

	local entity = MinionService.Spawn(player, { Model = model })

	entity:AddComponent("Health", HealthComponent.new({
		MaxHealth = 100,
	}))

	entity:AddComponent("Movement", MovementComponent.new(18))

	entity:AddComponent("Animation", AnimationComponent.new({
		AnimationIds = {},
	}))

	entity:AddComponent("OverheadGui", OverheadGuiComponent.new())

	entity:SetAttribute("Level", 1)
	entity:SetAttribute("Rarity", "Common")

	-- Hand the minion off to the player's Army. From this point on,
	-- FormationSystem (driven by ArmyService's anchor-follow Heartbeat)
	-- is the ONLY thing that calls Movement:SetDirection on this minion.
	local army = ArmyService.GetOrCreate(player)
	army:AddMinion(entity)

	log(string.format(
		"Spawned mini-%s #%d (entity #%d).",
		player.Name,
		index,
		entity.Id
	))
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Wait()
	task.wait(1)

	for i = 1, MINION_COUNT do
		task.spawn(spawnMiniMeFor, player, i)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		for i = 1, MINION_COUNT do
			task.spawn(spawnMiniMeFor, player, i)
		end
	end
end