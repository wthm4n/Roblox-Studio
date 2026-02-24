--[[
	Abilities/BlockRelease.lua
	Ends blocking and starts guard regen.
	Client fires "BlockRelease" when the block key is released.
]]

local BlockRelease = {}
BlockRelease.__index = BlockRelease

BlockRelease.Name     = "BlockRelease"
BlockRelease.Cooldown = 0
BlockRelease.Stamina  = 0

local GUARD_REGEN_RATE = 8  -- guard points restored per second

function BlockRelease:Execute(player: Player, inputData: {}, ctx: {})
	local state = ctx.states[player.UserId]
	if not state then return end
	if not state:Is("Blocking") then return end

	state:SetState("Idle")
	ctx.fireVfx("BlockEnd", { PlayerId = player.UserId })

	-- Regen guard meter while not blocking
	task.spawn(function()
		while not state:Is("Blocking") and state.GuardMeter < state.MaxGuardMeter do
			if state:Is("Dead") then break end
			state.GuardMeter = math.clamp(
				state.GuardMeter + GUARD_REGEN_RATE * 0.1,
				0,
				state.MaxGuardMeter
			)
			task.wait(0.1)
		end
	end)
end

return BlockRelease