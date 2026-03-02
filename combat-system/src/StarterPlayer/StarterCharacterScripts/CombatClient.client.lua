--[[
	CombatClient.lua  (CLIENT — LocalScript inside StarterPlayerScripts or StarterCharacterScripts)
	
	Responsibilities:
	  • Listen for mouse / tap input → fire UsedM1 remote (intent only, no hit data)
	  • ApplyHitEffect  → play hit-reaction / swing animation on correct character
	  • HitConfirm      → (a) flash red Highlight on victim (all clients)
	                       (b) play hit sound on attacker's client only
	                       (c) camera shake on attacker's client only
	                       (d) FOV kick on attacker's client only        [NEW]
	                       (e) camera punch toward target on attacker    [NEW]

	Place in: StarterPlayerScripts/CombatClient  (or StarterCharacterScripts)
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local LocalPlayer  = Players.LocalPlayer
local Camera       = workspace.CurrentCamera

-- ── Shared config ─────────────────────────────────────────────────────────────
local Shared         = ReplicatedStorage:WaitForChild("Shared")
local CombatSettings = require(Shared:WaitForChild("CombatSettings"))

-- ── Remotes ───────────────────────────────────────────────────────────────────
local RemotesFolder     = ReplicatedStorage:WaitForChild("Remotes")
local RE_UsedM1         = RemotesFolder:WaitForChild(CombatSettings.Remotes.UsedM1)        :: RemoteEvent
local RE_ApplyHitEffect = RemotesFolder:WaitForChild(CombatSettings.Remotes.ApplyHitEffect) :: RemoteEvent
local RE_HitConfirm     = RemotesFolder:WaitForChild(CombatSettings.Remotes.HitConfirm)     :: RemoteEvent
local RE_StunApplied    = RemotesFolder:WaitForChild(CombatSettings.Remotes.StunApplied)    :: RemoteEvent
local RE_StunReleased   = RemotesFolder:WaitForChild(CombatSettings.Remotes.StunReleased)   :: RemoteEvent
local RE_TechRoll       = RemotesFolder:WaitForChild(CombatSettings.Remotes.TechRoll)       :: RemoteEvent
local RE_Ragdoll        = RemotesFolder:WaitForChild(CombatSettings.Remotes.Ragdoll)        :: RemoteEvent
local RE_RagdollEnd     = RemotesFolder:WaitForChild(CombatSettings.Remotes.RagdollEnd)     :: RemoteEvent

-- ── Local state ───────────────────────────────────────────────────────────────
local _lastM1Time = -math.huge
local ANIM_CACHE: { [string]: { [string]: AnimationTrack } } = {}

-- Track active highlight per character so we don't stack them
local _activeHighlights: { [Model]: Highlight } = {}

-- ── Stun state (local player only) ────────────────────────────────────────────
local _locallyStunned   = false
local _locallyRagdolled = false

local _lastTechRoll   = -math.huge
local TECH_ROLL_KEY   = Enum.KeyCode[CombatSettings.Stun.TechRoll.Key] or Enum.KeyCode.Q

-- ══════════════════════════════════════════════════════════════════════════════
--  FOV KICK  [NEW]
--
--  On hit confirm, spike FOV upward then spring it back to baseline.
--  We track a target and lerp toward it each RenderStepped so there's no
--  TweenService fighting the camera — same pattern as the existing roll system.
--
--  Profiles scale with combo index so the finisher feels distinctly heavier.
-- ══════════════════════════════════════════════════════════════════════════════

local FOV_BASE    = 70   -- your game's resting FOV; adjust to match your camera setup
local _fovCurrent = FOV_BASE
local _fovTarget  = FOV_BASE

-- Per-combo: how many degrees to kick out, and how fast to return (lerp speed)
local FOV_KICK_PROFILES = {
	[1] = { Kick = 6,  ReturnSpeed = 14 },
	[2] = { Kick = 7,  ReturnSpeed = 13 },
	[3] = { Kick = 8,  ReturnSpeed = 12 },
	[4] = { Kick = 10, ReturnSpeed = 11 },
	[5] = { Kick = 14, ReturnSpeed = 9  },  -- finisher — slower, punchier return
}

local function _triggerFOVKick(comboIndex: number)
	local profile = FOV_KICK_PROFILES[comboIndex] or FOV_KICK_PROFILES[1]
	-- Spike immediately; _tickFOV will lerp it back to base
	_fovCurrent = FOV_BASE + profile.Kick
	_fovTarget  = FOV_BASE
	Camera.FieldOfView = _fovCurrent
end

local function _tickFOV(dt: number)
	if math.abs(_fovCurrent - _fovTarget) < 0.05 then
		_fovCurrent = _fovTarget
		Camera.FieldOfView = _fovCurrent
		return
	end
	local comboIndex = 1  -- use slowest speed as default for the lerp tick
	-- (speed set per-kick; we keep the last-used profile's return speed)
	-- Simple exponential decay toward base — always snappy enough
	_fovCurrent = _fovCurrent + (_fovTarget - _fovCurrent) * math.min(1, dt * 12)
	Camera.FieldOfView = _fovCurrent
end

-- Store return speed separately so the RenderStepped tick can use it
local _fovReturnSpeed = 12

local function _triggerFOVKickFull(comboIndex: number)
	local profile = FOV_KICK_PROFILES[comboIndex] or FOV_KICK_PROFILES[1]
	_fovCurrent     = FOV_BASE + profile.Kick
	_fovTarget      = FOV_BASE
	_fovReturnSpeed = profile.ReturnSpeed
	Camera.FieldOfView = _fovCurrent
end

-- Override the simple tick with the speed-aware version
local function _tickFOVFull(dt: number)
	if math.abs(_fovCurrent - _fovTarget) < 0.05 then
		_fovCurrent = _fovTarget
		Camera.FieldOfView = _fovCurrent
		return
	end
	_fovCurrent = _fovCurrent + (_fovTarget - _fovCurrent) * math.min(1, dt * _fovReturnSpeed)
	Camera.FieldOfView = _fovCurrent
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CAMERA PUNCH  [NEW]
--
--  On hit confirm (attacker only), nudge the camera forward along its LookVector
--  then spring it back using a simple spring simulation.
--
--  We apply the punch as a delta on Camera.CFrame each frame so we're not
--  fighting Roblox's camera controller — only the offset changes, not the
--  full position/orientation that the controller owns.
--
--  "Forward punch" = positive Z offset in camera space → feels like the camera
--  lurches at the target, then snaps back.
-- ══════════════════════════════════════════════════════════════════════════════

-- Spring state — tracks a 1D offset along camera look direction
local _punchOffset   = 0    -- current applied forward offset (studs)
local _punchVelocity = 0    -- spring velocity

-- Spring constants (tweak for feel)
local PUNCH_STIFFNESS = 280   -- how fast it returns to rest
local PUNCH_DAMPING   = 22    -- how much oscillation damping (higher = less bouncy)

-- Per-combo: how far forward to kick the camera (studs)
local PUNCH_PROFILES = {
	[1] = 0.18,
	[2] = 0.20,
	[3] = 0.24,
	[4] = 0.30,
	[5] = 0.45,   -- finisher
}

local function _triggerCameraPunch(comboIndex: number)
	local strength = PUNCH_PROFILES[comboIndex] or PUNCH_PROFILES[1]
	-- Give the spring an instant velocity kick; it will overshoot slightly then settle.
	-- The "overshoot" IS the punch feel — camera darts forward then snaps back.
	_punchVelocity = _punchVelocity + strength * 60   -- impulse (units/s)
end

-- Previous offset we applied so we can undo it and re-apply the new one (delta pattern)
local _punchApplied = 0

local function _tickCameraPunch(dt: number)
	-- Spring formula: F = -k*x - d*v
	local force = (-PUNCH_STIFFNESS * _punchOffset) + (-PUNCH_DAMPING * _punchVelocity)
	_punchVelocity = _punchVelocity + force * dt
	_punchOffset   = _punchOffset   + _punchVelocity * dt

	-- Clamp to avoid exploding on very large dt spikes
	_punchOffset = math.clamp(_punchOffset, -2, 2)

	-- Apply delta: undo old offset, apply new offset along camera LookVector
	local delta = _punchOffset - _punchApplied
	_punchApplied = _punchOffset

	-- Only bother if the delta is meaningful
	if math.abs(delta) > 0.0001 then
		-- CFrame.new with a vector in camera-local space:
		-- LookVector is -Z in Roblox's CFrame convention, so we negate
		Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, -delta)
	end

	-- Dampen to rest so floating point doesn't accumulate forever
	if math.abs(_punchOffset) < 0.0005 and math.abs(_punchVelocity) < 0.001 then
		-- Undo any residual and zero out
		if math.abs(_punchApplied) > 0.0001 then
			Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, _punchApplied)
		end
		_punchOffset   = 0
		_punchVelocity = 0
		_punchApplied  = 0
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  ANIMATION HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

local function _getTrack(character: Model, animId: string): AnimationTrack?
	local humanoid  = character:FindFirstChildOfClass("Humanoid")
	local animator  = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local charName = character.Name
	if not ANIM_CACHE[charName] then ANIM_CACHE[charName] = {} end

	if not ANIM_CACHE[charName][animId] then
		local anim           = Instance.new("Animation")
		anim.AnimationId     = animId
		ANIM_CACHE[charName][animId] = animator:LoadAnimation(anim)
		anim:Destroy()
	end

	return ANIM_CACHE[charName][animId]
end

local function _clearCache(character: Model)
	if _activeHighlights[character] then
		_activeHighlights[character]:Destroy()
		_activeHighlights[character] = nil
	end
	ANIM_CACHE[character.Name] = nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  HIT SOUND
-- ══════════════════════════════════════════════════════════════════════════════

local function _playHitSound(comboIndex: number)
	local soundId = CombatSettings.Audio["M" .. tostring(comboIndex) .. "Sound"]
		or CombatSettings.Audio.M1Sound

	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local sound       = Instance.new("Sound")
	sound.SoundId     = soundId
	sound.Volume      = 1.0
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMaxDistance = 50
	sound.Parent = hrp or workspace
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 3)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  RED HIGHLIGHT FLASH
-- ══════════════════════════════════════════════════════════════════════════════

local HL_CFG = CombatSettings.HitHighlight

local function _flashHighlight(victimChar: Model)
	local existing = _activeHighlights[victimChar]
	if existing then
		existing:Destroy()
		_activeHighlights[victimChar] = nil
	end

	local hl                    = Instance.new("Highlight")
	hl.FillColor                = HL_CFG.FillColor
	hl.OutlineColor             = HL_CFG.OutlineColor
	hl.FillTransparency         = HL_CFG.FillTransparency
	hl.OutlineTransparency      = HL_CFG.OutlineTransparency
	hl.Adornee                  = victimChar
	hl.DepthMode                = Enum.HighlightDepthMode.Occluded
	hl.Parent                   = victimChar

	_activeHighlights[victimChar] = hl

	task.delay(HL_CFG.Duration, function()
		if _activeHighlights[victimChar] == hl then
			hl:Destroy()
			_activeHighlights[victimChar] = nil
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CAMERA SHAKE  (existing — unchanged)
-- ══════════════════════════════════════════════════════════════════════════════

local _shakeOffset  = Vector3.zero
local _shakePower   = 0
local _shakeFreq    = 18
local _shakeTimer   = 0
local _shakeDurLeft = 0

local function _triggerCameraShake(comboIndex: number)
	local profile = CombatSettings.CameraShake[comboIndex]
		or CombatSettings.CameraShake[1]

	_shakePower   = math.max(_shakePower, profile.Magnitude)
	_shakeFreq    = profile.Frequency
	_shakeDurLeft = profile.Duration
	_shakeTimer   = 0
end

-- ══════════════════════════════════════════════════════════════════════════════
--  STUN REMOTE HANDLERS
-- ══════════════════════════════════════════════════════════════════════════════

RE_StunApplied.OnClientEvent:Connect(function(victim: Player, _duration: number)
	if victim ~= LocalPlayer then return end
	_locallyStunned = true
end)

RE_StunReleased.OnClientEvent:Connect(function(victim: Player, _reason: string)
	if victim ~= LocalPlayer then return end
	_locallyStunned = false
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  RAGDOLL REMOTE HANDLERS
-- ══════════════════════════════════════════════════════════════════════════════

local function _setAnimateEnabled(char: Model, enabled: boolean)
	local animScript = char:FindFirstChild("Animate")
	if animScript and animScript:IsA("LocalScript") then
		animScript.Disabled = not enabled
	end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator and not enabled then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
end

RE_Ragdoll.OnClientEvent:Connect(function(victim: Player, _active: boolean)
	local char = victim.Character
	if not char then return end
	_setAnimateEnabled(char, false)
	if victim == LocalPlayer then
		_locallyRagdolled = true
		_locallyStunned   = true
	end
end)

RE_RagdollEnd.OnClientEvent:Connect(function(victim: Player)
	local char = victim.Character
	if not char then return end
	_setAnimateEnabled(char, true)
	if victim == LocalPlayer then
		_locallyRagdolled = false
		_locallyStunned   = false
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  INPUT → INTENT
-- ══════════════════════════════════════════════════════════════════════════════

local function _onM1Input()
	if _locallyStunned or _locallyRagdolled then return end

	local now = os.clock()
	if now - _lastM1Time < CombatSettings.Cooldowns.M1 then return end
	_lastM1Time = now

	local char = LocalPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	RE_UsedM1:FireServer()
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		_onM1Input()
	end

	if input.KeyCode == TECH_ROLL_KEY and _locallyStunned then
		local now = os.clock()
		local cd  = CombatSettings.Stun.TechRoll.Cooldown
		if now - _lastTechRoll >= cd then
			_lastTechRoll = now
			RE_TechRoll:FireServer()
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  SERVER → CLIENT: ANIMATION PLAYBACK
-- ══════════════════════════════════════════════════════════════════════════════

RE_ApplyHitEffect.OnClientEvent:Connect(function(targetPlayer: Player, animKey: string, _comboIndex: number)
	local character = targetPlayer.Character
	if not character then return end

	local animEntry = CombatSettings.Animations[animKey]
	local animId: string?

	if type(animEntry) == "table" then
		animId = animEntry.Id
	elseif type(animEntry) == "string" then
		animId = animEntry
	end
	if not animId then return end

	local isHitReaction = animKey:sub(1, 11) == "HitReaction"
		or animKey:sub(1, 18) == "BlockingHitReaction"

	if isHitReaction then
		local humanoid  = character:FindFirstChildOfClass("Humanoid")
		local animator  = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not animator then return end

		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local name = track.Animation and track.Animation.AnimationId or ""
			if name ~= animId then
				local isReact = false
				for _, key in ipairs({ "HitReaction1","HitReaction2","HitReaction3","HitReaction4","HitReaction5",
					"BlockingHitReaction1","BlockingHitReaction2","BlockingHitReaction3","BlockingHitReaction4","BlockingHitReaction5" }) do
					local data = CombatSettings.Animations[key]
					if type(data) == "string" and data == name then
						isReact = true
						break
					end
				end
				if isReact then track:Stop(0) end
			end
		end

		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local track = animator:LoadAnimation(anim)
		anim:Destroy()
		track.Priority = Enum.AnimationPriority.Action4
		track:Play(0)
		track.Stopped:Connect(function() track:Destroy() end)
	else
		local track = _getTrack(character, animId)
		if not track then return end

		if animKey:sub(1, 1) == "M" and tonumber(animKey:sub(2)) then
			for i = 1, 5 do
				local prevKey  = "M" .. tostring(i)
				local prevData = CombatSettings.Animations[prevKey]
				if prevData and prevKey ~= animKey then
					local prevId    = type(prevData) == "table" and prevData.Id or prevData
					local prevTrack = _getTrack(character, prevId)
					if prevTrack and prevTrack.IsPlaying then
						prevTrack:Stop(0.05)
					end
				end
			end
		end

		track:Play()
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  SERVER → CLIENT: HIT CONFIRM
-- ══════════════════════════════════════════════════════════════════════════════

RE_HitConfirm.OnClientEvent:Connect(function(attacker: Player, victim: Player, comboIndex: number)
	-- Red highlight on victim (every client)
	local victimChar = victim.Character
	if victimChar then
		_flashHighlight(victimChar)
	end

	-- Sound + shake + FOV kick + camera punch — attacker's client only
	if attacker ~= LocalPlayer then return end

	_playHitSound(comboIndex)
	_triggerCameraShake(comboIndex)
	_triggerFOVKickFull(comboIndex)    -- [NEW] FOV spike → spring back to base
	_triggerCameraPunch(comboIndex)    -- [NEW] forward lurch → spring back
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  MAIN RENDER LOOP  — shake + FOV tick + camera punch tick
-- ══════════════════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function(dt: number)
	-- ── Existing camera shake ────────────────────────────────────────────────
	if _shakeDurLeft > 0 then
		_shakeDurLeft = _shakeDurLeft - dt
		_shakeTimer   = _shakeTimer   + dt

		local progress  = math.max(0, _shakeDurLeft) / math.max(0.001, _shakeTimer + _shakeDurLeft)
		local magnitude = _shakePower * progress

		local ox = math.sin(_shakeTimer * _shakeFreq * math.pi * 2)          * magnitude
		local oy = math.sin(_shakeTimer * _shakeFreq * math.pi * 2.3 + 1.1) * magnitude
		_shakeOffset = Vector3.new(ox, oy, 0)

		Camera.CFrame = Camera.CFrame * CFrame.new(_shakeOffset)
	else
		_shakeOffset = Vector3.zero
	end

	-- ── FOV kick lerp back to base  [NEW] ───────────────────────────────────
	_tickFOVFull(dt)

	-- ── Camera punch spring  [NEW] ───────────────────────────────────────────
	_tickCameraPunch(dt)
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  CHARACTER LIFECYCLE
-- ══════════════════════════════════════════════════════════════════════════════

local function _onCharacterAdded(character: Model)
	_clearCache(character)
	-- Reset FOV so respawn doesn't inherit a mid-kick FOV state
	_fovCurrent     = FOV_BASE
	_fovTarget      = FOV_BASE
	_fovReturnSpeed = 12
	Camera.FieldOfView = FOV_BASE
	-- Reset punch state
	_punchOffset   = 0
	_punchVelocity = 0
	_punchApplied  = 0
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then _clearCache(character) end
	end)
end

LocalPlayer.CharacterAdded:Connect(_onCharacterAdded)
if LocalPlayer.Character then
	_onCharacterAdded(LocalPlayer.Character)
end