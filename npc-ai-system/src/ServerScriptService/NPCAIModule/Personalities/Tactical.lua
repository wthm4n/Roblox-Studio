--[[
	Tactical.lua
	The most advanced personality. Fights smart, not hard.

	Behaviors:
	  - Flanks: approaches at an angle instead of head-on
	  - Finds and uses cover (hides behind parts)
	  - Checks if exposed and ducks back if so
	  - Coordinates with other Tactical NPCs nearby
	    (one suppresses while another flanks)
--]]

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)

local Tactical = setmetatable({}, { __index = PersonalityBase })
Tactical.__index = Tactical

local CFG = Config.Tactical

-- ── Constructor ────────────────────────────────────────────────────────────

function Tactical.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Tactical)
	self.Name            = "Tactical"
	self._role           = "Flanker"   -- "Flanker" or "Suppressor"
	self._inCover        = false
	self._coverPos       = nil
	self._suppressTimer  = 0
	self._flankTimer     = 0
	self._losCheckTimer  = 0
	self._updateTimer    = 0
	self._coordCooldown  = 0
	return self
end

-- ── Interface ──────────────────────────────────────────────────────────────

function Tactical:OnUpdate(dt: number)
	local entity  = self.Entity
	local state   = entity.FSM:GetState()

	self._losCheckTimer  += dt
	self._coordCooldown  -= dt
	self._updateTimer    += dt

	-- ── Coordinate with allies every 3 seconds ────────────────────────────
	if self._coordCooldown <= 0 then
		self._coordCooldown = 3
		self:_coordinateWithAllies()
	end

	if self._updateTimer < 0.15 then return end
	self._updateTimer = 0

	-- Only do tactical stuff when there's a target
	local target = entity.TargetSys.CurrentTarget
	if not target then
		self._inCover = false
		return
	end

	local pRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not pRoot then return end

	-- ── Line-of-sight exposure check ──────────────────────────────────────
	if self._losCheckTimer >= CFG.LoSCheckInterval then
		self._losCheckTimer = 0
		local exposed = entity.TargetSys:HasLineOfSight(pRoot.Position)

		if exposed and self._role == "Suppressor" then
			-- Suppressor: in cover, take pot-shots but don't advance
			self._suppressTimer += CFG.LoSCheckInterval
			if self._suppressTimer >= CFG.SuppressTime then
				-- Suppressed long enough — switch to flanking
				self._role          = "Flanker"
				self._suppressTimer = 0
				self._inCover       = false
			else
				self:_takeCover(pRoot.Position)
				return
			end
		end

		if exposed and self._role == "Flanker" then
			-- Flanker exposed — quickly move to flank position
			local flankPos = self:_getFlankPosition(pRoot.Position)
			if flankPos then
				entity.Pathfinder:MoveTo(flankPos)
			end
		end
	end

	-- ── Range-based behavior ──────────────────────────────────────────────
	local dist = (entity.RootPart.Position - pRoot.Position).Magnitude

	if dist <= Config.Combat.AttackRange then
		-- Close enough — attack
		if state ~= "Attack" then
			entity.FSM:Transition("Attack")
		end
	elseif dist <= CFG.FlankDistance * 1.5 then
		-- Mid range — flank or suppress based on role
		if self._role == "Flanker" then
			local flankPos = self:_getFlankPosition(pRoot.Position)
			if flankPos then
				entity.Pathfinder:MoveTo(flankPos)
			end
		else
			self:_takeCover(pRoot.Position)
		end
	else
		-- Far — advance while using cover
		if state ~= "Chase" then
			entity.FSM:Transition("Chase")
		end
	end
end

function Tactical:OnTargetFound(player: Player)
	-- On detection, immediately coordinate role assignment
	self._coordCooldown = 0
end

function Tactical:OnDamaged(amount: number, attacker: Player?)
	-- Getting shot — duck into cover immediately
	self._inCover = false
	local target  = self.Entity.TargetSys.CurrentTarget
	if target and target.Character then
		local root = target.Character:FindFirstChild("HumanoidRootPart") :: BasePart
		if root then
			self:_takeCover(root.Position)
		end
	end
end

-- ── Private ────────────────────────────────────────────────────────────────

-- Get a flanking position: off to the side of the player
function Tactical:_getFlankPosition(targetPos: Vector3): Vector3?
	local from      = self.Entity.RootPart.Position
	local toTarget  = (targetPos - from)
	toTarget        = Vector3.new(toTarget.X, 0, toTarget.Z).Unit

	-- Rotate 90 degrees (left or right, alternating)
	local angle  = math.rad(CFG.FlankAngle * (math.random() > 0.5 and 1 or -1))
	local cosA, sinA = math.cos(angle), math.sin(angle)
	local flankDir = Vector3.new(
		toTarget.X * cosA - toTarget.Z * sinA,
		0,
		toTarget.X * sinA + toTarget.Z * cosA
	).Unit

	return targetPos + flankDir * CFG.FlankDistance
end

-- Find nearest cover part and move behind it relative to threat
function Tactical:_takeCover(threatPos: Vector3)
	if self._inCover then return end

	local from      = self.Entity.RootPart.Position
	local bestPos   = nil
	local bestDist  = math.huge

	for _, part in ipairs(workspace:GetDescendants()) do
		if not part:IsA("BasePart") then continue end
		if not part.Anchored then continue end
		if part.Size.Y < CFG.CoverMinHeight then continue end

		local d = (from - part.Position).Magnitude
		if d > CFG.CoverSearchRadius or d > bestDist then continue end

		-- Cover position = behind the part relative to threat
		local awayFromThreat = (part.Position - threatPos).Unit
		local coverPos = part.Position + awayFromThreat * (part.Size.X * 0.5 + 2.5)
		coverPos = Vector3.new(coverPos.X, from.Y, coverPos.Z)

		bestDist = d
		bestPos  = coverPos
	end

	if bestPos then
		self._inCover  = true
		self._coverPos = bestPos
		self.Entity.Pathfinder:MoveTo(bestPos, function()
			-- Arrived at cover — stay here briefly
			task.delay(1.5, function()
				self._inCover = false
			end)
		end)
	end
end

-- Coordinate roles with nearby Tactical NPCs
function Tactical:_coordinateWithAllies()
	local entity   = self.Entity
	local from     = entity.RootPart.Position
	local allies   = {}
	local hasSupp  = false

	for _, model in ipairs(workspace:GetDescendants()) do
		if not model:IsA("Model") then continue end
		if model == entity.NPC then continue end
		if model:GetAttribute("Personality") ~= "Tactical" then continue end

		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		if not root then continue end
		if (from - root.Position).Magnitude > CFG.CoordRadius then continue end

		table.insert(allies, model)

		local role = model:GetAttribute("TacticalRole")
		if role == "Suppressor" then hasSupp = true end
	end

	-- If no suppressor exists among allies, become one
	if not hasSupp and #allies > 0 then
		self._role = "Suppressor"
		entity.NPC:SetAttribute("TacticalRole", "Suppressor")
	else
		self._role = "Flanker"
		entity.NPC:SetAttribute("TacticalRole", "Flanker")
	end
end

function Tactical:Destroy()
	self.Entity.NPC:SetAttribute("TacticalRole", nil)
end

return Tactical
