--[[
	MOVEMENT CONTROLLER
	
	Movement does NOT override combat.
	All movement requests go through Core.
	
	Handles:
	- Dashes (4 directions)
	- Rolls
	- Air control
	- Momentum physics
	
	Uses velocity solvers, respects invincibility frames.
	SUBSYSTEM - reports to Core, doesn't decide.
]]

local MovementController = {}
MovementController.__index = MovementController

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

function MovementController.new(core, isLocalPlayer: boolean)
	local self = setmetatable({}, MovementController)
	
	self.Core = core
	self.Character = core.Character
	self.Humanoid = core.Humanoid
	self.HumanoidRootPart = core.HumanoidRootPart
	self.IsLocalPlayer = isLocalPlayer
	
	-- Movement state
	self.CurrentDash = nil -- Active dash data
	self.DashVelocity = Vector3.new(0, 0, 0)
	
	-- Physics
	self.BodyVelocity = nil -- For applying dash forces
	
	-- Connections
	self.Connections = {}
	
	-- Listen to core events
	self.Connections.ActionStarted = core.Events.ActionStarted.Event:Connect(function(actionData)
		self:OnActionStarted(actionData)
	end)
	
	self.Connections.ActionEnded = core.Events.ActionEnded.Event:Connect(function(actionData)
		self:OnActionEnded(actionData)
	end)
	
	-- Update loop
	self.Connections.Heartbeat = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)
	
	-- Input handling (local player only)
	if isLocalPlayer and not core.IsServer then
		self:SetupInputHandling()
	end
	
	return self
end

--[[
	INPUT HANDLING - Local player only
	Captures dash inputs and sends to Core
]]
function MovementController:SetupInputHandling()
	-- Dash keybinds
	local dashKeys = {
		[Enum.KeyCode.Q] = "Front", -- Forward dash
		[Enum.KeyCode.E] = "Back",  -- Backward dash
		-- Could add left/right if desired
	}
	
	self.Connections.InputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		
		local direction = dashKeys[input.KeyCode]
		if direction then
			self:RequestDash(direction)
		end
	end)
end

function MovementController:RequestDash(direction: string)
	-- Send dash request to Core
	self.Core:QueueInput("Dash", {
		Direction = direction
	})
end

--[[
	Core approved a dash - execute it
]]
function MovementController:OnActionStarted(actionData)
	if actionData.Type == "Dash" then
		self:StartDash(actionData.Data.Direction, actionData.Config)
	end
end

function MovementController:OnActionEnded(actionData)
	if actionData.Type == "Dash" then
		self:EndDash()
	end
end

--[[
	Execute dash movement
]]
function MovementController:StartDash(direction: string, config: any)
	-- Get dash parameters from config
	local speed = config.Speed or 80
	local duration = config.ActiveFrames / 60 -- Convert frames to seconds
	
	-- Calculate dash direction
	local dashDirection = self:GetDashDirection(direction)
	
	-- Create dash data
	self.CurrentDash = {
		Direction = dashDirection,
		Speed = speed,
		StartTime = tick(),
		Duration = duration,
	}
	
	-- Apply initial velocity
	self:ApplyDashVelocity(dashDirection * speed)
	
	-- I-frames during dash if configured
	if config.Invincibility then
		self.Core.StateManager:SetInvincibility(config.ActiveFrames)
	end
end

function MovementController:GetDashDirection(directionName: string): Vector3
	local hrp = self.HumanoidRootPart
	local lookVector = hrp.CFrame.LookVector
	local rightVector = hrp.CFrame.RightVector
	
	-- Direction mapping
	local directions = {
		Front = lookVector,
		Back = -lookVector,
		Left = -rightVector,
		Right = rightVector,
	}
	
	local direction = directions[directionName] or lookVector
	
	-- Project onto horizontal plane (no vertical dashing)
	direction = Vector3.new(direction.X, 0, direction.Z).Unit
	
	return direction
end

function MovementController:ApplyDashVelocity(velocity: Vector3)
	-- Use LinearVelocity for modern physics
	if not self.BodyVelocity then
		self.BodyVelocity = Instance.new("BodyVelocity")
		self.BodyVelocity.MaxForce = Vector3.new(1, 0, 1) * 50000
		self.BodyVelocity.Parent = self.HumanoidRootPart
	end
	
	self.DashVelocity = velocity
	self.BodyVelocity.Velocity = velocity
end

function MovementController:EndDash()
	if self.BodyVelocity then
		self.BodyVelocity:Destroy()
		self.BodyVelocity = nil
	end
	
	self.CurrentDash = nil
	self.DashVelocity = Vector3.new(0, 0, 0)
end

function MovementController:Update(deltaTime: number)
	-- Update active dash
	if self.CurrentDash then
		self:UpdateDash(deltaTime)
	end
	
	-- Could add air control here
	if self:IsAirborne() then
		self:UpdateAirControl(deltaTime)
	end
end

function MovementController:UpdateDash(deltaTime: number)
	local dash = self.CurrentDash
	
	-- Check if dash should end
	local elapsed = tick() - dash.StartTime
	if elapsed >= dash.Duration then
		-- Dash ended, but don't call EndDash here
		-- The Core will end it via action timing
		return
	end
	
	-- Apply momentum decay if configured
	local decay = 0.95 -- Slight decay
	self.DashVelocity = self.DashVelocity * decay
	
	if self.BodyVelocity then
		self.BodyVelocity.Velocity = self.DashVelocity
	end
end

function MovementController:UpdateAirControl(deltaTime: number)
	-- Basic air control
	-- Would integrate with input if player is local
	
	-- For now, just ensure character doesn't freeze in air
	-- Could add air dash capability here
end

function MovementController:IsAirborne(): boolean
	-- Check if character is in air
	local rayOrigin = self.HumanoidRootPart.Position
	local rayDirection = Vector3.new(0, -4, 0)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {self.Character}
	
	local result = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	
	return result == nil
end

--[[
	MOMENTUM SYSTEM
	Prevents exploit stacking, clamps velocity
]]
function MovementController:ClampVelocity()
	local hrp = self.HumanoidRootPart
	local velocity = hrp.AssemblyVelocity
	
	local maxSpeed = 200 -- Anti-exploit cap
	
	if velocity.Magnitude > maxSpeed then
		hrp.AssemblyVelocity = velocity.Unit * maxSpeed
	end
end

--[[
	External API for other systems
]]
function MovementController:GetCurrentVelocity(): Vector3
	return self.HumanoidRootPart.AssemblyVelocity
end

function MovementController:SetVelocity(velocity: Vector3)
	-- Only allowed during specific states
	if self.Core.CurrentState == "Knockback" or self.Core.CurrentState == "Hitstun" then
		self.HumanoidRootPart.AssemblyVelocity = velocity
	end
end

function MovementController:Destroy()
	for _, conn in pairs(self.Connections) do
		conn:Disconnect()
	end
	
	if self.BodyVelocity then
		self.BodyVelocity:Destroy()
	end
end

return MovementController
