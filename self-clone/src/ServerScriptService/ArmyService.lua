--!strict
-- ArmyService.lua
-- Global manager: exactly one Army per Player. Mirrors MinionService's
-- shape on purpose (single registry table, O(1) keyed lookups, auto
-- cleanup on PlayerRemoving) so the two services are predictable
-- neighbors in the codebase.
--
-- The player does NOT own minions directly -- nothing outside this
-- module's Army/FormationComponent/FormationSystem trio should ever touch
-- a minion's position or movement. Future gameplay systems (mining,
-- combat, tasks...) read/write through Army's API, never around it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Army = require(script.Parent.Army)

local ArmyService = {}

-- Player -> Army. A single table keyed directly by Player reference is
-- O(1) for Create/Destroy/Get/Exists -- no secondary id-translation step.
local armies: { [Player]: Army.Army } = {}

local nextArmyId = 0
local function generateArmyId(): number
	nextArmyId += 1
	return nextArmyId
end

-- O(1). Errors on double-create rather than silently replacing, since a
-- silent replace would orphan the old Army's minions/slots.
function ArmyService.Create(player: Player): Army.Army
	if armies[player] then
		error(string.format("ArmyService: %s already has an army", player.Name), 2)
	end

	local army = Army.new(generateArmyId(), player)
	armies[player] = army
	return army
end

-- O(1). Idempotent: destroying a player with no army is a safe no-op.
function ArmyService.Destroy(player: Player)
	local army = armies[player]
	if not army then
		return
	end
	armies[player] = nil
	army:Destroy()
end

-- O(1).
function ArmyService.Get(player: Player): Army.Army?
	return armies[player]
end

-- O(1).
function ArmyService.Exists(player: Player): boolean
	return armies[player] ~= nil
end

-- Convenience: get-or-create, since most gameplay code just wants "the
-- player's army" without caring whether this is their first minion ever.
function ArmyService.GetOrCreate(player: Player): Army.Army
	return armies[player] or ArmyService.Create(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	ArmyService.Destroy(player)
end)

-- The single place that drives every Army's formation anchor. Cheap:
-- one Heartbeat connection, O(armies) per frame (tens of entries even
-- with hundreds of players), each iteration just reads the owner's
-- PrimaryPart CFrame and forwards it to Army:SetAnchor -- no engine
-- mutation here, FormationSystem's own bucketed pass handles that.
-- This replaces per-minion FollowComponent for any minion that belongs
-- to an Army: the army-as-a-whole follows the player, and
-- FormationSystem is the only thing that ever calls
-- MovementComponent:SetDirection on a formation minion.
-- IMPORTANT: anchor is position-only, NOT primaryPart.CFrame.
-- HumanoidRootPart's rotation changes constantly (every time the
-- character turns to face a direction, including just looking around
-- while standing still), and FormationComponent:InterpolateSlots()
-- rotates every slot's offset by the anchor's rotation -- so feeding it
-- the full CFrame made the whole formation spin around the player on
-- every facing change instead of just translating with their position.
-- CFrame.new(position) has identity rotation, so slot offsets stay
-- fixed in world-space orientation and only translate as the player
-- moves, which is what "follow the player" formations actually want.
RunService.Heartbeat:Connect(function()
	for player, army in pairs(armies) do
		local character = player.Character
		local primaryPart = character and character.PrimaryPart
		if primaryPart then
			army:SetAnchor(CFrame.new(primaryPart.Position))
		end
	end
end)

return ArmyService