--[[
	ComboService.lua
	Tracks per-player M1 combo chains, enforces combo windows,
	and returns the correct hit data for each combo stage.
]]

local ComboService = {}
ComboService.__index = ComboService

-- ─── Combo Config ─────────────────────────────────────────────────────────────

local COMBO_WINDOW = 0.85  -- seconds after a hit to continue the chain
local MAX_COMBO    = 4

-- Per-index hit data. Extend or override per character/weapon.
local DEFAULT_COMBO_DATA: { { Damage: number, Stun: number, Knockback: number, Ragdoll: boolean? } } = {
	[1] = { Damage = 8,  Stun = 0.20, Knockback = 0   },
	[2] = { Damage = 8,  Stun = 0.20, Knockback = 0   },
	[3] = { Damage = 10, Stun = 0.30, Knockback = 0   },
	[4] = { Damage = 15, Stun = 0.50, Knockback = 60, Ragdoll = true },
}

-- ─── Constructor ──────────────────────────────────────────────────────────────

function ComboService.new()
	local self = setmetatable({}, ComboService)
	-- [userId] = { Index: number, LastHitClock: number }
	self._records = {}
	return self
end

-- ─── Internal ─────────────────────────────────────────────────────────────────

function ComboService:_GetRecord(player: Player)
	local id = player.UserId
	if not self._records[id] then
		self._records[id] = { Index = 0, LastHitClock = 0 }
	end
	return self._records[id]
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--[[
	Advance(player) -> comboData

	Call when a validated M1 lands.
	Returns the hit data table for this combo stage.
	Resets to 1 if the combo window has expired.
]]
function ComboService:Advance(player: Player, customData: {}?)
	local now    = os.clock()
	local record = self:_GetRecord(player)
	local data   = customData or DEFAULT_COMBO_DATA

	if (now - record.LastHitClock) <= COMBO_WINDOW and record.Index > 0 then
		record.Index = (record.Index % MAX_COMBO) + 1
	else
		record.Index = 1
	end

	record.LastHitClock = now
	return data[record.Index]
end

--[[
	GetIndex(player) -> number

	Current combo index without advancing it.
	Use this when you need the index for damage scaling before calling Advance.
]]
function ComboService:GetIndex(player: Player): number
	return self:_GetRecord(player).Index
end

--[[
	IsOnFinalHit(player) -> boolean

	Convenience check — true when the NEXT Advance() will be hit 4.
]]
function ComboService:IsOnFinalHit(player: Player): boolean
	return self:_GetRecord(player).Index >= MAX_COMBO - 1
end

--[[
	Reset(player)

	Force-reset the chain. Call on death, stun, or guard break.
]]
function ComboService:Reset(player: Player)
	local id = player.UserId
	self._records[id] = { Index = 0, LastHitClock = 0 }
end

-- Cleanup on leave
function ComboService:OnPlayerRemoving(player: Player)
	self._records[player.UserId] = nil
end

return ComboService
