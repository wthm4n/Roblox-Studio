--[[
	SquadManager.lua  (place in ServerScriptService.NPCAIModule)
	
	Singleton that manages all NPC squads.
	
	Responsibilities:
	  • Assigns NPCs to squads based on proximity at spawn
	  • Elects a Squad Leader (highest HP, or first registered)
	  • Broadcasts ALERT when any member spots a player
	  • Tracks a shared target per squad
	  • Issues formation offsets so NPCs don't stack
	  • Handles "Call for Backup" — merges nearby idle squads into an alert
	
	Architecture:
	  NPCController.new() calls SquadManager.register(brain)
	  NPCController.Destroy() calls SquadManager.unregister(brain)
	  Personality:OnTargetFound() calls SquadManager.alert(brain, target)
	
	Squads are purely server-side data — no RemoteEvents needed.
--]]

local RunService = game:GetService("RunService")
local Config     = require(game.ReplicatedStorage.Shared.Config)

-- ─── Singleton ─────────────────────────────────────────────────────────────

local SquadManager = {}
SquadManager.__index = SquadManager

-- Internal state
local _squads      : { [string]: Squad } = {}   -- squadId → Squad
local _memberIndex : { [any]: Squad }    = {}   -- brain → Squad

-- ─── Types ─────────────────────────────────────────────────────────────────

--[[
	Squad = {
	  id          : string,
	  members     : { brain },
	  leader      : brain?,
	  sharedTarget: Player?,
	  alertActive : boolean,
	  alertTimer  : number,
	}
--]]
type Squad = {
	id           : string,
	members      : { any },
	leader       : any?,
	sharedTarget : any?,
	alertActive  : boolean,
	alertTimer   : number,
}

-- ─── Config shorthand ──────────────────────────────────────────────────────

local CFG = Config.Squad

-- ─── Internal helpers ──────────────────────────────────────────────────────

local function newSquad(id: string): Squad
	return {
		id           = id,
		members      = {},
		leader       = nil,
		sharedTarget = nil,
		alertActive  = false,
		alertTimer   = 0,
	}
end

local function squadIdFor(brain: any): string
	-- Assign to nearest squad within join radius, otherwise make new one
	local pos = brain.RootPart.Position

	for id, squad in pairs(_squads) do
		if #squad.members >= CFG.MaxSquadSize then continue end
		-- Use first member as anchor
		local anchor = squad.members[1]
		if not anchor then continue end
		local anchorPos = anchor.RootPart.Position
		if (pos - anchorPos).Magnitude <= CFG.SquadJoinRadius then
			return id
		end
	end

	-- New squad
	local id = "Squad_" .. tostring(math.random(100000, 999999))
	_squads[id] = newSquad(id)
	return id
end

local function electLeader(squad: Squad)
	local best     = nil
	local bestHp   = -1
	for _, brain in ipairs(squad.members) do
		if not brain.NPC.Parent then continue end
		local hp = brain.Humanoid.MaxHealth
		if hp > bestHp then
			bestHp = hp
			best   = brain
		end
	end
	squad.leader = best
	if best then
		best.NPC:SetAttribute("SquadLeader", true)
	end
end

local function removeMemberFromSquad(squad: Squad, brain: any)
	for i, m in ipairs(squad.members) do
		if m == brain then
			table.remove(squad.members, i)
			break
		end
	end
	brain.NPC:SetAttribute("SquadId", nil)
	brain.NPC:SetAttribute("SquadLeader", nil)
	brain.NPC:SetAttribute("FormationSlot", nil)
	_memberIndex[brain] = nil

	-- Re-elect leader if the leader left
	if squad.leader == brain then
		squad.leader = nil
		electLeader(squad)
	end

	-- Disband empty squads
	if #squad.members == 0 then
		_squads[squad.id] = nil
	end
end

-- Assign unique formation slot offsets so NPCs spread out
local FORMATION_OFFSETS = {
	Vector3.new(  0,  0,  0),
	Vector3.new(  4,  0,  0),
	Vector3.new( -4,  0,  0),
	Vector3.new(  0,  0,  4),
	Vector3.new(  2,  0, -4),
	Vector3.new( -2,  0, -4),
	Vector3.new(  6,  0,  2),
	Vector3.new( -6,  0,  2),
}

local function assignFormationSlots(squad: Squad)
	for i, brain in ipairs(squad.members) do
		local offset = FORMATION_OFFSETS[i] or Vector3.new(
			math.random(-8, 8), 0, math.random(-8, 8)
		)
		brain._squadOffset   = offset
		brain.NPC:SetAttribute("FormationSlot", i)
	end
end

-- ─── Public API ────────────────────────────────────────────────────────────

-- Register a new NPC brain into a squad
function SquadManager.register(brain: any)
	if _memberIndex[brain] then return end  -- already registered

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

-- Unregister when NPC dies / is removed
function SquadManager.unregister(brain: any)
	local squad = _memberIndex[brain]
	if not squad then return end
	removeMemberFromSquad(squad, brain)
end

--[[
	Alert the squad that one member has spotted a target.
	All members switch to Hunt mode (their personality must handle this).
	Also calls for backup from nearby squads if outnumbered.
--]]
function SquadManager.alert(brain: any, target: any)
	local squad = _memberIndex[brain]
	if not squad then return end

	squad.sharedTarget = target
	squad.alertActive  = true
	squad.alertTimer   = CFG.AlertDuration

	-- Broadcast to all squad members
	for _, member in ipairs(squad.members) do
		if member == brain then continue end
		if not member.NPC.Parent then continue end

		-- Force the member's target system to register the threat
		-- and unignore if needed, then let the personality react
		if member.TargetSys and target then
			member.TargetSys:UnignorePlayer(target)
			member.TargetSys:RegisterThreat(target, CFG.AlertThreatBoost)
		end

		-- Notify the personality
		if member.Personality and member.Personality.OnSquadAlert then
			member.Personality:OnSquadAlert(target, brain)
		end
	end

	-- Call for backup from nearby squads
	SquadManager._callForBackup(squad, target)

	print(("[SquadManager] %s ALERT — target: %s"):format(squad.id, tostring(target)))
end

-- Return the shared target for a brain's squad (nil if no alert)
function SquadManager.getSharedTarget(brain: any): any?
	local squad = _memberIndex[brain]
	return squad and squad.sharedTarget or nil
end

-- Return whether the squad is currently on alert
function SquadManager.isOnAlert(brain: any): boolean
	local squad = _memberIndex[brain]
	return squad ~= nil and squad.alertActive
end

-- Return the leader for a brain's squad
function SquadManager.getLeader(brain: any): any?
	local squad = _memberIndex[brain]
	return squad and squad.leader or nil
end

-- Return this brain's formation offset
function SquadManager.getFormationOffset(brain: any): Vector3
	return brain._squadOffset or Vector3.zero
end

-- Return squad member count
function SquadManager.getMemberCount(brain: any): number
	local squad = _memberIndex[brain]
	return squad and #squad.members or 1
end

-- Tick — decay alert timers
function SquadManager.update(dt: number)
	for _, squad in pairs(_squads) do
		if squad.alertActive then
			squad.alertTimer -= dt
			if squad.alertTimer <= 0 then
				squad.alertActive  = false
				squad.sharedTarget = nil
				print(("[SquadManager] %s alert expired — returning to patrol"):format(squad.id))
			end
		end
	end
end

-- ─── Private: backup logic ─────────────────────────────────────────────────

function SquadManager._callForBackup(alertedSquad: Squad, target: any)
	if #alertedSquad.members >= CFG.BackupThreshold then return end  -- already have enough
	
	local anchorBrain = alertedSquad.members[1]
	if not anchorBrain then return end
	local anchorPos = anchorBrain.RootPart.Position

	local backupRequested = 0

	for id, squad in pairs(_squads) do
		if squad == alertedSquad then continue end
		if squad.alertActive then continue end  -- already engaged
		if backupRequested >= CFG.MaxBackupSquads then break end

		local squadAnchor = squad.members[1]
		if not squadAnchor then continue end
		local squadPos = squadAnchor.RootPart.Position

		if (anchorPos - squadPos).Magnitude <= CFG.BackupRadius then
			-- Alert this nearby squad too
			squad.sharedTarget = target
			squad.alertActive  = true
			squad.alertTimer   = CFG.AlertDuration * 0.7  -- shorter secondary alert

			for _, member in ipairs(squad.members) do
				if not member.NPC.Parent then continue end
				if member.TargetSys and target then
					member.TargetSys:UnignorePlayer(target)
					member.TargetSys:RegisterThreat(target, CFG.AlertThreatBoost * 0.5)
				end
				if member.Personality and member.Personality.OnSquadAlert then
					member.Personality:OnSquadAlert(target, anchorBrain)
				end
			end

			backupRequested += 1
			print(("[SquadManager] Backup called — %s joining %s"):format(id, alertedSquad.id))
		end
	end
end

-- ─── Hook into RunService for alert decay ──────────────────────────────────

RunService.Heartbeat:Connect(function(dt)
	SquadManager.update(dt)
end)

return SquadManager