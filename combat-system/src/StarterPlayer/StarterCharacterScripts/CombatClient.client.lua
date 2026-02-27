--[[
	CombatClient.lua  (CLIENT — LocalScript inside StarterPlayerScripts or StarterCharacterScripts)
	
	Responsibilities:
	  • Listen for mouse / tap input → fire UsedM1 remote (intent only, no hit data)
	  • Receive ApplyHitEffect from server → play correct animation on correct character
	  • Play swing sound locally for the attacker
	  • NO hit detection, NO damage, NO validation — that's all server's job.

	Place in: StarterPlayerScripts/CombatClient  (or StarterCharacterScripts)
]]

-- ── Services ──────────────────────────────────────────────────────────────────
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- ── Shared config ─────────────────────────────────────────────────────────────
local Shared         = ReplicatedStorage:WaitForChild("Shared")
local CombatSettings = require(Shared:WaitForChild("CombatSettings"))

-- ── Remotes ───────────────────────────────────────────────────────────────────
local RemotesFolder     = ReplicatedStorage:WaitForChild("Remotes")
local RE_UsedM1         = RemotesFolder:WaitForChild(CombatSettings.Remotes.UsedM1)        :: RemoteEvent
local RE_ApplyHitEffect = RemotesFolder:WaitForChild(CombatSettings.Remotes.ApplyHitEffect) :: RemoteEvent

-- ── Local state ───────────────────────────────────────────────────────────────
-- Client-side cooldown mirror: prevents spamming the remote before server responds.
-- The server always has final say; this just reduces needless network traffic.
local _lastM1Time = -math.huge
local ANIM_CACHE: { [string]: { [string]: AnimationTrack } } = {}

-- ── Animation Helpers ─────────────────────────────────────────────────────────

--[[
	Returns (or lazily creates) an AnimationTrack for the given animId on the given
	character's Animator.  Tracks are cached per character per animId.
]]
local function _getTrack(character: Model, animId: string): AnimationTrack?
	local animator: Animator? = character:FindFirstChildOfClass("Humanoid")
		and character:FindFirstChildOfClass("Humanoid"):FindFirstChildOfClass("Animator")
	if not animator then return nil end

	local charName = character.Name
	if not ANIM_CACHE[charName] then
		ANIM_CACHE[charName] = {}
	end

	if not ANIM_CACHE[charName][animId] then
		local anim    = Instance.new("Animation")
		anim.AnimationId = animId
		ANIM_CACHE[charName][animId] = animator:LoadAnimation(anim)
		anim:Destroy()  -- Animation instance not needed after loading
	end

	return ANIM_CACHE[charName][animId]
end

-- Clean up cache when a character is removed (respawn / leaving)
local function _clearCache(character: Model)
	ANIM_CACHE[character.Name] = nil
end

-- ── Sound helper ──────────────────────────────────────────────────────────────

local function _playSwingSound(comboIndex: number)
	local soundId = CombatSettings.Audio["M" .. tostring(comboIndex) .. "Sound"]
		or CombatSettings.Audio.M1Sound
	local sound = Instance.new("Sound")
	sound.SoundId  = soundId
	sound.Volume   = 0.8
	sound.RollOffMaxDistance = 40
	sound.Parent   = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
		or workspace
	sound:Play()
	task.delay(3, function() sound:Destroy() end)
end

-- ── Input → Intent ────────────────────────────────────────────────────────────

local function _onM1Input()
	-- Client-side spam guard (mirrors server cooldown roughly)
	local now = os.clock()
	if now - _lastM1Time < CombatSettings.Cooldowns.M1 then return end
	_lastM1Time = now

	-- Ensure we have a living character
	local char = LocalPlayer.Character
	if not char then return end
	local hum: Humanoid? = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end

	-- Send INTENT only — no target info, no hit data
	RE_UsedM1:FireServer()
end

-- Desktop: left mouse button
UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		_onM1Input()
	end
end)

-- Mobile / gamepad: you can also listen for touch or Thumbstick here later.

-- ── Server → Client: Play animations ─────────────────────────────────────────
--[[
	Server fires ApplyHitEffect(targetPlayer, animKey, comboIndex).
	  • If animKey is "M1"–"M5" the target is the ATTACKER (swing anim).
	  • If animKey is "HitReaction*" the target is the VICTIM.
	  • If animKey is "BlockingHitReaction*" the target is the BLOCKER.
]]
RE_ApplyHitEffect.OnClientEvent:Connect(function(targetPlayer: Player, animKey: string, comboIndex: number)
	local character = targetPlayer.Character
	if not character then return end

	-- Resolve the animId from CombatSettings
	local animEntry = CombatSettings.Animations[animKey]
	local animId: string

	if type(animEntry) == "table" then
		animId = animEntry.Id  -- M1–M5 entries are tables with .Id
	elseif type(animEntry) == "string" then
		animId = animEntry     -- HitReaction*, Block entries are plain strings
	else
		return
	end

	local track = _getTrack(character, animId)
	if not track then return end

	-- Stop any conflicting swing animation before playing the new one
	-- (avoids blending issues on rapid combos)
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

	-- Play swing sound if this is the attacker and it is our local player
	if targetPlayer == LocalPlayer and animKey:sub(1, 1) == "M" then
		_playSwingSound(comboIndex)
	end
end)

-- ── Character lifecycle ───────────────────────────────────────────────────────

local function _onCharacterAdded(character: Model)
	_clearCache(character)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			_clearCache(character)
		end
	end)
end

LocalPlayer.CharacterAdded:Connect(_onCharacterAdded)
if LocalPlayer.Character then
	_onCharacterAdded(LocalPlayer.Character)
end
