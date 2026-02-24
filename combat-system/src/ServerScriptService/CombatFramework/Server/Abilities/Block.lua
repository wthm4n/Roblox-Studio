--[[
	Abilities/Block.lua
	Starts blocking. Pairs with BlockRelease.lua.
	Blocked hits deal chip damage and drain the guard meter.
	If guard meter hits 0: GuardBreak is applied.
]]

local Block = {}
Block.__index = Block

Block.Name     = "Block"
Block.Cooldown = 0
Block.Stamina  = 0

function Block:Execute(player: Player, inputData: {}, ctx: {})
	local state = ctx.states[player.UserId]
	if not state then return end
	if state.GuardBroken then return end
	if not state:CanBlock() then return end

	state:SetState("Blocking")
	ctx.fireVfx("BlockStart", { PlayerId = player.UserId })
end

return Block