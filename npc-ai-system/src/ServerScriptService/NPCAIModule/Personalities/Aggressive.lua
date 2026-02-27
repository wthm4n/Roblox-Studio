--[[
	Aggressive.lua
	A relentless hunter. Smarter, faster, nastier than base Chase.

	Behaviors:
	  - Hunts player beyond normal sight range
	  - Predicts player movement and paths to where they WILL be
	  - Combo attack system (rapid multi-hit)
	  - Retreats when low HP, then re-engages when partially recovered
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Aggressive = setmetatable({}, { __index = PersonalityBase })
Aggressive.__index = Aggressive

local CFG = Config.Aggressive

-- ── Constructor ────────────────────────────────────────────────────────────

function Aggressive.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Aggressive)
	self.Name            = "Aggressive"
	self._comboCount     = 0
	self._comboTimer     = 0
	self._retreating     = false
	self._retreatTimer   = 0
	self._updateTimer    = 0
	self._playerVelHist  = {}  -- ring buffer of last player positions for prediction
	self._velHistSize    = CFG.PredictSteps
	return self
end

-- ── Interface ──────────────────────────────────────────────────────────────

function Aggressive:OnUpdate(dt: number)
	local entity  = self.Entity
	local hum     = entity.Humanoid
	local hpRatio = hum.Health / hum.MaxHealth

	-- ── Retreat logic ─────────────────────────────────────────────────────
	if self._retreating then
		self._retreatTimer -= dt
		if hpRatio >= CFG.RetreatingHP + 0.15 or self._retreatTimer <= 0 then
			-- Recovered enough — re-engage
			self._retreating = false
			hum.WalkSpeed = CFG.ChaseSpeed
			entity.FSM:Transition("Chase")
		end
		return
	end

	if hpRatio <= CFG.RetreatingHP and entity.FSM:GetState() ~= "Flee" then
		self._retreating   = true
		self._retreatTimer = 5  -- retreat for up to 5 seconds
		hum.WalkSpeed = Config.Movement.FleeSpeed
		entity.FSM:Transition("Flee")
		return
	end

	-- ── Override chase speed ──────────────────────────────────────────────
	if entity.FSM:GetState() == "Chase" then
		hum.WalkSpeed = CFG.ChaseSpeed
	end

	self._updateTimer += dt
	if self._updateTimer < 0.1 then return end
	self._updateTimer = 0

	-- ── Combo attack management ───────────────────────────────────────────
	if entity.FSM:GetState() == "Attack" then
		self._comboTimer -= 0.1
		if self._comboTimer <= 0 and self._comboCount < CFG.ComboCount then
			self._comboCount += 1
			self._comboTimer  = CFG.ComboWindow
			self:_doComboHit()
		elseif self._comboCount >= CFG.ComboCount then
			-- Combo finished — reset and wait for cooldown
			self._comboCount = 0
		end
	else
		self._comboCount = 0
	end

	-- ── Predictive targeting ──────────────────────────────────────────────
	local target = entity.TargetSys.CurrentTarget
	if target and target.Character then
		local pRoot = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if pRoot then
			self:_recordPlayerPos(pRoot.Position)
			local predicted = self:_predictPlayerPos()
			if predicted and entity.FSM:GetState() == "Chase" then
				-- Path to predicted position instead of current position
				entity.Pathfinder:MoveTo(predicted)
			end
		end
	end
end

function Aggressive:OnTargetFound(player: Player)
	-- Boost speed immediately on target acquisition
	self.Entity.Humanoid.WalkSpeed = CFG.ChaseSpeed
end

function Aggressive:OnDamaged(amount: number, attacker: Player?)
	-- Getting hit makes it MORE aggressive — increase threat
	if attacker then
		self.Entity.TargetSys:RegisterThreat(attacker, amount * 3)
	end
end

-- ── Private ────────────────────────────────────────────────────────────────

function Aggressive:_recordPlayerPos(pos: Vector3)
	table.insert(self._playerVelHist, pos)
	if #self._playerVelHist > self._velHistSize then
		table.remove(self._playerVelHist, 1)
	end
end

-- Linear extrapolation: where will the player be in ~PredictSteps frames?
function Aggressive:_predictPlayerPos(): Vector3?
	local hist = self._playerVelHist
	if #hist < 3 then return nil end

	local newest = hist[#hist]
	local older  = hist[math.max(1, #hist - 3)]
	local vel    = (newest - older) / 3  -- average velocity per sample

	-- Project forward
	return newest + vel * (self._velHistSize * 0.5)
end

function Aggressive:_doComboHit()
	local entity = self.Entity
	local target = entity.TargetSys.CurrentTarget
	if not target or not target.Character then return end

	local hum = target.Character:FindFirstChildOfClass("Humanoid") :: Humanoid
	if not hum or hum.Health <= 0 then return end

	-- Combo hits do reduced damage per hit
	local comboDmg = Config.Combat.Damage * 0.6
	hum:TakeDamage(comboDmg)
	entity.Anim:PlayAction("Attack")
end

function Aggressive:Destroy()
	self._playerVelHist = {}
end

return Aggressive
