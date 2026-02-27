--[[
	Scared.lua

	Behavior:
	  - Always ignores players for targeting (never chases, never attacks)
	  - Detects players independently via its own proximity checks
	  - If a player enters FleeRadius → ShouldForceFlee() = true
	  - If a player enters HearRange (closer) → panic: random freeze/slow
	  - If attacked → flee immediately regardless of distance
	  - Flee ends only when no player is within FleeRadius AND not attacked
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)
local Players         = game:GetService("Players")

local Scared = setmetatable({}, { __index = PersonalityBase })
Scared.__index = Scared

local CFG = Config.Scared

function Scared.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Scared)
	self.Name             = "Scared"
	self._isFleeing       = false   -- true when a player is too close
	self._isAttacked      = false   -- true when hit, overrides distance check
	self._attackedTimer   = 0
	self._panicTimer      = 0       -- freeze/slow effect timer
	self._currentSpeed    = CFG.PanicSpeed
	self._frozen          = false

	-- Scared NPCs never engage combat, ignore all for TargetSys
	entity.TargetSys:IgnoreAll()

	self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
		entity.TargetSys:IgnorePlayer(player)
	end)

	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Scared:CanEnterCombat(): boolean
	return false  -- never
end

function Scared:ShouldForceFlee(): boolean
	return self._isFleeing or self._isAttacked
end

function Scared:GetFleeSpeed(): number?
	-- Freeze overrides speed to 0, slow reduces it
	if self._frozen then return 0 end
	return self._currentSpeed
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────

function Scared:OnUpdate(dt: number)
	-- ── Attacked timer ────────────────────────────────────────────────────
	if self._isAttacked then
		self._attackedTimer -= dt
		if self._attackedTimer <= 0 then
			self._isAttacked = false
		end
	end

	-- ── Panic effect timer (freeze / slow) ────────────────────────────────
	if self._panicTimer > 0 then
		self._panicTimer -= dt
		if self._panicTimer <= 0 then
			self._frozen       = false
			self._currentSpeed = CFG.PanicSpeed
		end
	end

	-- ── Proximity check — scan for any nearby player ──────────────────────
	-- We do this ourselves because TargetSys ignores all players for Scared
	local root         = self.Entity.RootPart
	local anyInRange   = false
	local anyInPanic   = false

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local pRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not pRoot then continue end

		local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
		if not hum or hum.Health <= 0 then continue end

		local dist = (root.Position - pRoot.Position).Magnitude

		if dist <= CFG.FleeRadius then
			anyInRange = true
		end

		-- Closer range triggers panic effects (freeze/slow)
		if dist <= Config.Detection.HearRange and self._panicTimer <= 0 then
			anyInPanic = true
		end
	end

	self._isFleeing = anyInRange

	-- Trigger a panic effect if a player is very close and no effect active
	if anyInPanic and self._panicTimer <= 0 then
		self:_triggerPanic()
	end

	-- If nothing is making us flee, reset speed to normal
	if not self._isFleeing and not self._isAttacked then
		if not self._frozen then
			self._currentSpeed = CFG.PanicSpeed
		end
	end
end

function Scared:OnDamaged(amount: number, attacker: Player?)
	-- Being hit overrides everything — flee hard
	self._isAttacked    = true
	self._attackedTimer = 5  -- flee for 5s after being hit

	-- Trigger immediate panic effect
	self:_triggerPanic()
end

function Scared:_triggerPanic()
	local roll = math.random()

	if roll < CFG.FreezeChance then
		-- Freeze
		self._frozen       = true
		self._panicTimer   = CFG.FreezeDuration
		self._currentSpeed = 0
	elseif roll < CFG.FreezeChance + CFG.SlowChance then
		-- Slow
		self._frozen       = false
		self._currentSpeed = CFG.PanicSpeed * CFG.SlowMultiplier
		self._panicTimer   = CFG.SlowDuration
	else
		-- Full panic speed
		self._frozen       = false
		self._currentSpeed = CFG.PanicSpeed
	end
end

function Scared:OnStateChanged(newState: string, oldState: string) end
function Scared:OnTargetFound(target: Player) end
function Scared:OnTargetLost() end

function Scared:Destroy()
	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
		self._playerAddedConn = nil
	end
end

return Scared