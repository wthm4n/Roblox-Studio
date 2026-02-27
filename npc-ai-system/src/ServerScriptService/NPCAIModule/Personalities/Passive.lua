--[[
	Passive.lua

	Hysteresis fix: ShouldForceFlee() uses two thresholds.
	  Enter flee: player <= FleeRadius
	  Exit flee:  player > FleeRadius + 10
	Prevents Flee<->Idle oscillation when player is on the edge of the radius.
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Passive = setmetatable({}, { __index = PersonalityBase })
Passive.__index = Passive

local CFG = Config.Passive

function Passive.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Passive)
	self.Name            = "Passive"
	self._hiding         = false
	self._hideTimer      = 0
	self._alerted        = false
	self._updateTimer    = 0
	self._nearestPlayer  = nil
	self._nearestDist    = math.huge
	self._isThreatActive = false  -- hysteresis flag
	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Passive:CanEnterCombat(): boolean
	return false
end

function Passive:ShouldForceFlee(): boolean
	if self._nearestPlayer then
		if not self._isThreatActive and self._nearestDist <= CFG.FleeRadius then
			self._isThreatActive = true
		elseif self._isThreatActive and self._nearestDist > CFG.FleeRadius + 10 then
			self._isThreatActive = false
		end
	else
		self._isThreatActive = false
	end
	return self._isThreatActive
end

function Passive:GetFleeSpeed(): number?
	return CFG.FleeSpeed
end

-- ── Internal update ────────────────────────────────────────────────────────

function Passive:OnUpdate(dt: number)
	self._updateTimer += dt
	if self._updateTimer < 0.2 then return end
	self._updateTimer = 0

	local entity = self.Entity

	-- Tick hide timer
	if self._hiding then
		self._hideTimer += 0.2
		if self._hideTimer >= CFG.HideDuration then
			self._hiding    = false
			self._hideTimer = 0
		end
		return
	end

	self._nearestPlayer, self._nearestDist = self:_scanNearestPlayer()

	if self._isThreatActive and self._nearestPlayer then
		if not self._alerted then
			self._alerted = true
			self:_alertAllies(entity.RootPart.Position, self._nearestPlayer)
		end

		if not self._hiding then
			local coverPos = self:_findCover(entity.RootPart.Position, self._nearestPlayer)
			if coverPos then
				self._hiding    = true
				self._hideTimer = 0
				entity.Humanoid.WalkSpeed = CFG.FleeSpeed
				entity.Pathfinder:MoveTo(coverPos, function()
					entity.Pathfinder:Stop()
				end)
			end
		end
	else
		self._alerted = false
		entity.Humanoid.WalkSpeed = Config.Movement.WalkSpeed
	end
end

function Passive:OnDamaged(amount: number, attacker: Player?)
	if attacker then
		self._nearestPlayer  = attacker
		self._isThreatActive = true  -- getting hit always activates threat
		local pRoot = attacker.Character and attacker.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		self._nearestDist = pRoot and (self.Entity.RootPart.Position - pRoot.Position).Magnitude or 0
	end
end

-- ── Private ────────────────────────────────────────────────────────────────

function Passive:_scanNearestPlayer(): (Player?, number)
	local Players  = game:GetService("Players")
	local nearest  = nil
	local nearDist = math.huge
	local from     = self.Entity.RootPart.Position
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			local d = (from - root.Position).Magnitude
			if d < nearDist then nearDist = d; nearest = p end
		end
	end
	return nearest, nearDist
end

function Passive:_findCover(from: Vector3, player: Player): Vector3?
	local pChar = player.Character
	local pRoot = pChar and pChar:FindFirstChild("HumanoidRootPart") :: BasePart
	if not pRoot then return nil end

	local toPlayer  = (pRoot.Position - from).Unit
	local bestPos   = nil
	local bestScore = -math.huge

	for _, part in ipairs(workspace:GetDescendants()) do
		if not part:IsA("BasePart") then continue end
		if not part.Anchored then continue end
		if part.Size.Y < 3 then continue end
		local d = (from - part.Position).Magnitude
		if d > CFG.HideSearchRadius then continue end

		local toPartDir      = (part.Position - from).Unit
		local dot            = toPlayer:Dot(toPartDir)
		local awayFromPlayer = (part.Position - pRoot.Position).Unit
		local hidePos        = part.Position + awayFromPlayer * (part.Size.X * 0.5 + 3)
		hidePos = Vector3.new(hidePos.X, from.Y, hidePos.Z)

		local score = -dot + (1 / (d + 1))
		if score > bestScore then
			bestScore = score
			bestPos   = hidePos
		end
	end
	return bestPos
end

function Passive:_alertAllies(from: Vector3, threat: Player)
	for _, model in ipairs(workspace:GetDescendants()) do
		if not model:IsA("Model") then continue end
		if model == self.Entity.NPC then continue end
		if not model:GetAttribute("IsNPC") then continue end
		if model:GetAttribute("Personality") ~= "Passive" then continue end
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		if not root then continue end
		if (from - root.Position).Magnitude <= CFG.AllyAlertRadius then
			model:SetAttribute("AlertedBy", threat.Name)
			task.delay(0.5, function() model:SetAttribute("AlertedBy", nil) end)
		end
	end
end

function Passive:Destroy() end

return Passive