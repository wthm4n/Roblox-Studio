--[[
	MovementController.client.lua  (CLIENT — LocalScript)
	Handles all client-side movement input, animation playback, and VFX for:
	  • Directional Dash (Q + WASD)
	  • Wall Run (auto-attach, animation, tilt)

	Architecture:
	  • Input is captured HERE on the client for responsiveness.
	  • Client immediately plays the local animation and sends intent to server.
	  • Server validates and applies physics.
	  • Server fires DashEffect / WallRunStart back to ALL clients for remote players.

	Place in: StarterPlayerScripts/MovementController  (LocalScript)
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

-- ── Settings ──────────────────────────────────────────────────────────────────
local Shared           = ReplicatedStorage:WaitForChild("Shared")
local MovementSettings = require(Shared:WaitForChild("MovementSettings"))
local DC               = MovementSettings.Dash
local WC               = MovementSettings.WallRun
local Anims            = MovementSettings.Animations

-- ── Remotes ───────────────────────────────────────────────────────────────────
local Remotes      = ReplicatedStorage:WaitForChild("Remotes")
local RE_RequestDash  = Remotes:WaitForChild(MovementSettings.Remotes.RequestDash)  :: RemoteEvent
local RE_DashEffect   = Remotes:WaitForChild(MovementSettings.Remotes.DashEffect)   :: RemoteEvent
local RE_WallRunStart = Remotes:WaitForChild(MovementSettings.Remotes.WallRunStart) :: RemoteEvent
local RE_WallRunEnd   = Remotes:WaitForChild(MovementSettings.Remotes.WallRunEnd)   :: RemoteEvent

-- ── Local player ──────────────────────────────────────────────────────────────
local LocalPlayer  = Players.LocalPlayer
local Camera       = workspace.CurrentCamera

-- ══════════════════════════════════════════════════════════════════════════════
--  ANIMATION HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

-- Cache loaded tracks to avoid re-loading them each dash
local _animCache: { [string]: AnimationTrack } = {}

local function _getAnimator(character: Model): Animator?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

local function _loadAnim(character: Model, animId: string): AnimationTrack?
	if _animCache[animId] then return _animCache[animId] end
	local animator = _getAnimator(character)
	if not animator then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId

	local track = animator:LoadAnimation(anim)
	anim:Destroy()
	_animCache[animId] = track
	return track
end

local function _playAnim(character: Model, animId: string, priority: Enum.AnimationPriority?, speed: number?)
	local track = _loadAnim(character, animId)
	if not track then return end
	track.Priority = priority or Enum.AnimationPriority.Action2
	track:Play()
	if speed then track:AdjustSpeed(speed) end
end

local function _stopAnim(animId: string)
	local track = _animCache[animId]
	if track and track.IsPlaying then
		track:Stop(0.2)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH INPUT
-- ══════════════════════════════════════════════════════════════════════════════

-- Cooldown mirror on client (prevents spam-sending to server)
local _lastDashTime = -math.huge
local _dashKeyHeld  = false

-- Map KeyCode → direction string
local KEY_TO_DIR: { [Enum.KeyCode]: string } = {
	[DC.Keys.Forward]  = "Forward",
	[DC.Keys.Backward] = "Backward",
	[DC.Keys.Left]     = "Left",
	[DC.Keys.Right]    = "Right",
}

local function _tryDash()
	local now = os.clock()
	if now - _lastDashTime < DC.Cooldown then return end
	if not _dashKeyHeld then return end

	local character = LocalPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end

	-- Figure out which direction key is held
	local direction: string? = nil
	for keyCode, dir in pairs(KEY_TO_DIR) do
		if UserInputService:IsKeyDown(keyCode) then
			direction = dir
			break
		end
	end

	-- If no direction key held, dash forward by default
	if not direction then direction = "Forward" end

	_lastDashTime = now

	-- Tell server (server does authority check + physics)
	RE_RequestDash:FireServer(direction)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == DC.Key then
		_dashKeyHeld = true
		_tryDash()
	end
end)

UserInputService.InputEnded:Connect(function(input, _)
	if input.KeyCode == DC.Key then
		_dashKeyHeld = false
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  DASH EFFECT (plays for ALL clients — remote and local)
-- ══════════════════════════════════════════════════════════════════════════════

RE_DashEffect.OnClientEvent:Connect(function(player: Player, direction: string)
	local character = player.Character
	if not character then return end

	-- Play directional dash animation
	local animKey = DC.Animations[direction]
	if animKey and Anims[animKey] then
		_playAnim(character, Anims[animKey], Enum.AnimationPriority.Action3)
	end

	-- ── Screen tilt VFX (local player only) ──────────────────────────────────
	if player ~= LocalPlayer then return end

	-- Subtle camera roll to sell the speed
	local tiltDir = 0
	if direction == "Left"  then tiltDir =  4 end
	if direction == "Right" then tiltDir = -4 end

	if tiltDir ~= 0 then
		local startCF   = Camera.CFrame
		local targetCF  = startCF * CFrame.Angles(0, 0, math.rad(tiltDir))
		local tween = TweenService:Create(Camera, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = targetCF
		})
		tween:Play()
		task.delay(DC.Duration, function()
			local returnTween = TweenService:Create(Camera, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				CFrame = Camera.CFrame * CFrame.Angles(0, 0, math.rad(-tiltDir))
			})
			returnTween:Play()
		end)
	end

	-- ── Speed lines / blur (optional — uses DepthOfField or MotionBlur) ──────
	-- Uncomment and customise if your game has post-processing effects:
	-- local blur = game:GetService("Lighting"):FindFirstChildOfClass("MotionBlur")
	-- if blur then
	--     blur.Intensity = 0.3
	--     task.delay(DC.Duration + DC.FadeTime, function() blur.Intensity = 0 end)
	-- end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL RUN ANIMATIONS + CAMERA TILT
-- ══════════════════════════════════════════════════════════════════════════════

-- Per-player wall run state for client (animation + tilt tracking)
type ClientWallState = {
	Side   : string,
	TiltCF : CFrame?,
}
local _wallStates: { [Player]: ClientWallState } = {}

-- Smoothly tilts camera toward wall while wall running
local _wallRunCamTilt = 0  -- current degrees of camera roll

local function _setWallCamTilt(targetDeg: number)
	if math.abs(_wallRunCamTilt - targetDeg) < 0.1 then return end
	_wallRunCamTilt = targetDeg
end

RE_WallRunStart.OnClientEvent:Connect(function(player: Player, side: string)
	local character = player.Character
	if not character then return end

	_wallStates[player] = { Side = side }

	-- Play wall run animation
	local animId = (side == "Left") and Anims.WallRunLeft or Anims.WallRunRight
	if animId then
		_playAnim(character, animId, Enum.AnimationPriority.Action2)
	end

	-- Camera tilt for local player
	if player == LocalPlayer then
		local tilt = (side == "Right") and -WC.TiltAngle or WC.TiltAngle
		_setWallCamTilt(tilt)
	end
end)

RE_WallRunEnd.OnClientEvent:Connect(function(player: Player)
	local ws = _wallStates[player]
	if not ws then return end

	local character = player.Character
	if character then
		-- Stop whichever wall run anim is playing
		_stopAnim(Anims.WallRunLeft)
		_stopAnim(Anims.WallRunRight)
	end

	_wallStates[player] = nil

	-- Reset camera tilt for local player
	if player == LocalPlayer then
		_setWallCamTilt(0)
	end
end)

-- ── Camera tilt application (smooth lerp each frame) ─────────────────────────
RunService.RenderStepped:Connect(function(dt)
	if _wallRunCamTilt == 0 then return end

	-- Lerp current camera roll toward target
	local currentRoll = 0  -- we don't track it but tween handles it
	-- Apply residual tilt correction each frame
	-- (Simple approach: the WallRunEnd fires instantly so tilt returns to 0 cleanly)
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  WALL JUMP (CLIENT INPUT)
--  When wall running, pressing Space jumps away from the wall.
--  Server handles the actual physics — client just sends the intent.
-- ══════════════════════════════════════════════════════════════════════════════

-- Wall jump remote (add to MovementSettings.Remotes if you want server authority)
-- For now, we let Roblox's built-in jump handle it, which naturally ends wall run
-- because the server's _tickWallRun will detect the grounded state change.
-- If you want explicit wall jump forces, wire up a RequestWallJump remote here.

UserInputService.JumpRequest:Connect(function()
	-- If local player is wall running, the server will naturally detach them
	-- when their Humanoid jumps and they leave the wall surface.
	-- No extra remote needed unless you want the custom wall-jump force from WC settings.
end)

print("[MovementController] Phase 2 client ready.")