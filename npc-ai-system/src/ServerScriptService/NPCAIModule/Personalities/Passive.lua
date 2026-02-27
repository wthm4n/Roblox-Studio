--[[
	Passive.lua

	Behavior:
	  - Patrols and completely ignores all players by default
	  - ONLY reacts when directly attacked (OnDamaged fires)
	  - On attacked: flees from attacker for FLEE_DURATION seconds
	  - Never chases, never attacks back (CanEnterCombat always false)
	  - After flee timer: re-ignores everyone, clears threat table, back to patrol

	Why IgnoreAll at spawn:
	  TargetSys._selectBestTarget iterates ALL players and picks nearest.
	  If a player is in the ignore list they are skipped entirely.
	  This means CurrentTarget stays nil → Idle/Patrol never see a target
	  → Chase/Attack are never triggered from States.lua.

	Why we only UnignorePlayer the attacker:
	  _beginFlee needs a direction. It reads TargetSys.CurrentTarget to
	  know which way to run. So we briefly unignore just the attacker so
	  TargetSys picks them up, giving _beginFlee a flee direction.
	  Everyone else stays ignored.

	Why we RegisterThreat for the attacker:
	  TargetSys._selectBestTarget also uses threat priority. By registering
	  threat for the attacker we guarantee they become CurrentTarget (not
	  some random other player who happens to be closer).
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

	-- Ignore everyone at spawn
	entity.TargetSys:IgnoreAll()

	-- Ignore players who join mid-session while not provoked
	self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
		if not self._isProvoked then
			entity.TargetSys:IgnorePlayer(player)
		end
	end)

	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Passive:CanEnterCombat(): boolean
	return false  -- never, under any circumstances
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

		-- Wipe the threat table so the attacker is no longer tracked
		-- then re-ignore everyone so TargetSys goes blind again
		self.Entity.TargetSys:ClearThreat()
		self.Entity.TargetSys:IgnoreAll()
		self.Entity.TargetSys:ClearTarget()
	end
end

function Passive:OnDamaged(amount: number, attacker: Player?)
	self._isProvoked = true
	self._fleeTimer  = FLEE_DURATION
	self._attacker   = attacker

	if attacker then
		-- Unignore ONLY the attacker and register their threat so they
		-- become CurrentTarget — this gives _beginFlee a flee direction
		self.Entity.TargetSys:UnignorePlayer(attacker)
		self.Entity.TargetSys:RegisterThreat(attacker, amount)
	end
	-- No Pathfinder call here — Flee.OnEnter calls _beginFlee
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