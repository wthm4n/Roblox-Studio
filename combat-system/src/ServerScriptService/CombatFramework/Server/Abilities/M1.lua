--[[
	Abilities/M1.lua
	4-hit melee combo chain with per-hit animations and hit-frame timing.
	Works for both players and NPCs.

	Animation data is passed in via ctx.animations (set this up in Init.server.lua
	by passing your CombatSettings.Animations table into the ctx).
	The server waits for the HitFrame before running the hitbox,
	matching visuals to actual hit detection.
]]

local M1 = {}
M1.__index = M1

M1.Name     = "M1"
M1.Cooldown = 0.35
M1.Stamina  = 0
M1.Range    = 8

-- Animation IDs per combo index — override via ctx.animations if needed
local DEFAULT_ANIMS = {
	[1] = { Id = "rbxassetid://108566685589624", Duration = 0.45, HitFrame = 0.15 },
	[2] = { Id = "rbxassetid://121076535244470", Duration = 0.45, HitFrame = 0.15 },
	[3] = { Id = "rbxassetid://118197196863834", Duration = 0.50, HitFrame = 0.20 },
	[4] = { Id = "rbxassetid://76404683651972",  Duration = 0.60, HitFrame = 0.25 },
}

local HIT_REACTIONS = {
	"rbxassetid://135435525629845",
	"rbxassetid://90491820229603",
	"rbxassetid://133746302611824",
	"rbxassetid://98605161276665",
	"rbxassetid://95965894669114",
}

local BLOCK_REACTIONS = {
	"rbxassetid://74809674784324",
	"rbxassetid://139217606379358",
	"rbxassetid://131983705093197",
	"rbxassetid://116379344332047",
	"rbxassetid://109762979660797",
}

local function GetAnimator(character: Model): Animator?
	local hum = character:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	return hum:FindFirstChildOfClass("Animator")
end

local function PlayAnim(character: Model, animId: string, priority: Enum.AnimationPriority?)
	local animator = GetAnimator(character)
	if not animator then return nil end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = animator:LoadAnimation(anim)
	track.Priority = priority or Enum.AnimationPriority.Action
	track:Play()
	anim:Destroy()  -- LoadAnimation clones internally, safe to destroy
	return track
end

function M1:Execute(player: Player?, inputData: {}, ctx: {})
	-- Resolve character — works for players and NPCs
	local char
	if player then
		char = player.Character
	elseif inputData.Character then
		char = inputData.Character  -- NPC passes their model here
	end
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- Advance combo
	local comboData  = ctx.combo:Advance(player)
	local comboIndex = ctx.combo:GetIndex(player)

	-- Pick animation for this hit
	local animData = (ctx.animations and ctx.animations["M" .. comboIndex]) or DEFAULT_ANIMS[comboIndex]

	-- Play attack animation on attacker
	if animData then
		task.spawn(function()
			PlayAnim(char, animData.Id)
		end)
	end

	-- Wait for hit frame before spawning hitbox
	-- This syncs damage with the visual swing
	local hitDelay = animData and animData.HitFrame or 0.15
	task.delay(hitDelay, function()
		if not char or not char.Parent then return end  -- character left mid-swing

		local attackerState = player and ctx.states[player.UserId]
		if not attackerState and player then return end

		-- Server hitbox in front of attacker
		local hitboxOrigin = root.CFrame * CFrame.new(0, 0, -(M1.Range / 2))
		local victims = ctx.hitbox:CreateMeleeHitbox({
			Caster = player,
			Caster_Character = char,  -- fallback for NPCs (no Player object)
			Origin = hitboxOrigin,
			Size   = Vector3.new(6, 6, M1.Range),
		})

		for _, victim in ipairs(victims) do
			local victimState = victim._isNPC
				and ctx.states[victim._npcId]
				or  ctx.states[victim.UserId]

			if not victimState then continue end

			local victimChar = victim._isNPC and victim.Character or
				(victim.Character)
			local victimRoot = victimChar and victimChar:FindFirstChild("HumanoidRootPart")

			-- Deal damage
			local result = ctx.damage:Apply(attackerState, victimState, victim, {
				Base       = comboData.Damage,
				ComboIndex = comboIndex,
				CanCrit    = true,
			})
			if not result then continue end

			-- Play hit reaction on victim (random from pool)
			if victimChar then
				task.spawn(function()
					if result.IsBlocked then
						local reactionId = BLOCK_REACTIONS[math.random(#BLOCK_REACTIONS)]
						PlayAnim(victimChar, reactionId)
					else
						local reactionId = HIT_REACTIONS[math.random(#HIT_REACTIONS)]
						PlayAnim(victimChar, reactionId)
					end
				end)
			end

			-- Stun
			if comboData.Stun > 0 and not result.IsBlocked then
				ctx.status:Apply(victim, victimState, "Stun", comboData.Stun)
			end

			-- Final hit knockback + ragdoll
			if comboData.Ragdoll and not result.IsBlocked then
				local dir = (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
				if victimRoot then
					victimRoot:ApplyImpulse(dir * comboData.Knockback + Vector3.new(0, 20, 0))
				end
				ctx.status:Apply(victim, victimState, "Ragdoll", 1.2)
				ctx.combo:Reset(player)
			end

			-- VFX to all clients
			ctx.fireVfx("HitEffect", {
				AttackerId = player and player.UserId,
				Position   = victimRoot and victimRoot.Position or root.Position,
				IsCrit     = result.IsCrit,
				IsBlocked  = result.IsBlocked,
				ComboIndex = comboIndex,
				IsFinal    = comboData.Ragdoll == true,
				Damage     = result.Final,
			})
		end
	end)
end

return M1