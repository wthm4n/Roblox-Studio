--[[
	CombatClient.lua  (CLIENT)

	ARCHITECTURE — "Optimistic Client" (how TSB / JJS work):
	─────────────────────────────────────────────────────────
	OLD (laggy):
	  Click → FireServer → wait RTT → server task.delay(HitFrame)
	       → FireAllClients(anim) → client FINALLY sees animation
	  Result: anim starts 200-500ms after click. Feels broken.

	NEW (instant):
	  Click → play anim + sound + camera effects IMMEDIATELY (frame 0)
	       → FireServer() in parallel  ← server validates + deals damage only
	  Server → FireAllClients(victim, reactionAnim) for hit reactions + highlight
	  Result: attacker sees zero latency. Server is still fully authoritative.
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ── Shared config ─────────────────────────────────────────────────────────────
local Shared         = ReplicatedStorage:WaitForChild("Shared")
local CombatSettings = require(Shared:WaitForChild("CombatSettings"))

-- ── Remotes ───────────────────────────────────────────────────────────────────
local RemotesFolder     = ReplicatedStorage:WaitForChild("Remotes")
local RE_UsedM1         = RemotesFolder:WaitForChild(CombatSettings.Remotes.UsedM1)
local RE_ApplyHitEffect = RemotesFolder:WaitForChild(CombatSettings.Remotes.ApplyHitEffect)
local RE_HitConfirm     = RemotesFolder:WaitForChild(CombatSettings.Remotes.HitConfirm)
local RE_StunApplied    = RemotesFolder:WaitForChild(CombatSettings.Remotes.StunApplied)
local RE_StunReleased   = RemotesFolder:WaitForChild(CombatSettings.Remotes.StunReleased)
local RE_TechRoll       = RemotesFolder:WaitForChild(CombatSettings.Remotes.TechRoll)
local RE_Ragdoll        = RemotesFolder:WaitForChild(CombatSettings.Remotes.Ragdoll)
local RE_RagdollEnd     = RemotesFolder:WaitForChild(CombatSettings.Remotes.RagdollEnd)

-- ── State ─────────────────────────────────────────────────────────────────────
local _comboIndex       = 0
local _lastM1Time       = -math.huge
local _locallyStunned   = false
local _locallyRagdolled = false
local _lastTechRoll     = -math.huge
local TECH_ROLL_KEY     = Enum.KeyCode[CombatSettings.Stun.TechRoll.Key] or Enum.KeyCode.Q

-- ── Caches ────────────────────────────────────────────────────────────────────
local ANIM_CACHE: { [string]: { [string]: AnimationTrack } } = {}
local _activeHighlights: { [Model]: Highlight } = {}

-- ══════════════════════════════════════════════════════════════════════════════
--  LOCAL PLAYER ANIMATOR
--  Drives the local player's swing anims directly, with zero server wait.
-- ══════════════════════════════════════════════════════════════════════════════

local _localAnimator: Animator? = nil
local _localTracks: { [string]: AnimationTrack } = {}

local function _setupLocalAnimator(character: Model)
	_localTracks   = {}
	_localAnimator = nil
	local hum = character:WaitForChild("Humanoid")
	_localAnimator = hum:WaitForChild("Animator") :: Animator
end

local function _getLocalTrack(animId: string): AnimationTrack?
	if not _localAnimator then return nil end
	if _localTracks[animId] then return _localTracks[animId] end
	local anim       = Instance.new("Animation")
	anim.AnimationId = animId
	local track      = _localAnimator:LoadAnimation(anim)
	anim:Destroy()
	_localTracks[animId] = track
	return track
end

local function _preloadSwingAnims()
	for i = 1, 5 do
		local data = CombatSettings.Animations["M" .. i]
		if data and data.Id then _getLocalTrack(data.Id) end
	end
end

local function _stopAllSwingAnims()
	for i = 1, 5 do
		local data = CombatSettings.Animations["M" .. i]
		if data and data.Id then
			local t = _localTracks[data.Id]
			if t and t.IsPlaying then t:Stop(0.05) end
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  REMOTE PLAYER ANIMATOR  (other players' anims + hit reactions)
-- ══════════════════════════════════════════════════════════════════════════════

local function _getTrack(character: Model, animId: string): AnimationTrack?
	local hum      = character:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return nil end
	local name = character.Name
	if not ANIM_CACHE[name] then ANIM_CACHE[name] = {} end
	if not ANIM_CACHE[name][animId] then
		local anim       = Instance.new("Animation")
		anim.AnimationId = animId
		ANIM_CACHE[name][animId] = animator:LoadAnimation(anim)
		anim:Destroy()
	end
	return ANIM_CACHE[name][animId]
end

local function _clearCache(character: Model)
	if _activeHighlights[character] then
		_activeHighlights[character]:Destroy()
		_activeHighlights[character] = nil
	end
	ANIM_CACHE[character.Name] = nil
end

-- ══════════════════════════════════════════════════════════════════════════════
--  FOV KICK
-- ══════════════════════════════════════════════════════════════════════════════

local FOV_BASE        = 70
local _fovCurrent     = FOV_BASE
local _fovTarget      = FOV_BASE
local _fovReturnSpeed = 12

local FOV_PROFILES = {
	[1]={Kick=6,ReturnSpeed=14}, [2]={Kick=7,ReturnSpeed=13},
	[3]={Kick=8,ReturnSpeed=12}, [4]={Kick=10,ReturnSpeed=11},
	[5]={Kick=14,ReturnSpeed=9},
}

local function _triggerFOVKick(idx: number)
	local p = FOV_PROFILES[idx] or FOV_PROFILES[1]
	_fovCurrent = FOV_BASE + p.Kick; _fovTarget = FOV_BASE
	_fovReturnSpeed = p.ReturnSpeed; Camera.FieldOfView = _fovCurrent
end

local function _tickFOV(dt: number)
	if math.abs(_fovCurrent - _fovTarget) < 0.05 then
		_fovCurrent = _fovTarget; Camera.FieldOfView = _fovCurrent; return
	end
	_fovCurrent = _fovCurrent + (_fovTarget - _fovCurrent) * math.min(1, dt * _fovReturnSpeed)
	Camera.FieldOfView = _fovCurrent
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CAMERA PUNCH  (spring)
-- ══════════════════════════════════════════════════════════════════════════════

local _punchOffset=0; local _punchVelocity=0; local _punchApplied=0
local PUNCH_K=280; local PUNCH_D=22
local PUNCH_PROFILES={[1]=0.18,[2]=0.20,[3]=0.24,[4]=0.30,[5]=0.45}

local function _triggerCameraPunch(idx: number)
	_punchVelocity = _punchVelocity + (PUNCH_PROFILES[idx] or 0.18) * 60
end

local function _tickCameraPunch(dt: number)
	local f = (-PUNCH_K * _punchOffset) + (-PUNCH_D * _punchVelocity)
	_punchVelocity = _punchVelocity + f * dt
	_punchOffset   = math.clamp(_punchOffset + _punchVelocity * dt, -2, 2)
	local delta = _punchOffset - _punchApplied; _punchApplied = _punchOffset
	if math.abs(delta) > 0.0001 then
		Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, -delta)
	end
	if math.abs(_punchOffset) < 0.0005 and math.abs(_punchVelocity) < 0.001 then
		if math.abs(_punchApplied) > 0.0001 then
			Camera.CFrame = Camera.CFrame * CFrame.new(0, 0, _punchApplied)
		end
		_punchOffset=0; _punchVelocity=0; _punchApplied=0
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
--  CAMERA SHAKE
-- ══════════════════════════════════════════════════════════════════════════════

local _shakePower=0; local _shakeFreq=18; local _shakeTimer=0; local _shakeDurLeft=0

local function _triggerCameraShake(idx: number)
	local p = CombatSettings.CameraShake[idx] or CombatSettings.CameraShake[1]
	_shakePower = math.max(_shakePower, p.Magnitude)
	_shakeFreq  = p.Frequency; _shakeDurLeft = p.Duration; _shakeTimer = 0
end

-- ══════════════════════════════════════════════════════════════════════════════
--  HIT SOUND
-- ══════════════════════════════════════════════════════════════════════════════

local function _playHitSound(idx: number)
	local id  = CombatSettings.Audio["M"..idx.."Sound"] or CombatSettings.Audio.M1Sound
	local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local snd = Instance.new("Sound")
	snd.SoundId=id; snd.Volume=1.0
	snd.RollOffMode=Enum.RollOffMode.InverseTapered; snd.RollOffMaxDistance=50
	snd.Parent = hrp or workspace; snd:Play()
	game:GetService("Debris"):AddItem(snd, 3)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  RED HIGHLIGHT
-- ══════════════════════════════════════════════════════════════════════════════

local HL = CombatSettings.HitHighlight

local function _flashHighlight(char: Model)
	local ex = _activeHighlights[char]
	if ex then ex:Destroy() end
	local hl = Instance.new("Highlight")
	hl.FillColor=HL.FillColor; hl.OutlineColor=HL.OutlineColor
	hl.FillTransparency=HL.FillTransparency; hl.OutlineTransparency=HL.OutlineTransparency
	hl.Adornee=char; hl.DepthMode=Enum.HighlightDepthMode.Occluded; hl.Parent=char
	_activeHighlights[char] = hl
	task.delay(HL.Duration, function()
		if _activeHighlights[char] == hl then hl:Destroy(); _activeHighlights[char]=nil end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
--  M1 INPUT — zero server wait, everything is instant
-- ══════════════════════════════════════════════════════════════════════════════

local function _onM1Input()
	if _locallyStunned or _locallyRagdolled then return end

	-- Rate-limit FireServer calls (mirrors server cooldown, prevents flooding)
	local now = os.clock()
	if now - _lastM1Time < CombatSettings.Cooldowns.M1 then return end
	_lastM1Time = now

	local char = LocalPlayer.Character
	if not char or not _localAnimator then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Advance combo client-side (mirrors server logic exactly)
	_comboIndex = (_comboIndex % CombatSettings.Combo.MaxHits) + 1
	local animKey  = "M" .. _comboIndex
	local animData = CombatSettings.Animations[animKey]
	if not animData then return end

	-- ── INSTANT: anim + sound + camera — all happen frame 0 of click ─────────
	_stopAllSwingAnims()
	local track = _getLocalTrack(animData.Id)
	if track then
		track.Priority = Enum.AnimationPriority.Action3
		track:Play(0.05)
		task.delay(animData.Duration + 0.05, function()
			if track.IsPlaying then track:Stop(0.1) end
		end)
	end

	_playHitSound(_comboIndex)
	_triggerCameraShake(_comboIndex)
	_triggerFOVKick(_comboIndex)
	_triggerCameraPunch(_comboIndex)

	-- ── ASYNC: server validates and deals damage in background ────────────────
	RE_UsedM1:FireServer()
end

-- ══════════════════════════════════════════════════════════════════════════════
--  INPUT
-- ══════════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		_onM1Input()
	end
	if input.KeyCode == TECH_ROLL_KEY and _locallyStunned then
		local now = os.clock()
		if now - _lastTechRoll >= CombatSettings.Stun.TechRoll.Cooldown then
			_lastTechRoll = now; RE_TechRoll:FireServer()
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  SERVER → CLIENT: ApplyHitEffect
--  For LOCAL player: only hit reactions (swing anim already playing locally)
--  For REMOTE players: swing anims + hit reactions
-- ══════════════════════════════════════════════════════════════════════════════

local REACTION_KEYS = {
	"HitReaction1","HitReaction2","HitReaction3","HitReaction4","HitReaction5",
	"BlockingHitReaction1","BlockingHitReaction2","BlockingHitReaction3",
	"BlockingHitReaction4","BlockingHitReaction5"
}

RE_ApplyHitEffect.OnClientEvent:Connect(function(targetPlayer: Player, animKey: string, _ci: number)
	local character = targetPlayer.Character
	if not character then return end

	-- Skip swing anims for local player — already playing from _onM1Input
	local isSwing = animKey:sub(1,1) == "M" and tonumber(animKey:sub(2)) ~= nil
	if isSwing and targetPlayer == LocalPlayer then return end

	local animEntry = CombatSettings.Animations[animKey]
	local animId: string? = type(animEntry)=="table" and animEntry.Id or (type(animEntry)=="string" and animEntry) or nil
	if not animId then return end

	local isReaction = animKey:sub(1,11) == "HitReaction" or animKey:sub(1,18) == "BlockingHitReaction"

	if isReaction then
		local hum = character:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if not animator then return end
		-- Stop conflicting reactions
		for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
			local id = t.Animation and t.Animation.AnimationId or ""
			for _, k in ipairs(REACTION_KEYS) do
				local d = CombatSettings.Animations[k]
				if type(d)=="string" and d==id then t:Stop(0) break end
			end
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = animId
		local t = animator:LoadAnimation(anim); anim:Destroy()
		t.Priority = Enum.AnimationPriority.Action4; t:Play(0)
		t.Stopped:Connect(function() t:Destroy() end)
	else
		-- Remote player swing
		local t = _getTrack(character, animId)
		if not t then return end
		for i = 1, 5 do
			local pk = "M"..i; local pd = CombatSettings.Animations[pk]
			if pd and pk ~= animKey then
				local pid = type(pd)=="table" and pd.Id or pd
				local prev = _getTrack(character, pid)
				if prev and prev.IsPlaying then prev:Stop(0.05) end
			end
		end
		t:Play(0.05)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  SERVER → CLIENT: HitConfirm  (highlight only — all feedback already fired)
-- ══════════════════════════════════════════════════════════════════════════════

RE_HitConfirm.OnClientEvent:Connect(function(_attacker: Player, victim: Player, _ci: number)
	local vc = victim.Character
	if vc then _flashHighlight(vc) end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  STUN / RAGDOLL
-- ══════════════════════════════════════════════════════════════════════════════

RE_StunApplied.OnClientEvent:Connect(function(victim: Player, _d: number)
	if victim == LocalPlayer then _locallyStunned = true end
end)

RE_StunReleased.OnClientEvent:Connect(function(victim: Player, _r: string)
	if victim == LocalPlayer then _locallyStunned = false end
end)

local function _setAnimateEnabled(char: Model, enabled: boolean)
	local s = char:FindFirstChild("Animate")
	if s and s:IsA("LocalScript") then s.Disabled = not enabled end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local anim = hum and hum:FindFirstChildOfClass("Animator")
	if anim and not enabled then
		for _, t in ipairs(anim:GetPlayingAnimationTracks()) do t:Stop(0) end
	end
end

RE_Ragdoll.OnClientEvent:Connect(function(victim: Player, _active: boolean)
	local char = victim.Character; if not char then return end
	_setAnimateEnabled(char, false)
	if victim == LocalPlayer then
		_locallyRagdolled=true; _locallyStunned=true
		_stopAllSwingAnims()
	end
end)

RE_RagdollEnd.OnClientEvent:Connect(function(victim: Player)
	local char = victim.Character; if not char then return end
	_setAnimateEnabled(char, true)
	if victim == LocalPlayer then
		_locallyRagdolled=false; _locallyStunned=false
		_comboIndex = 0  -- re-sync with server after ragdoll recovery
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  RENDER LOOP
-- ══════════════════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function(dt: number)
	if _shakeDurLeft > 0 then
		_shakeDurLeft = _shakeDurLeft - dt; _shakeTimer = _shakeTimer + dt
		local prog = math.max(0,_shakeDurLeft) / math.max(0.001, _shakeTimer+_shakeDurLeft)
		local mag  = _shakePower * prog
		local ox = math.sin(_shakeTimer*_shakeFreq*math.pi*2) * mag
		local oy = math.sin(_shakeTimer*_shakeFreq*math.pi*2.3+1.1) * mag
		Camera.CFrame = Camera.CFrame * CFrame.new(ox, oy, 0)
	end
	_tickFOV(dt)
	_tickCameraPunch(dt)
end)

-- ══════════════════════════════════════════════════════════════════════════════
--  CHARACTER SETUP
-- ══════════════════════════════════════════════════════════════════════════════

local function _onCharacterAdded(character: Model)
	_clearCache(character)
	_comboIndex=0; _lastM1Time=-math.huge
	_fovCurrent=FOV_BASE; _fovTarget=FOV_BASE; _fovReturnSpeed=12
	_punchOffset=0; _punchVelocity=0; _punchApplied=0
	Camera.FieldOfView = FOV_BASE

	_setupLocalAnimator(character)
	_preloadSwingAnims()

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then _clearCache(character) end
	end)
end

LocalPlayer.CharacterAdded:Connect(_onCharacterAdded)
if LocalPlayer.Character then _onCharacterAdded(LocalPlayer.Character) end