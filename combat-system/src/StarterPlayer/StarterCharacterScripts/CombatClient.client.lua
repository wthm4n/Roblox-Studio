--[[
	MovementController.client.lua  (CLIENT — LocalScript)
	Full movement system: Idle/Walk/Run/Sprint/Dash/Slide/WallRun animations + input.

	Place in: StarterPlayerScripts/MovementController  (LocalScript)

	ARCHITECTURE:
	  • We DISABLE the default Animate script entirely and own all animations here.
	  • Sprint  : LeftControl held → boosted WalkSpeed + Run anim
	  • Dash    : Q + WASD → fires RequestDash to server, plays directional anim
	  • Slide   : LeftControl + S while sprinting → plays Slide anim, brief speed burst
	  • WallRun : server detects + fires WallRunStart/End → we play the anim
	  • Camera tilt on side dashes uses additive delta roll, NOT tweening Camera.CFrame
]]

print("[MovementController] Loading...")

-- ── Services ──────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ── Settings ──────────────────────────────────────────────────────────────────
local Shared           = ReplicatedStorage:WaitForChild("Shared")
local MovementSettings = require(Shared:WaitForChild("MovementSettings"))
local DC               = MovementSettings.Dash
local WC               = MovementSettings.WallRun
local SC               = MovementSettings.Slide
local Anims            = MovementSettings.Animations

-- ── Remotes ───────────────────────────────────────────────────────────────────
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local RE_RequestDash  = Remotes:WaitForChild(MovementSettings.Remotes.RequestDash)  :: RemoteEvent
local RE_DashEffect   = Remotes:WaitForChild(MovementSettings.Remotes.DashEffect)   :: RemoteEvent
local RE_WallRunStart = Remotes:WaitForChild(MovementSettings.Remotes.WallRunStart) :: RemoteEvent
local RE_WallRunEnd   = Remotes:WaitForChild(MovementSettings.Remotes.WallRunEnd)   :: RemoteEvent

-- ── Local refs ────────────────────────────────────────────────────────────────
local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ══════════════════════════════════════════════════════════════════════════════
--  ANIMATION SYSTEM
--  We kill the default Animate script and drive every anim ourselves.
-- ══════════════════════════════════════════════════════════════════════════════

local _animator:   Animator? = nil
local _animTracks: { [string]: AnimationTrack } = {}

local function _killDefaultAnimate(character: Model)
	local animate = character:FindFirstChild("Animate")
	if animate then animate.Enabled = false end
end

local function _loadTrack(animId: string): AnimationTrack?
	if not _animator then return nil end
	if _animTracks[animId] then return _animTracks[animId] end
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = _animator:LoadAnimation(anim)
	anim:Destroy()
	_animTracks[animId] = track
	return track
end

local function _preloadAll()
	for _, id in pairs(Anims) do
		if type(id) == "string" then
			_loadTrack(id)
		end
	end
end

local function _playTrack(animId: string, fadeIn: number?, priority: Enum.AnimationPriority?)
	local track = _loadTrack(animId)
	if not track then return end
	if track.IsPlaying then return end
	track.Priority = priority or Enum.AnimationPriority.Core
	track:Play(fadeIn or 0.15)
end

local function _stopTrack(animId: string, fadeOut: number?)
	local track = _animTracks[animId]
	if track and track.IsPlaying then
		track:Stop(fadeOut or 0.2)
	end
end

local function _stopAllLocomotion()
	_stopTrack(Anims.Idle, 0.1)
	_stopTrack(Anims.Walk, 0.1)
	_stopTrack(Anims.Run,  0.1)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INPUT STATE
-- ══════════════════════════════════════════════════════════════════════════════

local _sprintHeld    = false
local _dashHeld      = false
local _lastDash      = -math.huge
local _isSliding     = false
local _isWallRunning = false

-- ══════════════════════════════════════════════════════════════════════════════
--  SPRINT
-- ══════════════════════════════════════════════════════════════════════════════

local BASE_SPEED   = 16
local SPRINT_SPEED = 28

local function _setSprint(on: boolean)
	_sprintHeld = on
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or _isSliding then return end
	humanoid.WalkSpeed = on and SPRINT_SPEED or BASE_SPEED
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SLIDE
-- ══════════════════════════════════════════════════════════════════════════════

local function _startSlide()
	if _isSliding then return end
	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp then return end

	-- Need to be moving to slide
	local flatSpeed = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
	if flatSpeed < 5 then return end

	_isSliding = true
	_stopAllLocomotion()

	humanoid.HipHeight  = SC.CrouchHipHeight
	humanoid.WalkSpeed  = SC.Speed

	_playTrack(Anims.Slide, 0.08, Enum.AnimationPriority.Action2)

	task.delay(SC.Duration, function()
		if not _isSliding then return end
		_isSliding = false
		local char = LocalPlayer.Character
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.HipHeight  = SC.DefaultHipHeight
			hum.WalkSpeed  = _sprintHeld and SPRINT_SPEED or BASE_SPEED
		end
		_stopTrack(Anims.Slide, 0.2)
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH INPUT
-- ══════════════════════════════════════════════════════════════════════════════

local KEY_TO_DIR: { [Enum.KeyCode]: string } = {
	[DC.Keys.Forward]  = "Forward",
	[DC.Keys.Backward] = "Backward",
	[DC.Keys.Left]     = "Left",
	[DC.Keys.Right]    = "Right",
}

local function _tryDash()
	local now = os.clock()
	if now - _lastDash < DC.Cooldown  then return end
	if not _dashHeld                  then return end
	if _isSliding or _isWallRunning   then return end

	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	local direction = "Forward"
	for keyCode, dir in pairs(KEY_TO_DIR) do
		if UserInputService:IsKeyDown(keyCode) then
			direction = dir
			break
		end
	end

	_lastDash = now
	RE_RequestDash:FireServer(direction)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INPUT BINDING
-- ══════════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end

	if input.KeyCode == Enum.KeyCode.LeftControl then
		_setSprint(true)
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			_startSlide()
		end
	end

	if input.KeyCode == Enum.KeyCode.S and _sprintHeld then
		_startSlide()
	end

	if input.KeyCode == DC.Key then
		_dashHeld = true
		_tryDash()
	end
end)

UserInputService.InputEnded:Connect(function(input, _)
	if input.KeyCode == Enum.KeyCode.LeftControl then
		_setSprint(false)
	end
	if input.KeyCode == DC.Key then
		_dashHeld = false
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  LOCOMOTION TICK  (Idle / Walk / Run)
-- ══════════════════════════════════════════════════════════════════════════════

local function _tickLocomotion()
	-- Don't fight action anims
	if _isSliding or _isWallRunning then return end

	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local hrp      = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not hrp or humanoid.Health <= 0 then return end

	local vel       = hrp.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	-- Helper: is this specific track already playing?
	local function playing(id)
		local t = _animTracks[id]
		return t and t.IsPlaying
	end

	if flatSpeed < 0.5 then
		if not playing(Anims.Idle) then
			_stopTrack(Anims.Walk, 0.2)
			_stopTrack(Anims.Run,  0.2)
			_playTrack(Anims.Idle, 0.2, Enum.AnimationPriority.Core)
		end
	elseif _sprintHeld or flatSpeed > SPRINT_SPEED * 0.7 then
		if not playing(Anims.Run) then
			_stopTrack(Anims.Idle, 0.15)
			_stopTrack(Anims.Walk, 0.15)
			_playTrack(Anims.Run,  0.15, Enum.AnimationPriority.Core)
		end
	else
		if not playing(Anims.Walk) then
			_stopTrack(Anims.Idle, 0.15)
			_stopTrack(Anims.Run,  0.15)
			_playTrack(Anims.Walk, 0.15, Enum.AnimationPriority.Core)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CAMERA TILT  (side dashes + wall run)
--
--  The WRONG way: TweenService:Create(Camera, ...) or Camera.CFrame = newCF
--    → This overwrites position/look that Roblox's camera controller manages.
--    → Results in camera snapping, jitter, or spinning.
--
--  The RIGHT way: track a roll target, lerp _camRoll toward it each frame,
--    then multiply the delta onto Camera.CFrame so only the roll axis changes.
--    Roblox's controller still owns position + yaw + pitch.
-- ══════════════════════════════════════════════════════════════════════════════

local _camRoll       = 0    -- current applied roll (radians)
local _camRollTarget = 0    -- where we're lerping to
local ROLL_LERP_SPEED = 12  -- how snappy the lerp is

local function _setRollTarget(rad: number)
	_camRollTarget = rad
end

local function _tickCamera(dt: number)
	local diff = _camRollTarget - _camRoll
	if math.abs(diff) < 0.0001 then
		-- Snap to exactly 0 when returning to neutral so error doesn't accumulate
		if _camRollTarget == 0 and _camRoll ~= 0 then
			Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, -_camRoll)
			_camRoll = 0
		end
		return
	end

	local prev   = _camRoll
	_camRoll     = _camRoll + diff * math.min(1, dt * ROLL_LERP_SPEED)
	local delta  = _camRoll - prev

	-- Apply only the delta so we're not fighting the camera controller
	Camera.CFrame = Camera.CFrame * CFrame.Angles(0, 0, delta)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH EFFECT  (fired by server → all clients)
-- ══════════════════════════════════════════════════════════════════════════════

RE_DashEffect.OnClientEvent:Connect(function(player: Player, direction: string)
	local character = player.Character
	if not character then return end

	local animKey = DC.Animations[direction]
	local animId  = animKey and Anims[animKey]

	if animId then
		if player == LocalPlayer then
			_stopAllLocomotion()
			_playTrack(animId, 0.05, Enum.AnimationPriority.Action3)
			task.delay(DC.Duration + 0.05, function()
				_stopTrack(animId, 0.15)
			end)
		else
			-- Remote player: play on their animator without affecting our cache
			local hum = character:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if animator then
				local a = Instance.new("Animation")
				a.AnimationId = animId
				local t = animator:LoadAnimation(a)
				a:Destroy()
				t.Priority = Enum.AnimationPriority.Action3
				t:Play(0.05)
			end
		end
	end

	-- Camera roll (local only, side dashes only)
	if player ~= LocalPlayer then return end
	if direction == "Left" then
		_setRollTarget(math.rad(5))
		task.delay(DC.Duration, function() _setRollTarget(0) end)
	elseif direction == "Right" then
		_setRollTarget(math.rad(-5))
		task.delay(DC.Duration, function() _setRollTarget(0) end)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN ANIMATIONS
-- ══════════════════════════════════════════════════════════════════════════════

RE_WallRunStart.OnClientEvent:Connect(function(player: Player, side: string)
	local character = player.Character
	if not character then return end

	local animId = (side == "Left") and Anims.WallRunLeft or Anims.WallRunRight

	if player == LocalPlayer then
		_isWallRunning = true
		_stopAllLocomotion()
		_playTrack(animId, 0.1, Enum.AnimationPriority.Action2)
		local tilt = (side == "Right") and math.rad(-7) or math.rad(7)
		_setRollTarget(tilt)
	else
		local hum = character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			local a = Instance.new("Animation")
			a.AnimationId = animId
			local t = animator:LoadAnimation(a)
			a:Destroy()
			t.Priority = Enum.AnimationPriority.Action2
			t:Play(0.1)
		end
	end
end)

RE_WallRunEnd.OnClientEvent:Connect(function(player: Player)
	if player == LocalPlayer then
		_isWallRunning = false
		_stopTrack(Anims.WallRunLeft,  0.2)
		_stopTrack(Anims.WallRunRight, 0.2)
		_setRollTarget(0)
	else
		local character = player.Character
		if not character then return end
		local hum = character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
				local id = t.Animation and t.Animation.AnimationId
				if id == Anims.WallRunLeft or id == Anims.WallRunRight then
					t:Stop(0.2)
				end
			end
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  CHARACTER SETUP
-- ══════════════════════════════════════════════════════════════════════════════

local function _onCharacterAdded(character: Model)
	_animTracks    = {}
	_animator      = nil
	_isSliding     = false
	_isWallRunning = false
	_camRoll       = 0
	_camRollTarget = 0
	_sprintHeld    = false

	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	_animator = humanoid:WaitForChild("Animator") :: Animator

	-- Kill default Animate immediately
	_killDefaultAnimate(character)

	-- Kill it again if it gets re-added (Roblox sometimes re-parents it)
	character.ChildAdded:Connect(function(child)
		if child.Name == "Animate" then
			task.defer(function()
				if child and child.Parent then child.Enabled = false end
			end)
		end
	end)

	humanoid.WalkSpeed = BASE_SPEED
	humanoid.JumpPower = 50

	_preloadAll()
end

if LocalPlayer.Character then
	_onCharacterAdded(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(_onCharacterAdded)

-- ══════════════════════════════════════════════════════════════════════════════
--  MAIN LOOP
-- ══════════════════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function(dt)
	_tickLocomotion()
	_tickCamera(dt)
end)

print("[MovementController] Ready.")