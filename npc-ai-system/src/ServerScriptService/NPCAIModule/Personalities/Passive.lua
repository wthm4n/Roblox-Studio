--[[
	Passive.lua

	Clean architecture: NO FSM:Transition calls anywhere in this file.
	Passive only manages hiding/alerting logic and answers questions
	that States.lua uses to decide transitions.
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Passive = setmetatable({}, { __index = PersonalityBase })
Passive.__index = Passive

local CFG = Config.Passive

function Passive.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Passive)
	self.Name         = "Passive"
	self._hiding      = false
	self._hideTimer   = 0
	self._alerted     = false
	self._updateTimer = 0
	self._nearestPlayer = nil
	self._nearestDist   = math.huge
	return self
end

-- ── Questions States.lua asks ──────────────────────────────────────────────

function Passive:CanEnterCombat(): boolean
	return false
end

function Passive:ShouldForceFlee(): boolean
	return self._nearestPlayer ~= nil and self._nearestDist <= CFG.FleeRadius
end

function Passive:GetFleeSpeed(): number?
	return CFG.FleeSpeed
end

-- ── Internal update — manages hide/alert logic ────────────────────────────
-- Does NOT call FSM:Transition. States.lua handles that.

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

	-- Scan for nearest player
	self._nearestPlayer, self._nearestDist = self:_scanNearestPlayer()

	if self._nearestPlayer and self._nearestDist <= CFG.FleeRadius then
		-- Alert nearby passive allies
		if not self._alerted then
			self._alerted = true
			self:_alertAllies(entity.RootPart.Position, self._nearestPlayer)
		end

		-- Try to hide behind cover, otherwise flee movement is handled by States
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
	-- Record attacker as nearest threat so ShouldForceFlee triggers
	if attacker then
		self._nearestPlayer = attacker
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