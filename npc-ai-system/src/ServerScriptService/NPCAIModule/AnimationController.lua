--[[
	AnimationController.lua
	Manages all NPC animations. Plug into NPCController.

	How to set up animations in Studio:
	  1. Inside your NPC Model, create a folder called "Animations"
	  2. Inside that folder, add Animation objects with these exact names:
	       Idle
	       Walk
	       Run
	       Swim
	       Climb
	       Attack
	       Hurt
	       Death
	  3. Set each Animation's AnimationId to your animation asset ID
	     e.g.  rbxassetid://507766388

	The controller reads them automatically — no hardcoding IDs here.
--]]

local AnimationController = {}
AnimationController.__index = AnimationController

-- How fast each state blends in (seconds)
local FADE_IN = {
	Idle   = 0.2,
	Walk   = 0.15,
	Run    = 0.15,
	Swim   = 0.2,
	Climb  = 0.1,
	Attack = 0.05,
	Hurt   = 0.05,
	Death  = 0.1,
}

-- Which animations loop
local LOOPED = {
	Idle  = true,
	Walk  = true,
	Run   = true,
	Swim  = true,
	Climb = true,
}

-- Priority per animation
local PRIORITY = {
	Idle   = Enum.AnimationPriority.Idle,
	Walk   = Enum.AnimationPriority.Movement,
	Run    = Enum.AnimationPriority.Movement,
	Swim   = Enum.AnimationPriority.Movement,
	Climb  = Enum.AnimationPriority.Movement,
	Attack = Enum.AnimationPriority.Action,
	Hurt   = Enum.AnimationPriority.Action,
	Death  = Enum.AnimationPriority.Action4,
}

-- ─── Constructor ───────────────────────────────────────────────────────────

function AnimationController.new(npc: Model)
	local self = setmetatable({}, AnimationController)

	self.NPC      = npc
	self.Humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.Animator = self.Humanoid:FindFirstChildOfClass("Animator") :: Animator

	-- If no Animator exists, create one
	if not self.Animator then
		self.Animator = Instance.new("Animator")
		self.Animator.Parent = self.Humanoid
	end

	self._tracks  = {}   -- { [animName]: AnimationTrack }
	self._current = nil  -- currently playing looped track name
	self._dead    = false

	-- Load all animations from the model's Animations folder
	self:_loadAnimations()

	return self
end

-- ─── Public API ────────────────────────────────────────────────────────────

--[[
	Play a looped state animation (Idle, Walk, Run, Swim, Climb).
	Smoothly crossfades from the previous state.
	Does nothing if already playing that animation.
--]]
function AnimationController:SetLocomotion(animName: string)
	if self._dead then return end
	if self._current == animName then return end

	local track = self._tracks[animName]
	if not track then return end

	-- Fade out previous
	if self._current then
		local prev = self._tracks[self._current]
		if prev and prev.IsPlaying then
			prev:Stop(FADE_IN[animName] or 0.15)
		end
	end

	track:Play(FADE_IN[animName] or 0.15)
	self._current = animName
end

--[[
	Play a one-shot animation (Attack, Hurt, Death).
	These don't affect _current locomotion — attack plays over walk etc.
	Returns the track so caller can connect .Stopped if needed.
--]]
function AnimationController:PlayAction(animName: string): AnimationTrack?
	if self._dead and animName ~= "Death" then return nil end

	local track = self._tracks[animName]
	if not track then return nil end

	if track.IsPlaying then
		track:Stop(0)
	end

	track:Play(FADE_IN[animName] or 0.05)

	if animName == "Death" then
		self._dead = true
		-- Stop all locomotion
		if self._current then
			local prev = self._tracks[self._current]
			if prev and prev.IsPlaying then
				prev:Stop(0.2)
			end
			self._current = nil
		end
	end

	return track
end

-- Stop everything immediately
function AnimationController:StopAll()
	for _, track in pairs(self._tracks) do
		if track.IsPlaying then
			track:Stop(0)
		end
	end
	self._current = nil
end

-- Check if an action animation is currently mid-play
function AnimationController:IsPlayingAction(animName: string): boolean
	local track = self._tracks[animName]
	return track ~= nil and track.IsPlaying
end

function AnimationController:Destroy()
	self:StopAll()
	self._tracks = {}
end

-- ─── Private ───────────────────────────────────────────────────────────────

function AnimationController:_loadAnimations()
	local animFolder = self.NPC:FindFirstChild("Animations")
	if not animFolder then
		warn("[AnimationController] No 'Animations' folder found in", self.NPC.Name,
			"— create a folder named 'Animations' inside the NPC model and add Animation objects.")
		return
	end

	local loaded = 0
	for _, animObj in ipairs(animFolder:GetChildren()) do
		if not animObj:IsA("Animation") then continue end

		local name  = animObj.Name
		local track = self.Animator:LoadAnimation(animObj)

		-- Apply settings
		track.Priority = PRIORITY[name] or Enum.AnimationPriority.Movement
		track.Looped   = LOOPED[name] or false

		self._tracks[name] = track
		loaded += 1
	end

	print(("[AnimationController] Loaded %d animations for %s"):format(loaded, self.NPC.Name))
end

return AnimationController