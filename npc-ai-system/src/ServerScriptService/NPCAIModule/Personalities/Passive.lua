--[[
	Passive.lua

	Behavior:
	  - Patrols and ignores all players by default
	  - ONLY reacts when directly attacked
	  - On attacked: flees from attacker for FLEE_DURATION seconds
	  - Never chases, never attacks back
	  - After flee timer expires: forgets attacker, resumes ignoring everyone
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)
local Players         = game:GetService("Players")

local Passive = setmetatable({}, { __index = PersonalityBase })
Passive.__index = Passive

local CFG           = Config.Passive
local FLEE_DURATION = 6

function Passive.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Passive)
	self.Name        = "Passive"
	self._fleeTimer  = 0
	self._isProvoked = false
	self._attacker   = nil

	-- Ignore everyone at spawn — passive NPCs are completely unaware of players
	entity.TargetSys:IgnoreAll()

	-- Also ignore players who join mid-session
	self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
		if not self._isProvoked then
			entity.TargetSys:IgnorePlayer(player)
		end
	end)

	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Passive:CanEnterCombat(): boolean
	return false  -- never chases or attacks, ever
end

function Passive:ShouldForceFlee(): boolean
	return self._isProvoked
end

function Passive:GetFleeSpeed(): number?
	return CFG.FleeSpeed
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────

function Passive:OnUpdate(dt: number)
	if not self._isProvoked then return end

	self._fleeTimer -= dt
	if self._fleeTimer <= 0 then
		self._isProvoked = false
		self._attacker   = nil

		-- Re-ignore everyone and wipe target so FSM exits Flee cleanly
		self.Entity.TargetSys:IgnoreAll()
		self.Entity.TargetSys:ClearTarget()
	end
end

function Passive:OnDamaged(amount: number, attacker: Player?)
	self._isProvoked = true
	self._fleeTimer  = FLEE_DURATION
	self._attacker   = attacker

	if attacker then
		-- Unignore ONLY the attacker so TargetSys picks them up
		-- This gives _beginFlee a direction to run away from
		self.Entity.TargetSys:UnignorePlayer(attacker)
	end

	-- No Pathfinder call here — Flee state OnEnter calls _beginFlee
end

function Passive:OnStateChanged(newState: string, oldState: string) end
function Passive:OnTargetFound(target: Player) end
function Passive:OnTargetLost() end

function Passive:Destroy()
	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
		self._playerAddedConn = nil
	end
end

return Passive