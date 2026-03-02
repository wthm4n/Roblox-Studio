--[[
	MovementController.client.lua  (CLIENT — LocalScript)
	Client side of the Titanfall-tier movement system.
	Place in: StarterPlayerScripts/MovementController
]]

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local MS      = require(Shared:WaitForChild("MovementSettings"))
local DC      = MS.Dash
local WC      = MS.WallRun
local SC      = MS.Slide
local SP      = MS.Speed
local Anims   = MS.Animations

local Remotes        = ReplicatedStorage:WaitForChild("Remotes")
local function _re(n) return Remotes:WaitForChild(n) :: RemoteEvent end

local RE_RequestDash  = _re(MS.Remotes.RequestDash)
local RE_RequestSlide = _re(MS.Remotes.RequestSlide)
local RE_DashEffect   = _re(MS.Remotes.DashEffect)
local RE_SlideStart   = _re(MS.Remotes.SlideStart)
local RE_SlideEnd     = _re(MS.Remotes.SlideEnd)
local RE_WallRunStart = _re(MS.Remotes.WallRunStart)
local RE_WallRunEnd   = _re(MS.Remotes.WallRunEnd)
local RE_EnergySync   = _re(MS.Remotes.EnergySync)

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ══════════════════════════════════════════════════════════════════════════════
--  ANIMATION ENGINE
-- ══════════════════════════════════════════════════════════════════════════════

local _animator: Animator? = nil
local _tracks: { [string]: AnimationTrack } = {}

local function _killAnimate(char: Model)
	local a = char:FindFirstChild("Animate")
	if a then a.Enabled = false end
	char.ChildAdded:Connect(function(c)
		if c.Name == "Animate" then
			task.defer(function() if c and c.Parent then c.Enabled = false end end)
		end
	end)
end

local function _load(id: string): AnimationTrack?
	if not _animator then return nil end
	if _tracks[id] then return _tracks[id] end
	local a = Instance.new("Animation")
	a.AnimationId = id
	local t = _animator:LoadAnimation(a)
	a:Destroy()
	_tracks[id] = t
	return t
end

local function _preload()
	for _, id in pairs(Anims) do
		if type(id) == "string" then _load(id) end
	end
end

local function _play(id: string, fadeIn: number?, pri: Enum.AnimationPriority?)
	local t = _load(id)
	if not t or t.IsPlaying then return end
	t.Priority = pri or Enum.AnimationPriority.Core
	t:Play(fadeIn or 0.15)
end

local function _stop(id: string, fadeOut: number?)
	local t = _tracks[id]
	if t and t.IsPlaying then t:Stop(fadeOut or 0.2) end
end

local function _stopLoco()
	_stop(Anims.Idle, 0.1)
	_stop(Anims.Walk, 0.1)
	_stop(Anims.Run,  0.1)
end

local function _isPlaying(id: string): boolean
	local t = _tracks[id]
	return t ~= nil and t.IsPlaying
end

local function _playRemote(char: Model, animId: string, pri: Enum.AnimationPriority?, fade: number?)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if not anim then return end
	local a = Instance.new("Animation")
	a.AnimationId = animId
	local t = anim:LoadAnimation(a)
	a:Destroy()
	t.Priority = pri or Enum.AnimationPriority.Action2
	t:Play(fade or 0.1)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CLIENT STATE
-- ══════════════════════════════════════════════════════════════════════════════

local _sprintHeld    = false
local _dashHeld      = false
local _lastDashLocal = -math.huge
local _isDashing     = false
local _isSliding     = false
local _isWallRunning = false
local _energy        = 0

-- ══════════════════════════════════════════════════════════════════════════════
--  SPRINT
-- ══════════════════════════════════════════════════════════════════════════════

local function _setSprint(on: boolean)
	_sprintHeld = on
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or _isSliding then return end
	hum.WalkSpeed = on and SP.Sprint or SP.Walk
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
	if now - _lastDashLocal < DC.Cooldown then return end
	if not _dashHeld then return end
	if _isSliding then return end

	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	local dir = "Forward"
	for kc, d in pairs(KEY_TO_DIR) do
		if UserInputService:IsKeyDown(kc) then dir = d break end
	end

	_lastDashLocal = now
	RE_RequestDash:FireServer(dir)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  SLIDE INPUT
-- ══════════════════════════════════════════════════════════════════════════════

local function _trySlide()
	if _isSliding or _isWallRunning then return end
	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then return end
	local flat = Vector3.new(hrp.AssemblyLinearVelocity.X, 0, hrp.AssemblyLinearVelocity.Z).Magnitude
	if flat < 6 then return end
	RE_RequestSlide:FireServer()
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INPUT BINDING
-- ══════════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(inp, proc)
	if proc then return end

	if inp.KeyCode == Enum.KeyCode.LeftControl then
		_setSprint(true)
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then
			_trySlide()
		end
	end

	if inp.KeyCode == Enum.KeyCode.S and _sprintHeld then
		_trySlide()
	end

	if inp.KeyCode == DC.Key then
		_dashHeld = true
		_tryDash()
	end
end)

UserInputService.InputEnded:Connect(function(inp, _)
	if inp.KeyCode == Enum.KeyCode.LeftControl then _setSprint(false) end
	if inp.KeyCode == DC.Key then _dashHeld = false end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  LOCOMOTION TICK
-- ══════════════════════════════════════════════════════════════════════════════

local function _tickLocomotion()
	if _isDashing or _isSliding or _isWallRunning then return end

	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not hrp or hum.Health <= 0 then return end

	local v    = hrp.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z).Magnitude

	if flat < 0.5 then
		if not _isPlaying(Anims.Idle) then
			_stop(Anims.Walk, 0.2)
			_stop(Anims.Run,  0.2)
			_play(Anims.Idle, 0.2, Enum.AnimationPriority.Core)
		end
	elseif _sprintHeld or flat > SP.Sprint * 0.65 then
		if not _isPlaying(Anims.Run) then
			_stop(Anims.Idle, 0.15)
			_stop(Anims.Walk, 0.15)
			_play(Anims.Run,  0.15, Enum.AnimationPriority.Core)
		end
	else
		if not _isPlaying(Anims.Walk) then
			_stop(Anims.Idle, 0.15)
			_stop(Anims.Run,  0.15)
			_play(Anims.Walk, 0.15, Enum.AnimationPriority.Core)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CAMERA SPRINGS
--  All springs defined here so _tickCamera can call them without forward-ref errors
-- ══════════════════════════════════════════════════════════════════════════════

-- Roll spring
local _camRoll       = 0
local _camRollVel    = 0
local _camRollTarget = 0
local ROLL_STIFFNESS = 12
local ROLL_DAMPING   = 6

local function _setRoll(r: number)
	_camRollTarget = r
end

-- FOV spring
local _fovBase    = 70
local _fovCurrent = 70
local _fovVel     = 0
local _fovTarget  = 70
local FOV_STIFFNESS = 18
local FOV_DAMPING   = 7

local function _setFOV(target: number)
	_fovTarget = target
end

local function _tickFOV(dt: number)
	local force = FOV_STIFFNESS * (_fovTarget - _fovCurrent) - FOV_DAMPING * _fovVel
	_fovVel     = _fovVel     + force * dt
	_fovCurrent = _fovCurrent + _fovVel * dt
	if math.abs(_fovCurrent - _fovBase) < 0.05 and math.abs(_fovVel) < 0.05 and _fovTarget == _fovBase then
		_fovCurrent = _fovBase
		_fovVel     = 0
	end
	Camera.FieldOfView = _fovCurrent
end

-- Pitch spring
local _pitchOffset = 0
local _pitchVel    = 0
local _pitchTarget = 0
local PITCH_STIFFNESS = 14
local PITCH_DAMPING   = 6

local function _setPitch(target: number)
	_pitchTarget = target
end

local function _tickPitch(dt: number)
	local force  = PITCH_STIFFNESS * (_pitchTarget - _pitchOffset) - PITCH_DAMPING * _pitchVel
	_pitchVel    = _pitchVel    + force * dt
	_pitchOffset = _pitchOffset + _pitchVel * dt
	if math.abs(_pitchOffset) < 0.0002 and math.abs(_pitchVel) < 0.0002 and _pitchTarget == 0 then
		_pitchOffset = 0
		_pitchVel    = 0
	end
end

local function _tickCamera(dt: number)
	-- Roll spring
	local force = ROLL_STIFFNESS * (_camRollTarget - _camRoll) - ROLL_DAMPING * _camRollVel
	_camRollVel = _camRollVel + force * dt
	_camRoll    = _camRoll    + _camRollVel * dt
	if math.abs(_camRoll) < 0.0002 and math.abs(_camRollVel) < 0.0002 and _camRollTarget == 0 then
		_camRoll = 0; _camRollVel = 0
	end

	_tickPitch(dt)
	_tickFOV(dt)

	-- Apply all offsets cleanly onto current camera CFrame each frame (no delta accumulation)
	Camera.CFrame = CFrame.fromMatrix(
		Camera.CFrame.Position,
		Camera.CFrame.RightVector,
		Camera.CFrame.UpVector
	) * CFrame.Angles(_pitchOffset, 0, _camRoll)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH EFFECT
-- ══════════════════════════════════════════════════════════════════════════════

RE_DashEffect.OnClientEvent:Connect(function(player: Player, direction: string)
	local char = player.Character
	if not char then return end

	local animKey = DC.Animations[direction]
	local animId  = animKey and Anims[animKey]

	if animId then
		if player == LocalPlayer then
			_isDashing = true
			_stopLoco()
			_play(animId, 0.05, Enum.AnimationPriority.Action3)
			task.delay(DC.Duration + 0.08, function()
				_isDashing = false
				_stop(animId, 0.12)
			end)
		else
			_playRemote(char, animId, Enum.AnimationPriority.Action3, 0.05)
		end
	end

	if player ~= LocalPlayer then return end

	local dur = DC.Duration

	if direction == "Forward" then
		_setFOV(_fovBase + 18)
		_setPitch(math.rad(-2.5))
		_setRoll(0)
		task.delay(dur + 0.15, function()
			_setFOV(_fovBase)
			_setPitch(0)
		end)

	elseif direction == "Backward" then
		_setFOV(_fovBase - 8)
		_setPitch(math.rad(3))
		_setRoll(0)
		task.delay(dur + 0.2, function()
			_setFOV(_fovBase)
			_setPitch(0)
		end)

	elseif direction == "Left" then
		_setRoll(math.rad(7))
		_setFOV(_fovBase + 8)
		_setPitch(math.rad(-1))
		task.delay(dur + 0.25, function()
			_setRoll(0)
			_setFOV(_fovBase)
			_setPitch(0)
		end)

	elseif direction == "Right" then
		_setRoll(math.rad(-7))
		_setFOV(_fovBase + 8)
		_setPitch(math.rad(-1))
		task.delay(dur + 0.25, function()
			_setRoll(0)
			_setFOV(_fovBase)
			_setPitch(0)
		end)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  SLIDE EFFECT
-- ══════════════════════════════════════════════════════════════════════════════

RE_SlideStart.OnClientEvent:Connect(function(player: Player)
	local char = player.Character
	if not char then return end

	if player == LocalPlayer then
		_isSliding = true
		_stopLoco()
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.HipHeight = SC.CrouchHipHeight end
		_play(Anims.Slide, 0.08, Enum.AnimationPriority.Action2)
	else
		_playRemote(char, Anims.Slide, Enum.AnimationPriority.Action2, 0.08)
	end
end)

RE_SlideEnd.OnClientEvent:Connect(function(player: Player)
	local char = player.Character
	if not char then return end

	if player == LocalPlayer then
		_isSliding = false
		_stop(Anims.Slide, 0.2)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.HipHeight = SC.DefaultHipHeight
			hum.WalkSpeed = _sprintHeld and SP.Sprint or SP.Walk
		end
	else
		_stop(Anims.Slide, 0.2)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN EFFECT
-- ══════════════════════════════════════════════════════════════════════════════

RE_WallRunStart.OnClientEvent:Connect(function(player: Player, side: string)
	local char = player.Character
	if not char then return end

	local animId = (side == "Left") and Anims.WallRunLeft or Anims.WallRunRight

	if player == LocalPlayer then
		_isWallRunning = true
		_stopLoco()
		_play(animId, 0.1, Enum.AnimationPriority.Action2)
		-- Roll toward the wall + slight FOV bump + gentle upward pitch (momentum feel)
		local roll = (side == "Right") and math.rad(-6) or math.rad(6)
		_setRoll(roll)
		_setFOV(_fovBase + 10)
		_setPitch(math.rad(-1.5))
	else
		_playRemote(char, animId, Enum.AnimationPriority.Action2, 0.1)
	end
end)

RE_WallRunEnd.OnClientEvent:Connect(function(player: Player)
	if player == LocalPlayer then
		_isWallRunning = false
		_stop(Anims.WallRunLeft,  0.25)
		_stop(Anims.WallRunRight, 0.25)
		-- Spring everything back smoothly
		_setRoll(0)
		_setFOV(_fovBase)
		_setPitch(0)
	else
		local char = player.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local anim = hum and hum:FindFirstChildOfClass("Animator")
		if anim then
			for _, t in ipairs(anim:GetPlayingAnimationTracks()) do
				local id = t.Animation and t.Animation.AnimationId
				if id == Anims.WallRunLeft or id == Anims.WallRunRight then
					t:Stop(0.25)
				end
			end
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  ENERGY SYNC
-- ══════════════════════════════════════════════════════════════════════════════

RE_EnergySync.OnClientEvent:Connect(function(energy: number)
	_energy = energy
	-- Hook your UI here if needed
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  CHARACTER SETUP
-- ══════════════════════════════════════════════════════════════════════════════

local function _onCharacterAdded(char: Model)
	_tracks        = {}
	_animator      = nil
	_isDashing     = false
	_isSliding     = false
	_isWallRunning = false
	_sprintHeld    = false
	_camRoll       = 0
	_camRollVel    = 0
	_camRollTarget = 0
	_fovCurrent    = _fovBase
	_fovVel        = 0
	_fovTarget     = _fovBase
	_pitchOffset   = 0
	_pitchVel      = 0
	_pitchTarget   = 0
	Camera.FieldOfView = _fovBase

	local hum = char:WaitForChild("Humanoid") :: Humanoid
	_animator = hum:WaitForChild("Animator") :: Animator

	_killAnimate(char)
	hum.WalkSpeed = SP.Walk
	hum.JumpPower = 50

	task.defer(_preload)
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

print("[MovementController] Momentum system ready.")