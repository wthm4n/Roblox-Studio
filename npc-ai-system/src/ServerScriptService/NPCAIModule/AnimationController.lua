--[[
	AnimationController.lua
	
	Since the NPC already has Roblox's built-in "Animate" LocalScript,
	locomotion anims (idle, walk, run, swim, climb, jump) are handled
	automatically — no server code needed for those.

	This module only handles:
	  - Attack  (action anim, server-driven)
	  - Hurt    (action anim, server-driven)

	Both are fired via a RemoteEvent to the client so the Animate
	script doesn't fight with us.
--]]

local AnimationController = {}
AnimationController.__index = AnimationController

-- R6 action animation IDs
-- These play ON TOP of whatever Animate is doing (higher priority)
local ACTION_IDS = {
	Attack = "rbxassetid://115362763052284",  -- default punch/tool slash
	Hurt   = "rbxassetid://180435397",  -- default hit react
}

local FADE = {
	Attack = 0.05,
	Hurt   = 0.05,
}

-- ─── Constructor ───────────────────────────────────────────────────────────

function AnimationController.new(npc: Model)
	local self = setmetatable({}, AnimationController)

	self.NPC      = npc
	self.Humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.Animator = self.Humanoid:FindFirstChildOfClass("Animator")

	if not self.Animator then
		self.Animator = Instance.new("Animator")
		self.Animator.Parent = self.Humanoid
	end

	self._tracks = {}
	self._dead   = false

	self:_loadActions()
	return self
end

-- ─── Public ────────────────────────────────────────────────────────────────

-- Play Attack or Hurt on top of the Animate script
function AnimationController:PlayAction(animName: string): AnimationTrack?
	if self._dead and animName ~= "Death" then return nil end

	local track = self._tracks[animName]
	if not track then return nil end

	if track.IsPlaying then track:Stop(0) end
	track:Play(FADE[animName] or 0.05)
	return track
end

-- Call this on death — Animate handles the fall anim itself,
-- we just stop any action tracks
function AnimationController:OnDeath()
	self._dead = true
	for _, track in pairs(self._tracks) do
		if track.IsPlaying then track:Stop(0.1) end
	end
end

-- These are no-ops now — Animate handles locomotion automatically
-- Kept so NPCController doesn't error if it calls them
function AnimationController:SetLocomotion(_animName: string) end
function AnimationController:StopAll() end

function AnimationController:IsPlayingAction(animName: string): boolean
	local track = self._tracks[animName]
	return track ~= nil and track.IsPlaying
end

function AnimationController:Destroy()
	for _, track in pairs(self._tracks) do
		if track.IsPlaying then track:Stop(0) end
	end
	self._tracks = {}
end

-- ─── Private ───────────────────────────────────────────────────────────────

function AnimationController:_loadActions()
	-- Check for custom overrides in an Animations folder first
	local animFolder = self.NPC:FindFirstChild("Animations")

	for name, defaultId in pairs(ACTION_IDS) do
		local animObj = Instance.new("Animation")

		if animFolder then
			local custom = animFolder:FindFirstChild(name)
			animObj.AnimationId = (custom and custom:IsA("Animation"))
				and custom.AnimationId
				or defaultId
		else
			animObj.AnimationId = defaultId
		end

		local track = self.Animator:LoadAnimation(animObj)
		track.Priority = Enum.AnimationPriority.Action  -- always on top of Animate
		track.Looped   = false
		self._tracks[name] = track
	end

	print("[AnimationController] Action anims loaded for", self.NPC.Name,
		"(locomotion handled by Animate script)")
end

return AnimationController