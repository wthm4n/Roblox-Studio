--[[
	NPC CONTROLLER
	
	Makes NPCs use the SAME combat system as players.
	NPCs get a CombatCore instance just like players.
	
	This handles:
	- AI decision making
	- Target acquisition
	- Attack timing
	- Combo execution
	
	The actual combat mechanics are handled by CombatCore.
]]

local NPCController = {}
NPCController.__index = NPCController

local RunService = game:GetService("RunService")

function NPCController.new(combatInstance, npcConfig)
	local self = setmetatable({}, NPCController)

	self.CombatInstance = combatInstance
	self.Core = combatInstance.Core
	self.Character = combatInstance.Core.Character
	self.Humanoid = combatInstance.Core.Humanoid
	self.HumanoidRootPart = combatInstance.Core.HumanoidRootPart

	-- NPC behavior config
	self.Config = npcConfig
		or {
			AggroRange = 50,
			AttackRange = 8,
			ComboChance = 0.7, -- 70% chance to continue combo
			DashChance = 0.3,
			ReactionTime = 0.2, -- Seconds
		}

	-- AI state
	self.CurrentTarget = nil
	self.LastAttackTime = 0
	self.NextActionTime = 0
	self.IsInCombat = false

	-- Decision making
	self.DecisionTimer = 0
	self.DecisionInterval = 0.1 -- Make decisions every 0.1s

	-- Connections
	self.Connections = {}

	-- Listen to combat events for AI reactions
	self.Connections.ActionEnded = self.Core.Events.ActionEnded.Event:Connect(function(data)
		self:OnActionEnded(data)
	end)

	self.Connections.DamageTaken = self.Core.Events.DamageTaken.Event:Connect(function(data)
		self:OnDamageTaken(data)
	end)

	-- AI update loop
	self.Connections.Heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)

	return self
end

--[[
	MAIN AI UPDATE LOOP
]]
function NPCController:Update(deltaTime: number)
	self.DecisionTimer = self.DecisionTimer + deltaTime

	-- Make decisions at intervals
	if self.DecisionTimer >= self.DecisionInterval then
		self.DecisionTimer = 0
		self:MakeDecision()
	end

	-- Movement AI
	self:UpdateMovement(deltaTime)
end

--[[
	AI DECISION MAKING
]]
function NPCController:MakeDecision()
	-- Find target if we don't have one
	if not self.CurrentTarget or not self.CurrentTarget.Parent then
		self:FindTarget()
	end

	if not self.CurrentTarget then
		self.IsInCombat = false
		return
	end

	-- Check if we can act
	local currentTime = tick()
	if currentTime < self.NextActionTime then
		return -- Still in reaction delay
	end

	-- Calculate distance to target
	local targetHRP = self.CurrentTarget:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		self.CurrentTarget = nil
		return
	end

	local distance = (targetHRP.Position - self.HumanoidRootPart.Position).Magnitude

	-- Decision tree
	if distance <= self.Config.AttackRange then
		-- In attack range
		self:DecideAttack()
	elseif distance <= self.Config.AggroRange then
		-- Chase target
		self.IsInCombat = true
		-- Movement handled in UpdateMovement
	else
		-- Target too far, lose aggro
		self.CurrentTarget = nil
		self.IsInCombat = false
	end
end

function NPCController:DecideAttack()
	-- Check if already attacking
	if self.Core.CurrentAction then
		return
	end

	-- Check if in combo
	if self.Core.ComboCounter > 0 then
		-- Decide whether to continue combo
		if self.Core.InAttackWindow then
			if math.random() < self.Config.ComboChance then
				self:ExecuteM1()
			end
		end
	else
		-- Start new combo
		if self.Core:CanStartNewCombo() then
			self:ExecuteM1()
		end
	end

	-- Randomly use dash
	if math.random() < self.Config.DashChance and not self.Core.CurrentAction then
		self:ExecuteDash()
	end
end

--[[
	ACTION EXECUTION
	NPCs use the same CombatCore:QueueInput as players
]]
function NPCController:ExecuteM1()
	self.Core:QueueInput("M1", {
		ComboIndex = self.Core.ComboCounter + 1,
	})

	self:SetReactionDelay()
end

function NPCController:ExecuteDash()
	-- Random dash direction
	local directions = { "Front", "Back", "Left", "Right" }
	local direction = directions[math.random(1, #directions)]

	self.Core:QueueInput("Dash", {
		Direction = direction,
	})

	self:SetReactionDelay()
end

function NPCController:ExecuteAbility(abilityName: string)
	self.Core:QueueInput("Ability", {
		AbilityName = abilityName,
	})

	self:SetReactionDelay()
end

function NPCController:SetReactionDelay()
	-- Add human-like reaction delay
	local delay = self.Config.ReactionTime + (math.random() * 0.1)
	self.NextActionTime = tick() + delay
end

--[[
	TARGET ACQUISITION
]]
function NPCController:FindTarget()
	local shortestDistance = self.Config.AggroRange
	local closestTarget = nil

	-- Find all players in range
	local players = game.Players:GetPlayers()

	for _, player in ipairs(players) do
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			local hrp = player.Character:FindFirstChild("HumanoidRootPart")

			if humanoid and humanoid.Health > 0 and hrp then
				local distance = (hrp.Position - self.HumanoidRootPart.Position).Magnitude

				if distance < shortestDistance then
					shortestDistance = distance
					closestTarget = player.Character
				end
			end
		end
	end

	self.CurrentTarget = closestTarget
end

--[[
	MOVEMENT AI
]]
function NPCController:UpdateMovement(deltaTime: number)
	if not self.IsInCombat or not self.CurrentTarget then
		-- Idle behavior
		self.Humanoid:MoveTo(self.HumanoidRootPart.Position)
		return
	end

	-- Don't move during actions
	if self.Core.CurrentAction then
		return
	end

	local targetHRP = self.CurrentTarget:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return
	end

	local distance = (targetHRP.Position - self.HumanoidRootPart.Position).Magnitude

	-- Move toward target if too far
	if distance > self.Config.AttackRange then
		self.Humanoid:MoveTo(targetHRP.Position)
	else
		-- In range, stop moving
		self.Humanoid:MoveTo(self.HumanoidRootPart.Position)
	end
end

--[[
	EVENT HANDLERS
]]
function NPCController:OnActionEnded(data)
	-- Action finished, can make new decision soon
end

function NPCController:OnDamageTaken(data)
	-- Took damage, get aggressive
	self.IsInCombat = true

	-- Could set attacker as target
	-- if data.Attacker then
	--     self.CurrentTarget = data.Attacker
	-- end
end

--[[
	PUBLIC API
]]
function NPCController:SetTarget(target: Model)
	self.CurrentTarget = target
	self.IsInCombat = true
end

function NPCController:SetAggroRange(range: number)
	self.Config.AggroRange = range
end

function NPCController:SetAttackRange(range: number)
	self.Config.AttackRange = range
end

function NPCController:Destroy()
	for _, conn in pairs(self.Connections) do
		conn:Disconnect()
	end

	self.CurrentTarget = nil
end

return NPCController
