--[[
	AnimationController.lua
	Uses rbxassetid:// format — works in Studio test mode.
--]]

local AnimationController = {}
AnimationController.__index = AnimationController

local ANIM_IDS = {
	idle  = "rbxassetid://180435571",
	walk  = "rbxassetid://180426354",
	run   = "rbxassetid://180426354",
	jump  = "rbxassetid://125750702",
	fall  = "rbxassetid://180436148",
	climb = "rbxassetid://180436334",
	swim  = "rbxassetid://180435613",
	Attack = "rbxassetid://103696146273479",
	Hurt   = "rbxassetid://180435397",
	Death  = "rbxassetid://180436148",
}

local LOOPED = { idle=true, walk=true, run=true, climb=true, swim=true }

local PRIORITY = {
	idle   = Enum.AnimationPriority.Idle,
	walk   = Enum.AnimationPriority.Movement,
	run    = Enum.AnimationPriority.Movement,
	jump   = Enum.AnimationPriority.Movement,
	fall   = Enum.AnimationPriority.Movement,
	climb  = Enum.AnimationPriority.Movement,
	swim   = Enum.AnimationPriority.Movement,
	Attack = Enum.AnimationPriority.Action,
	Hurt   = Enum.AnimationPriority.Action,
	Death  = Enum.AnimationPriority.Action4,
}

local FADE = {
	idle=0.2, walk=0.15, run=0.15, jump=0.1, fall=0.3, climb=0.1, swim=0.2,
	Attack=0.05, Hurt=0.05, Death=0.1,
}

function AnimationController.new(npc: Model)
	local self = setmetatable({}, AnimationController)
	self.NPC      = npc
	self.Humanoid = npc:FindFirstChildOfClass("Humanoid") :: Humanoid
	self.Animator = self.Humanoid:FindFirstChildOfClass("Animator")
	if not self.Animator then
		self.Animator = Instance.new("Animator")
		self.Animator.Parent = self.Humanoid
	end
	self._tracks  = {}
	self._current = nil
	self._dead    = false
	self:_loadAll()
	return self
end

function AnimationController:SetLocomotion(animName: string)
	if self._dead then return end
	if self._current == animName then return end
	local track = self._tracks[animName]
	if not track then return end
	if self._current and self._tracks[self._current] then
		self._tracks[self._current]:Stop(FADE[animName] or 0.15)
	end
	track:Play(FADE[animName] or 0.15)
	self._current = animName
end

function AnimationController:PlayAction(animName: string): AnimationTrack?
	if self._dead and animName ~= "Death" then return nil end
	local track = self._tracks[animName]
	if not track then return nil end
	if track.IsPlaying then track:Stop(0) end
	track:Play(FADE[animName] or 0.05)
	if animName == "Death" then
		self._dead = true
		if self._current and self._tracks[self._current] then
			self._tracks[self._current]:Stop(0.2)
			self._current = nil
		end
	end
	return track
end

function AnimationController:OnDeath() self:PlayAction("Death") end
function AnimationController:IsPlayingAction(animName: string): boolean
	local t = self._tracks[animName]
	return t ~= nil and t.IsPlaying
end
function AnimationController:StopAll()
	for _, t in pairs(self._tracks) do if t.IsPlaying then t:Stop(0) end end
	self._current = nil
end
function AnimationController:Destroy()
	self:StopAll()
	self._tracks = {}
end

function AnimationController:_loadAll()
	for name, id in pairs(ANIM_IDS) do
		local ok, result = pcall(function()
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local track = self.Animator:LoadAnimation(anim)
			track.Priority = PRIORITY[name] or Enum.AnimationPriority.Movement
			track.Looped   = LOOPED[name] or false
			self._tracks[name] = track
		end)
		if not ok then
			warn("[AnimationController] Failed to load:", name, result)
		end
	end
	print("[AnimationController] Loaded R6 anims for", self.NPC.Name)
end

return AnimationController