-- Passive.lua (Calm → Aggressive → Flee on Low HP)

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)
local Players         = game:GetService("Players")

local Passive = setmetatable({}, { __index = PersonalityBase })
Passive.__index = Passive

local CFG = Config.Passive

function Passive.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Passive)

	self.Name            = "Passive"
	self._provoked       = false
	self._retreating     = false
	self._retreatTimer   = 0

	-- Ignore all players initially
	entity.TargetSys:IgnoreAll()

	self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
		if not self._provoked then
			entity.TargetSys:IgnorePlayer(player)
		end
	end)

	return self
end

-- ─────────────────────────────────────────────────────────────

function Passive:CanEnterCombat(): boolean
	return self._provoked and not self._retreating
end

function Passive:ShouldForceFlee(): boolean
	return self._retreating
end

function Passive:GetFleeSpeed(): number?
	return CFG.FleeSpeed
end

-- ─────────────────────────────────────────────────────────────

function Passive:OnUpdate(dt: number)
	local entity  = self.Entity
	local hum     = entity.Humanoid
	local hpRatio = hum.Health / hum.MaxHealth

	-- If currently retreating
	if self._retreating then
		self._retreatTimer -= dt

		-- Recover condition
		if hpRatio >= CFG.RetreatingHP + 0.2 or self._retreatTimer <= 0 then
			self._retreating = false
			self._provoked   = false

			entity.TargetSys:ClearThreat()
			entity.TargetSys:IgnoreAll()
			entity.TargetSys:ClearTarget()
		end

		return
	end

	-- Enter retreat mode if low HP
	if self._provoked and hpRatio <= CFG.RetreatingHP then
		self._retreating   = true
		self._retreatTimer = 5
	end
end

-- ─────────────────────────────────────────────────────────────

function Passive:OnDamaged(amount: number, attacker: Player?)
	if not attacker then return end

	self._provoked = true
	self._retreating = false

	-- Allow targeting system to work now
	self.Entity.TargetSys:UnignorePlayer(attacker)
	self.Entity.TargetSys:RegisterThreat(attacker, amount * 2)
end

-- ─────────────────────────────────────────────────────────────

function Passive:Destroy()
	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
		self._playerAddedConn = nil
	end
end

return Passive