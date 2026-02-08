--[[
	MovementClient.lua - SIMPLE VERSION
	
	- Walk/Run with Ctrl key
	- Wall run (horizontal only, no up/down)
	- Dash (W/A/S/D)
	- Double jump
	- Slide
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera

local SETTINGS = require(ReplicatedStorage.Modules.Movement:WaitForChild("MovementSettings"))

-- ========================================
-- SETUP REMOTES
-- ========================================

local RemoteFolder = ReplicatedStorage:FindFirstChild("MovementRemotes")
if not RemoteFolder then
	RemoteFolder = Instance.new("Folder")
	RemoteFolder.Name = "MovementRemotes"
	RemoteFolder.Parent = ReplicatedStorage
end

local function GetOrCreateRemote(name: string, class: string)
	local remote = RemoteFolder:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = RemoteFolder
	end
	return remote
end

local MovementEvent = GetOrCreateRemote("MovementUpdate", "RemoteEvent")
local DashEvent = GetOrCreateRemote("Dash", "RemoteEvent")

-- ========================================
-- STATE
-- ========================================

local state = {
	isRunning = false, -- Ctrl key held
	isDashing = false,
	isSliding = false,
	hasDoubleJump = true,

	wallRun = {
		active = false,
		side = nil,
		normal = nil,
		part = nil,
		bodyVel = nil,
		lastEndTime = 0, -- Track when wall run ended
	},

	lastDash = 0,
	lastSlide = 0,

	currentAnim = "Idle",
}

local animations = {}
local animator = nil
local activeVelocity = nil
local keysPressed = { W = false, A = false, S = false, D = false }

-- ========================================
-- ANIMATION SYSTEM
-- ========================================

local function LoadAnimations()
	animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local function SafeLoad(name: string, id: string)
		if not id or id == "" or not string.match(id, "%d") then
			warn("⚠️ Invalid animation ID for " .. name)
			return nil
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = id
		return animator:LoadAnimation(anim)
	end

	for animName, animId in pairs(SETTINGS.Animations) do
		animations[animName] = SafeLoad(animName, animId)
	end

	print("✅ Loaded animations")
end

local function PlayAnimation(animName: string)
	if state.currentAnim == animName then
		return
	end

	if state.currentAnim and animations[state.currentAnim] then
		local track = animations[state.currentAnim]
		if track and track.IsPlaying then
			track:Stop(0.1)
		end
	end

	state.currentAnim = animName
	local track = animations[animName]
	if track then
		track:Play(0.1)
	end
end

LoadAnimations()

-- ========================================
-- HELPERS
-- ========================================

local function CleanupVelocity()
	if activeVelocity then
		activeVelocity:Destroy()
		activeVelocity = nil
	end
end

local function IsGrounded(): boolean
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { character }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local ray = workspace:Raycast(rootPart.Position, Vector3.new(0, -3.5, 0), rayParams)
	return ray ~= nil
end

-- ========================================
-- WALK/RUN SYSTEM (CTRL KEY)
-- ========================================

local function UpdateWalkSpeed()
	if state.isDashing or state.wallRun.active or state.isSliding then
		return
	end

	if state.isRunning then
		humanoid.WalkSpeed = SETTINGS.Player.RunSpeed
	else
		humanoid.WalkSpeed = SETTINGS.Player.WalkSpeed
	end
end

-- ========================================
-- DASH SYSTEM
-- ========================================

local function PerformDash(direction: string)
	if state.isDashing or state.wallRun.active or state.isSliding then
		return
	end

	local currentTime = tick()
	if currentTime - state.lastDash < SETTINGS.Dash.Cooldown then
		return
	end

	state.isDashing = true
	state.lastDash = currentTime

	local cameraCF = camera.CFrame
	local dashDir = Vector3.zero

	if direction == "W" then
		dashDir = Vector3.new(cameraCF.LookVector.X, 0, cameraCF.LookVector.Z).Unit
	elseif direction == "S" then
		dashDir = -Vector3.new(cameraCF.LookVector.X, 0, cameraCF.LookVector.Z).Unit
	elseif direction == "A" then
		dashDir = -Vector3.new(cameraCF.RightVector.X, 0, cameraCF.RightVector.Z).Unit
	elseif direction == "D" then
		dashDir = Vector3.new(cameraCF.RightVector.X, 0, cameraCF.RightVector.Z).Unit
	end

	CleanupVelocity()

	activeVelocity = Instance.new("BodyVelocity")
	activeVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	activeVelocity.Velocity = dashDir * SETTINGS.Dash.Speed
	activeVelocity.Parent = rootPart

	PlayAnimation("Dash" .. direction)
	DashEvent:FireServer(true, direction)

	task.delay(SETTINGS.Dash.Duration, function()
		CleanupVelocity()
		state.isDashing = false
		DashEvent:FireServer(false, direction)
		UpdateWalkSpeed()
	end)
end

-- ========================================
-- SLIDE SYSTEM
-- ========================================

local function StartSlide()
	if state.isSliding or state.isDashing or state.wallRun.active then
		return
	end

	local currentTime = tick()
	if currentTime - state.lastSlide < SETTINGS.Slide.Cooldown then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if speed < 10 then
		return
	end

	state.isSliding = true
	state.lastSlide = currentTime

	local slideDir = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z).Unit

	CleanupVelocity()

	activeVelocity = Instance.new("BodyVelocity")
	activeVelocity.MaxForce = Vector3.new(100000, 0, 100000)
	activeVelocity.Velocity = slideDir * SETTINGS.Slide.Speed
	activeVelocity.Parent = rootPart

	humanoid.HipHeight = SETTINGS.Slide.HipHeight
	PlayAnimation("Slide")
	MovementEvent:FireServer("slide", true)

	task.delay(SETTINGS.Slide.Duration, function()
		EndSlide()
	end)
end

local function EndSlide()
	if not state.isSliding then
		return
	end

	state.isSliding = false
	humanoid.HipHeight = SETTINGS.Player.HipHeight
	CleanupVelocity()
	MovementEvent:FireServer("slide", false)
	UpdateWalkSpeed()
end

-- ========================================
-- WALL RUN SYSTEM (SIMPLE - NO UP/DOWN)
-- ========================================

local function DetectWall()
	if IsGrounded() then
		return nil, nil, nil
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if horizontalSpeed < SETTINGS.WallRun.MinSpeed then
		return nil, nil, nil
	end

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local origin = rootPart.Position

	-- Check RIGHT side
	for i = 0, 2 do
		local offset = Vector3.new(0, i - 1, 0) * 1.5
		local rightRay =
			workspace:Raycast(origin + offset, rootPart.CFrame.RightVector * SETTINGS.WallRun.DetectionRange, params)

		if rightRay and math.abs(rightRay.Normal.Y) < SETTINGS.WallRun.MaxSlopeAngle then
			return rightRay.Instance, rightRay.Normal, "Right"
		end
	end

	-- Check LEFT side
	for i = 0, 2 do
		local offset = Vector3.new(0, i - 1, 0) * 1.5
		local leftRay =
			workspace:Raycast(origin + offset, -rootPart.CFrame.RightVector * SETTINGS.WallRun.DetectionRange, params)

		if leftRay and math.abs(leftRay.Normal.Y) < SETTINGS.WallRun.MaxSlopeAngle then
			return leftRay.Instance, leftRay.Normal, "Left"
		end
	end

	return nil, nil, nil
end

local function StartWallRun(part, normal, side)
	if state.wallRun.active or state.isDashing or state.isSliding then
		return
	end

	-- Cooldown after ending wall run
	if tick() - state.wallRun.lastEndTime < SETTINGS.WallRun.Cooldown then
		return
	end

	state.wallRun.active = true
	state.wallRun.part = part
	state.wallRun.normal = normal
	state.wallRun.side = side

	-- Get wall direction (horizontal only)
	local wallTangent = Vector3.new(0, 1, 0):Cross(normal)
	if side == "Left" then
		wallTangent = -wallTangent
	end

	-- Create BodyVelocity for wall run
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.MaxForce = Vector3.new(100000, 100000, 100000)
	bodyVel.Velocity = wallTangent * SETTINGS.WallRun.Speed + Vector3.new(0, 2, 0) -- Slight upward to counter gravity
	bodyVel.Parent = rootPart
	state.wallRun.bodyVel = bodyVel

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, false)
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	PlayAnimation("WallRun" .. side)
	MovementEvent:FireServer("wallRun", true, side)

	print("🏃 Wall running on " .. side)
end

local function UpdateWallRun()
	if not state.wallRun.active then
		return
	end

	local camLook = camera.CFrame.LookVector
	local wallNormal = state.wallRun.normal

	-- Check if looking AT the wall (wall is in front of camera)
	-- Increased threshold to be less aggressive
	local lookingAtWall = camLook:Dot(wallNormal)
	if lookingAtWall > 0.5 then
		print("👀 Looking at wall - ending")
		EndWallRun(false)
		return
	end

	-- Get wall tangent direction
	local wallTangent = Vector3.new(0, 1, 0):Cross(wallNormal)
	if state.wallRun.side == "Left" then
		wallTangent = -wallTangent
	end

	-- Check camera alignment with wall direction (horizontal only)
	local camFlat = Vector3.new(camLook.X, 0, camLook.Z)
	if camFlat.Magnitude > 0.1 then
		camFlat = camFlat.Unit
		local alignment = camFlat:Dot(wallTangent)

		-- Reduced threshold - only end if REALLY perpendicular/backward
		if math.abs(alignment) < 0.3 then
			print("👀 Looking perpendicular to wall - ending")
			EndWallRun(false)
			return
		end

		-- Flip direction if looking backward
		if alignment < 0 then
			wallTangent = -wallTangent
		end
	end

	-- Check if still touching wall
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local dir = state.wallRun.side == "Left" and -rootPart.CFrame.RightVector or rootPart.CFrame.RightVector
	local ray = workspace:Raycast(rootPart.Position, dir * (SETTINGS.WallRun.DetectionRange + 1), params)

	if not ray or ray.Instance ~= state.wallRun.part then
		print("📏 Lost wall contact")
		EndWallRun(false)
		return
	end

	-- Keep velocity horizontal with slight upward force
	if state.wallRun.bodyVel then
		state.wallRun.bodyVel.Velocity = wallTangent * SETTINGS.WallRun.Speed + Vector3.new(0, 2, 0)
	end

	-- Keep character facing forward
	rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + wallTangent)
end

function EndWallRun(jumped)
	if not state.wallRun.active then
		return
	end

	print("🛑 Wall run ended")

	state.wallRun.active = false
	state.wallRun.lastEndTime = tick() -- Save when we ended
	local wallNormal = state.wallRun.normal

	if state.wallRun.bodyVel then
		state.wallRun.bodyVel:Destroy()
		state.wallRun.bodyVel = nil
	end

	state.wallRun.side = nil
	state.wallRun.part = nil
	state.wallRun.normal = nil

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	if jumped and wallNormal then
		local jumpDir = (wallNormal + Vector3.new(0, 0.5, 0)).Unit
		rootPart.AssemblyLinearVelocity = jumpDir * SETTINGS.WallRun.JumpOffForce
		print("🚀 Jumped off wall!")
	end

	MovementEvent:FireServer("wallRun", false)
	UpdateWalkSpeed()
end

-- ========================================
-- DOUBLE JUMP
-- ========================================

local function PerformDoubleJump()
	if not state.hasDoubleJump or IsGrounded() then
		return
	end

	state.hasDoubleJump = false
	rootPart.AssemblyLinearVelocity =
		Vector3.new(rootPart.AssemblyLinearVelocity.X, SETTINGS.DoubleJump.Force, rootPart.AssemblyLinearVelocity.Z)

	print("💨 Double jump!")
end

-- ========================================
-- ANIMATION STATE
-- ========================================

local function GetMovementState(): string
	if state.wallRun.active then
		return "WallRun" .. state.wallRun.side
	end

	if state.isDashing then
		return "Dash" .. (state.dashDirection or "W")
	end

	if state.isSliding then
		return "Slide"
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	if speed < 2 then
		return "Idle"
	end

	if state.isRunning and speed > 10 then
		return "Run"
	else
		return "Walk"
	end
end

-- ========================================
-- INPUT HANDLING
-- ========================================

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	-- Track WASD
	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = true
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = true
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = true
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = true
	end

	-- Run toggle (Ctrl)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		state.isRunning = true
		UpdateWalkSpeed()
	end

	-- Dash
	if input.KeyCode == SETTINGS.Dash.Key then
		local direction = "W"
		if keysPressed.W then
			direction = "W"
		elseif keysPressed.A then
			direction = "A"
		elseif keysPressed.S then
			direction = "S"
		elseif keysPressed.D then
			direction = "D"
		end
		state.dashDirection = direction
		PerformDash(direction)
	end

	-- Slide
	if input.KeyCode == SETTINGS.Slide.Key then
		StartSlide()
	end

	-- Jump / Wall run jump
	if input.KeyCode == Enum.KeyCode.Space then
		if state.wallRun.active then
			EndWallRun(true)
		elseif not IsGrounded() then
			PerformDoubleJump()
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	-- Track WASD
	if input.KeyCode == Enum.KeyCode.W then
		keysPressed.W = false
	elseif input.KeyCode == Enum.KeyCode.A then
		keysPressed.A = false
	elseif input.KeyCode == Enum.KeyCode.S then
		keysPressed.S = false
	elseif input.KeyCode == Enum.KeyCode.D then
		keysPressed.D = false
	end

	-- Run toggle (Ctrl)
	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		state.isRunning = false
		UpdateWalkSpeed()
	end

	-- Manual slide end
	if input.KeyCode == SETTINGS.Slide.Key then
		if state.isSliding then
			EndSlide()
		end
	end
end)

-- ========================================
-- UPDATE LOOP
-- ========================================

RunService.RenderStepped:Connect(function()
	-- Reset double jump when grounded
	if IsGrounded() then
		state.hasDoubleJump = true
	end

	-- Wall run
	if state.wallRun.active then
		UpdateWallRun()
	else
		if SETTINGS.WallRun.AutoTrigger then
			local part, normal, side = DetectWall()
			if part then
				StartWallRun(part, normal, side)
			end
		end
	end

	-- Slide speed check
	if state.isSliding then
		local velocity = rootPart.AssemblyLinearVelocity
		local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

		if speed < 5 then
			EndSlide()
		end
	end

	-- Update animations
	local newState = GetMovementState()
	if newState ~= state.currentAnim then
		PlayAnimation(newState)
	end
end)

-- ========================================
-- CLEANUP
-- ========================================

humanoid.Died:Connect(function()
	EndWallRun(false)
	EndSlide()
	state.isDashing = false
	CleanupVelocity()

	if state.wallRun.bodyVel then
		state.wallRun.bodyVel:Destroy()
		state.wallRun.bodyVel = nil
	end
end)

print("✅ MovementClient initialized - SIMPLE MODE")
