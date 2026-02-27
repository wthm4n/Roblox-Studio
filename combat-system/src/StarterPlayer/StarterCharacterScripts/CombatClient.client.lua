--[[
	CombatClient.lua  (CLIENT — LocalScript inside StarterPlayerScripts or StarterCharacterScripts)
	
	Responsibilities:
	  • Listen for mouse / tap input → fire UsedM1 remote (intent only, no hit data)
	  • ApplyHitEffect  → play hit-reaction / swing animation on correct character
	  • HitConfirm      → (a) flash red Highlight on victim (all clients)
	                       (b) play hit sound on attacker's client only
	                       (c) camera shake on attacker's client only

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
-- Whether THIS local client is currently stunned (for input blocking + UI).
local _locallyStunned  = false  -- is the local player currently stunned/ragdolled?
local _locallyRagdolled = false -- is the local player currently ragdolled?

-- Tech roll cooldown mirror (server has authoritative check too)
local _lastTechRoll   = -math.huge
local TECH_ROLL_KEY   = Enum.KeyCode[CombatSettings.Stun.TechRoll.Key] or Enum.KeyCode.Q

-- ═══════════════════════════════════════════════════════════════════════════════
--  ANIMATION HELPERS
-- ═══════════════════════════════════════════════════════════════════════════════

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
	-- Also clean up any leftover highlight
	if _activeHighlights[character] then
		_activeHighlights[character]:Destroy()
		_activeHighlights[character] = nil
	end
	ANIM_CACHE[character.Name] = nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  HIT SOUND  (plays on attacker's client only, when server confirms a hit)
-- ═══════════════════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════════════════
--  RED HIGHLIGHT FLASH  (all clients see this on the victim)
-- ═══════════════════════════════════════════════════════════════════════════════

local HL_CFG = CombatSettings.HitHighlight

local function _flashHighlight(victimChar: Model)
	-- Reuse existing highlight if it's already on this character (rapid hits)
	local existing = _activeHighlights[victimChar]
	if existing then
		-- Just reset the removal timer by cancelling the old task implicitly;
		-- we'll create a new one below after re-setting properties.
		existing:Destroy()
		_activeHighlights[victimChar] = nil
	end

	-- Create a fresh Highlight parented inside the victim's character
	local hl                    = Instance.new("Highlight")
	hl.FillColor                = HL_CFG.FillColor
	hl.OutlineColor             = HL_CFG.OutlineColor
	hl.FillTransparency         = HL_CFG.FillTransparency
	hl.OutlineTransparency      = HL_CFG.OutlineTransparency
	hl.Adornee                  = victimChar   -- entire character model
	hl.DepthMode                = Enum.HighlightDepthMode.Occluded
	hl.Parent                   = victimChar

	_activeHighlights[victimChar] = hl

	-- Auto-remove after Duration
	task.delay(HL_CFG.Duration, function()
		if _activeHighlights[victimChar] == hl then
			hl:Destroy()
			_activeHighlights[victimChar] = nil
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  CAMERA SHAKE  (only the attacker's local client runs this)
-- ═══════════════════════════════════════════════════════════════════════════════

-- Pure Luau trauma-style shake — no external libraries needed.
-- We accumulate a shakeOffset that we apply to Camera.CFrame every frame.

local _shakeOffset  = Vector3.zero
local _shakePower   = 0        -- current shake magnitude (decays over time)
local _shakeFreq    = 18       -- oscillations per second
local _shakeTimer   = 0        -- time accumulator for oscillation
local _shakeDurLeft = 0        -- seconds remaining for this shake

RunService.RenderStepped:Connect(function(dt: number)
	if _shakeDurLeft <= 0 then
		_shakeOffset = Vector3.zero
		return
	end

	_shakeDurLeft = _shakeDurLeft - dt
	_shakeTimer   = _shakeTimer   + dt

	-- Smooth decay: power falls off as duration runs out
	local progress  = math.max(0, _shakeDurLeft) / math.max(0.001, _shakeTimer + _shakeDurLeft)
	local magnitude = _shakePower * progress

	-- Oscillate on X/Y using sin at slightly different frequencies for organicness
	local ox = math.sin(_shakeTimer * _shakeFreq * math.pi * 2)          * magnitude
	local oy = math.sin(_shakeTimer * _shakeFreq * math.pi * 2.3 + 1.1) * magnitude
	_shakeOffset = Vector3.new(ox, oy, 0)

	Camera.CFrame = Camera.CFrame * CFrame.new(_shakeOffset)
end)

local function _triggerCameraShake(comboIndex: number)
	local profile = CombatSettings.CameraShake[comboIndex]
		or CombatSettings.CameraShake[1]

	-- If a shake is already running, take the stronger value
	_shakePower   = math.max(_shakePower, profile.Magnitude)
	_shakeFreq    = profile.Frequency
	-- Reset duration (extend if a new hit comes in fast)
	_shakeDurLeft = profile.Duration
	_shakeTimer   = 0
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  STUN REMOTE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- StunApplied (victim: Player, duration: number)
RE_StunApplied.OnClientEvent:Connect(function(victim: Player, _duration: number)
	if victim ~= LocalPlayer then return end
	_locallyStunned = true
	-- No GUI — ragdoll physics is the visual
end)

-- StunReleased (victim: Player, reason: string)
RE_StunReleased.OnClientEvent:Connect(function(victim: Player, _reason: string)
	if victim ~= LocalPlayer then return end
	_locallyStunned = false
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  RAGDOLL REMOTE HANDLERS
--  Server tells ALL clients to disable / re-enable the victim's Animate script.
--  Without this, Roblox's default animation controller fights the physics joints
--  and the ragdoll looks stiff / snaps back to idle pose.
-- ═══════════════════════════════════════════════════════════════════════════════

local function _setAnimateEnabled(char: Model, enabled: boolean)
	-- The "Animate" LocalScript lives directly under the character model
	local animScript = char:FindFirstChild("Animate")
	if animScript and animScript:IsA("LocalScript") then
		animScript.Disabled = not enabled
	end
	-- Also stop all currently-playing animation tracks so they don't hold poses
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator and not enabled then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
end

-- Ragdoll: victim: Player, active: boolean
RE_Ragdoll.OnClientEvent:Connect(function(victim: Player, _active: boolean)
	local char = victim.Character
	if not char then return end

	-- Disable Animate on ALL clients so nobody sees animation fighting the physics
	_setAnimateEnabled(char, false)

	-- Track ragdoll state for the local player (blocks input)
	if victim == LocalPlayer then
		_locallyRagdolled = true
		_locallyStunned   = true
	end
end)

-- RagdollEnd: victim: Player
RE_RagdollEnd.OnClientEvent:Connect(function(victim: Player)
	local char = victim.Character
	if not char then return end

	_setAnimateEnabled(char, true)

	if victim == LocalPlayer then
		_locallyRagdolled = false
		_locallyStunned   = false
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  INPUT → INTENT

-- ═══════════════════════════════════════════════════════════════════════════════

local function _onM1Input()
	-- Can't attack while stunned (server also gates, avoids the round trip)
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

-- ═══════════════════════════════════════════════════════════════════════════════
--  INPUT LISTENER  (M1 attack + Q tech roll)
-- ═══════════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end

	-- M1 attack
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		_onM1Input()
	end

	-- Tech roll escape (Q while stunned)
	if input.KeyCode == TECH_ROLL_KEY and _locallyStunned then
		local now = os.clock()
		local cd  = CombatSettings.Stun.TechRoll.Cooldown
		if now - _lastTechRoll >= cd then
			_lastTechRoll = now
			RE_TechRoll:FireServer()
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  SERVER → CLIENT: ANIMATION PLAYBACK  (swing anims + hit reactions)
--
--  Hit reactions (HitReaction1–5) are played DIRECTLY on the victim's Animator,
--  bypassing the Animate LocalScript entirely. This means they work even while
--  the character is ragdolled (Animate is disabled during ragdoll).
--
--  Swing anims (M1–M5) play on the attacker normally.
-- ═══════════════════════════════════════════════════════════════════════════════

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
		-- ── Play directly on Animator — works even with Animate disabled ─────
		local humanoid  = character:FindFirstChildOfClass("Humanoid")
		local animator  = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if not animator then return end

		-- Stop any other hit reaction already playing so they don't stack
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local name = track.Animation and track.Animation.AnimationId or ""
			-- Stop other reactions but not the ragdoll/idle if Animate is off
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

		-- Load + play the reaction track fresh every hit (short, one-shot)
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local track = animator:LoadAnimation(anim)
		anim:Destroy()
		track.Priority = Enum.AnimationPriority.Action4  -- above everything
		track:Play(0)   -- no fade-in; snappy hit feedback
		-- Auto-stop after it finishes so it doesn't hold the last frame
		track.Stopped:Connect(function() track:Destroy() end)
	else
		-- ── Swing animation (attacker) — normal path ─────────────────────────
		local track = _getTrack(character, animId)
		if not track then return end

		-- Stop conflicting swing anims on rapid combos
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

-- ═══════════════════════════════════════════════════════════════════════════════
--  SERVER → CLIENT: HIT CONFIRM  (highlight + sound + shake)
--  Payload: attacker: Player, victim: Player, comboIndex: number
-- ═══════════════════════════════════════════════════════════════════════════════

RE_HitConfirm.OnClientEvent:Connect(function(attacker: Player, victim: Player, comboIndex: number)
	-- ── 1. Red highlight on victim (every client renders this) ───────────────
	local victimChar = victim.Character
	if victimChar then
		_flashHighlight(victimChar)
	end

	-- ── 2. Hit sound + camera shake — ONLY on the attacker's own client ───────
	if attacker ~= LocalPlayer then return end

	_playHitSound(comboIndex)
	_triggerCameraShake(comboIndex)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  CHARACTER LIFECYCLE
-- ═══════════════════════════════════════════════════════════════════════════════

local function _onCharacterAdded(character: Model)
	_clearCache(character)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then _clearCache(character) end
	end)
end

LocalPlayer.CharacterAdded:Connect(_onCharacterAdded)
if LocalPlayer.Character then
	_onCharacterAdded(LocalPlayer.Character)
end