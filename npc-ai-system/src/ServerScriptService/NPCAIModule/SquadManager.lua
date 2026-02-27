--[[
	SquadManager.lua  (place in ServerScriptService.NPCAIModule)

	Singleton that manages all NPC squads.

	FIXES (v2):
	  1. BackupThreshold condition was inverted — was `>=` (never called backup
	     for solo squads), now correctly alerts when UNDER threshold.
	  2. Squad grouping now checks ALL existing members for proximity, not just
	     squad[1], so squads grow correctly regardless of spawn order.
	  3. Added PROXIMITY ALERT fallback — alert() notifies ALL nearby NPC brains
	     within BackupRadius regardless of squad membership. Solo-squad NPCs now
	     respond to a fight nearby even if they never grouped.
	  4. Alert refreshes timer on re-sighting instead of ignoring it.
	  5. _allBrains set tracks every registered brain globally for proximity search.
--]]

local RunService = game:GetService("RunService")
local Config     = require(game.ReplicatedStorage.Shared.Config)

local SquadManager = {}
SquadManager.__index = SquadManager

local _squads      = {}  -- squadId → Squad
local _memberIndex = {}  -- brain → Squad
local _allBrains   = {}  -- all registered brains (for proximity-based alerts)

local CFG = Config.Squad

-- ─── Internal helpers ──────────────────────────────────────────────────────

local function newSquad(id)
	return {
		id           = id,
		members      = {},
		leader       = nil,
		sharedTarget = nil,
		alertActive  = false,
		alertTimer   = 0,
	}
end

-- FIX 2: Check ALL squad members for proximity, not just squad[1]
local function squadIdFor(brain)
	local pos      = brain.RootPart.Position
	local bestId   = nil
	local bestDist = math.huge

	for id, squad in pairs(_squads) do
		if #squad.members >= CFG.MaxSquadSize then continue end
		for _, member in ipairs(squad.members) do
			if not member.RootPart then continue end
			local d = (pos - member.RootPart.Position).Magnitude
			if d <= CFG.SquadJoinRadius and d < bestDist then
				bestDist = d
				bestId   = id
			end
		end
	end

	if bestId then return bestId end

	local id = "Squad_" .. tostring(math.random(100000, 999999))
	_squads[id] = newSquad(id)
	return id
end

local function electLeader(squad)
	for _, brain in ipairs(squad.members) do
		if brain.NPC.Parent then
			brain.NPC:SetAttribute("SquadLeader", nil)
		end
	end
	local best, bestHp = nil, -1
	for _, brain in ipairs(squad.members) do
		if not brain.NPC.Parent then continue end
		local hp = brain.Humanoid.MaxHealth
		if hp > bestHp then bestHp = hp; best = brain end
	end
	squad.leader = best
	if best then best.NPC:SetAttribute("SquadLeader", true) end
end

local FORMATION_OFFSETS = {
	Vector3.new( 0, 0, 0), Vector3.new( 4, 0, 0), Vector3.new(-4, 0, 0),
	Vector3.new( 0, 0, 4), Vector3.new( 2, 0,-4), Vector3.new(-2, 0,-4),
	Vector3.new( 6, 0, 2), Vector3.new(-6, 0, 2),
}

local function assignFormationSlots(squad)
	for i, brain in ipairs(squad.members) do
		local offset = FORMATION_OFFSETS[i]
			or Vector3.new(math.random(-8,8), 0, math.random(-8,8))
		brain._squadOffset = offset
		brain.NPC:SetAttribute("FormationSlot", i)
	end
end

-- Core: push an alert into one brain
local function alertBrain(member, target, broadcaster)
	if not member.NPC.Parent then return end
	if member == broadcaster then return end
	if member.TargetSys and target then
		member.TargetSys:UnignorePlayer(target)
		member.TargetSys:RegisterThreat(target, CFG.AlertThreatBoost)
	end
	if member.Personality and member.Personality.OnSquadAlert then
		member.Personality:OnSquadAlert(target, broadcaster)
	end
end

-- ─── Public API ────────────────────────────────────────────────────────────

function SquadManager.register(brain)
	if _memberIndex[brain] then return end

	_allBrains[brain] = true

	local id    = squadIdFor(brain)
	local squad = _squads[id]

	table.insert(squad.members, brain)
	_memberIndex[brain] = squad

	brain.NPC:SetAttribute("SquadId", id)
	brain._squadOffset = Vector3.zero

	assignFormationSlots(squad)
	electLeader(squad)

	print(("[SquadManager] %s joined %s (%d members)"):format(
		brain.NPC.Name, id, #squad.members))
end

function SquadManager.unregister(brain)
	_allBrains[brain] = nil
	local squad = _memberIndex[brain]
	if not squad then return end

	for i, m in ipairs(squad.members) do
		if m == brain then table.remove(squad.members, i); break end
	end

	brain.NPC:SetAttribute("SquadId", nil)
	brain.NPC:SetAttribute("SquadLeader", nil)
	brain.NPC:SetAttribute("FormationSlot", nil)
	_memberIndex[brain] = nil

	if squad.leader == brain then
		squad.leader = nil
		electLeader(squad)
	end

	if #squad.members == 0 then _squads[squad.id] = nil end
end

--[[
	Alert the squad that one member spotted a target.

	Stage 1 — own squad members (always)
	Stage 2 — ALL other registered brains within BackupRadius
	           (FIX 3: catches solo-squad NPCs that spawned too far apart to group)
--]]
function SquadManager.alert(brain, target)
	local squad    = _memberIndex[brain]
	local alertPos = brain.RootPart.Position

	-- Stage 1: own squad
	if squad then
		squad.sharedTarget = target
		squad.alertActive  = true
		squad.alertTimer   = CFG.AlertDuration  -- FIX 4: always refresh

		for _, member in ipairs(squad.members) do
			alertBrain(member, target, brain)
		end
	end

	-- Stage 2: proximity-based backup (FIX 3)
	local backupCount = 0
	local backupCap   = CFG.MaxBackupSquads * CFG.MaxSquadSize

	for otherBrain in pairs(_allBrains) do
		if otherBrain == brain then continue end
		if not otherBrain.RootPart then continue end
		if not otherBrain.NPC.Parent then continue end

		-- Skip if this brain is already in the alerting squad (handled above)
		local otherSquad = _memberIndex[otherBrain]
		if otherSquad and otherSquad == squad then continue end

		local dist = (alertPos - otherBrain.RootPart.Position).Magnitude
		if dist > CFG.BackupRadius then continue end
		if backupCount >= backupCap then break end

		-- Mark the other brain's squad as alerted too
		if otherSquad and not otherSquad.alertActive then
			otherSquad.sharedTarget = target
			otherSquad.alertActive  = true
			otherSquad.alertTimer   = CFG.AlertDuration * 0.75
			print(("[SquadManager] Backup: %s responding"):format(otherSquad.id))
		end

		alertBrain(otherBrain, target, brain)
		backupCount += 1
	end

	print(("[SquadManager] ALERT from %s — target: %s | backup: %d"):format(
		squad and squad.id or brain.NPC.Name,
		tostring(target),
		backupCount))
end

function SquadManager.getSharedTarget(brain)
	local squad = _memberIndex[brain]
	return squad and squad.sharedTarget or nil
end

function SquadManager.isOnAlert(brain)
	local squad = _memberIndex[brain]
	return squad ~= nil and squad.alertActive
end

function SquadManager.getLeader(brain)
	local squad = _memberIndex[brain]
	return squad and squad.leader or nil
end

function SquadManager.getFormationOffset(brain)
	return brain._squadOffset or Vector3.zero
end

function SquadManager.getMemberCount(brain)
	local squad = _memberIndex[brain]
	return squad and #squad.members or 1
end

-- ─── Tick ──────────────────────────────────────────────────────────────────

function SquadManager.update(dt)
	for _, squad in pairs(_squads) do
		if squad.alertActive then
			squad.alertTimer -= dt
			if squad.alertTimer <= 0 then
				squad.alertActive  = false
				squad.sharedTarget = nil
				print(("[SquadManager] %s alert expired"):format(squad.id))
			end
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	SquadManager.update(dt)
end)

return SquadManager