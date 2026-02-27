-- Scared.lua (Pure Flee Version)

local PersonalityBase = require(script.Parent.PersonalityBase)
local Config          = require(game.ReplicatedStorage.Shared.Config)
local Players         = game:GetService("Players")

local Scared = setmetatable({}, { __index = PersonalityBase })
Scared.__index = Scared

local CFG = Config.Scared

function Scared.new(entity: any)
	local self = setmetatable(PersonalityBase.new(entity, CFG), Scared)

	self.Name           = "Scared"
	self._isFleeing     = false
	self._nearestThreat = nil

	entity.TargetSys:IgnoreAll()

	self._playerAddedConn = Players.PlayerAdded:Connect(function(player)
		entity.TargetSys:IgnorePlayer(player)
	end)

	return self
end

-- Never enters combat
function Scared:CanEnterCombat(): boolean
	return false
end

function Scared:ShouldForceFlee(): boolean
	return self._isFleeing
end

function Scared:GetFleeSpeed(): number?
	return CFG.PanicSpeed
end

-- Main Update
function Scared:OnUpdate(dt: number)
	local root = self.Entity.RootPart

	local nearestDist = math.huge
	local nearestPos  = nil

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local pRoot = char and char:FindFirstChild("HumanoidRootPart") :: BasePart
		if not pRoot then continue end

		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local dist = (root.Position - pRoot.Position).Magnitude
		if dist < CFG.FleeRadius and dist < nearestDist then
			nearestDist = dist
			nearestPos  = pRoot.Position
		end
	end

	self._nearestThreat = nearestPos
	self._isFleeing     = nearestPos ~= nil

	if self._isFleeing then
		self:_runAway()
	end
end

function Scared:_runAway()
	local entity = self.Entity
	local root   = entity.RootPart
	local threat = self._nearestThreat

	if not threat then return end

	local awayDir = (root.Position - threat).Unit
	awayDir = Vector3.new(awayDir.X, 0, awayDir.Z)

	if awayDir.Magnitude < 0.01 then
		awayDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
	else
		awayDir = awayDir.Unit
	end

	local dest = root.Position + awayDir * Config.Patrol.WanderRadius
	entity.Pathfinder:MoveTo(dest)
end

function Scared:OnDamaged(amount: number, attacker: Player?)
	-- Still just runs, no special logic
	if attacker and attacker.Character then
		local pRoot = attacker.Character:FindFirstChild("HumanoidRootPart")
		if pRoot then
			self._nearestThreat = pRoot.Position
			self._isFleeing = true
			self:_runAway()
		end
	end
end

function Scared:Destroy()
	if self._playerAddedConn then
		self._playerAddedConn:Disconnect()
	end
end

return Scared