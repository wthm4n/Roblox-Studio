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

-- ── Local state ───────────────────────────────────────────────────────────────
local _lastM1Time = -math.huge
local ANIM_CACHE: { [string]: { [string]: AnimationTrack } } = {}

-- Track active highlight per character so we don't stack them
local _activeHighlights: { [Model]: Highlight } = {}

-- ── Stun state (local player only) ────────────────────────────────────────────
-- Whether THIS local client is currently stunned (for input blocking + UI).
local _locallyStunned = false
local _stunGui: ScreenGui? = nil   -- persistent stun indicator GUI

-- Tech roll cooldown mirror (client-side; server has authoritative check too)
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
--  STUN INDICATOR UI  (shown only to the local player when they're stunned)
-- ═══════════════════════════════════════════════════════════════════════════════
--  Simple "STUNNED — Press Q to tech roll" label in the centre of the screen.
--  Destroy it on release. Pure Roblox UI, no extra assets needed.

local function _createStunGui(): ScreenGui
	local gui        = Instance.new("ScreenGui")
	gui.Name         = "StunIndicator"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame           = Instance.new("Frame", gui)
	frame.Name            = "Container"
	frame.Size            = UDim2.new(0, 300, 0, 60)
	frame.Position        = UDim2.new(0.5, -150, 0.72, 0)
	frame.BackgroundColor3 = Color3.fromRGB(200, 30, 30)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner", frame)
	corner.CornerRadius = UDim.new(0, 8)

	local label            = Instance.new("TextLabel", frame)
	label.Name             = "Label"
	label.Size             = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3       = Color3.new(1, 1, 1)
	label.TextScaled       = true
	label.Font             = Enum.Font.GothamBold
	label.Text             = ("STUNNED  —  Press %s to escape"):format(
		CombatSettings.Stun.TechRoll.Key
	)

	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	return gui
end

local function _showStunGui()
	if _stunGui then _stunGui:Destroy() end
	_stunGui = _createStunGui()
end

local function _hideStunGui()
	if _stunGui then
		_stunGui:Destroy()
		_stunGui = nil
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
--  STUN REMOTE HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- StunApplied: victim: Player, duration: number
RE_StunApplied.OnClientEvent:Connect(function(victim: Player, duration: number)
	-- Only show the indicator on our own screen
	if victim ~= LocalPlayer then return end

	_locallyStunned = true
	_showStunGui()

	-- Safety: hide the GUI after duration even if StunReleased somehow doesn't fire
	task.delay(duration + 0.2, function()
		if _locallyStunned then
			_locallyStunned = false
			_hideStunGui()
		end
	end)
end)

-- StunReleased: victim: Player, reason: string
RE_StunReleased.OnClientEvent:Connect(function(victim: Player, reason: string)
	if victim ~= LocalPlayer then return end

	_locallyStunned = false
	_hideStunGui()

	-- If it was a tech roll, play the roll animation
	if reason == "techroll" then
		local char = LocalPlayer.Character
		if char then
			-- You can add a dedicated TechRoll animation ID to MovementSettings later.
			-- For now we just hide the stun UI — the backward velocity is visual enough.
		end
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
--  TECH ROLL INPUT  (victim presses Q while stunned)
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
--  SERVER → CLIENT: ANIMATION PLAYBACK  (swing + hit reactions)
-- ═══════════════════════════════════════════════════════════════════════════════

RE_ApplyHitEffect.OnClientEvent:Connect(function(targetPlayer: Player, animKey: string, comboIndex: number)
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

	local track = _getTrack(character, animId)
	if not track then return end

	-- Stop previous swing anims to prevent blend-fighting on rapid combos
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