--[[
	Abilities/Fireball.lua
	Server-authoritative hitscan projectile with Burn status.
	Server raycasts — client only plays the visual.
]]

local Fireball = {}
Fireball.__index = Fireball

-- ─── Ability Definition ───────────────────────────────────────────────────────

Fireball.Name       = "Fireball"
Fireball.Cooldown   = 6
Fireball.Stamina    = 25
Fireball.BaseDamage = 30
Fireball.Range      = 80
Fireball.BurnTime   = 3

-- ─── Execute ──────────────────────────────────────────────────────────────────

function Fireball:Execute(player: Player, inputData: {}, ctx: {})
	local char = player.Character
	if not char then return end

	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local attackerState = ctx.states[player.UserId]
	local origin    = root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1.5, 0)
	local direction = root.CFrame.LookVector

	-- Server-side raycast hit detection
	local victim = ctx.hitbox:CastRay({
		Caster    = player,
		Origin    = origin,
		Direction = direction,
		Range     = Fireball.Range,
	})

	-- Tell clients to play the projectile animation regardless of hit
	ctx.fireVfx("FireballEffect", {
		CasterId  = player.UserId,
		Origin    = origin,
		Direction = direction,
		Hit       = victim ~= nil,
		HitPos    = victim and victim.Character
			and victim.Character:FindFirstChild("HumanoidRootPart")
			and victim.Character.HumanoidRootPart.Position
			or (origin + direction * Fireball.Range),
	})

	if not victim then return end

	local victimState = ctx.states[victim.UserId]
	if not victimState then return end

	-- Apply damage
	local result = ctx.damage:Apply(attackerState, victimState, victim, {
		Base    = Fireball.BaseDamage,
		CanCrit = true,
	})

	if result then
		-- Apply burn DoT
		ctx.status:Apply(victim, victimState, "Burn", Fireball.BurnTime)
	end
end

return Fireball