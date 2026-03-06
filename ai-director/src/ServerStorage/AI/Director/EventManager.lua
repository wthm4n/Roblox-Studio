-- EventManager.lua
-- Triggers special gameplay events: ambushes, elite drops, squad attacks.
-- Each event has its own cooldown and probability gate.

local EventManager = {}
EventManager.__index = EventManager

-- ──────────────────────────────────────────────
--  Event Definitions
-- ──────────────────────────────────────────────

local EVENTS = {
	ambush = {
		cooldown    = 60,    -- seconds between ambush events
		minStress   = 50,    -- minimum stress to trigger
		groupSize   = {4, 7} -- random range of enemies
	},
	eliteDrop = {
		cooldown    = 90,
		minStress   = 40,
	},
	squadAttack = {
		cooldown    = 45,
		minStress   = 35,
		groupSize   = {3, 5}
	},
	sniperSpawn = {
		cooldown    = 80,
		minStress   = 30,
	},
}

-- ──────────────────────────────────────────────
--  Constructor
-- ──────────────────────────────────────────────
function EventManager.new(spawnManager)
	assert(spawnManager, "[EventManager] spawnManager is required")

	local self = setmetatable({}, EventManager)

	self._spawnManager = spawnManager
	self._cooldowns    = {}    -- {eventName: lastFiredAt}
	self._eventLog     = {}    -- [{event, time, success}]
	self._listeners    = {}    -- event-name → {callbacks}
	self._enabled      = true

	-- Init cooldowns so all events are immediately available at session start
	for name, _ in pairs(EVENTS) do
		self._cooldowns[name] = -math.huge
	end

	return self
end

-- ──────────────────────────────────────────────
--  Internal Helpers
-- ──────────────────────────────────────────────

function EventManager:_isReady(eventName: string): boolean
	local def = EVENTS[eventName]
	if not def then return false end
	local lastFired = self._cooldowns[eventName] or -math.huge
	return (tick() - lastFired) >= def.cooldown
end

function EventManager:_markFired(eventName: string)
	self._cooldowns[eventName] = tick()
	table.insert(self._eventLog, {
		event = eventName,
		time  = tick(),
	})
end

function EventManager:_fire(eventName: string, ...)
	self:_markFired(eventName)
	local cbs = self._listeners[eventName] or {}
	for _, cb in ipairs(cbs) do pcall(cb, ...) end
end

local function randInt(min: number, max: number): number
	return math.random(min, max)
end

-- ──────────────────────────────────────────────
--  Core Gate
-- ──────────────────────────────────────────────

--[[
	TryTriggerEvent(stress: number, eventProbability: number)
	Called each Director tick. Rolls against probability then
	picks which ready event to fire based on stress conditions.
	Returns the name of the triggered event, or nil.
]]
function EventManager:TryTriggerEvent(stress: number, eventProbability: number): string?
	if not self._enabled then return nil end
	if math.random() > eventProbability then return nil end

	-- Collect eligible events
	local eligible = {}
	for name, def in pairs(EVENTS) do
		if self:_isReady(name) and stress >= def.minStress then
			table.insert(eligible, name)
		end
	end

	if #eligible == 0 then return nil end

	-- Pick one randomly
	local chosen = eligible[math.random(1, #eligible)]

	if chosen == "ambush" then
		self:TriggerAmbush(stress)
	elseif chosen == "eliteDrop" then
		self:TriggerEliteDrop()
	elseif chosen == "squadAttack" then
		self:TriggerSquadAttack()
	elseif chosen == "sniperSpawn" then
		self:TriggerSniperSpawn()
	end

	return chosen
end

-- ──────────────────────────────────────────────
--  Event Implementations
-- ──────────────────────────────────────────────

--[[
	TriggerAmbush()
	Spawns a large group of enemies simultaneously.
	Enemies are tagged for flanking positions if available.
]]
function EventManager:TriggerAmbush(stress: number)
	local def = EVENTS.ambush
	local count = randInt(def.groupSize[1], def.groupSize[2])

	-- Scale group size with stress
	local stressBonus = math.floor((stress - def.minStress) / 20)
	count = math.min(count + stressBonus, 10)

	warn(string.format("[EventManager] ⚠ AMBUSH — spawning %d enemies", count))
	local spawned = self._spawnManager:SpawnGroup(count, {"flank"})

	self:_fire("ambush", {count = count, spawned = spawned})
	return spawned
end

--[[
	TriggerEliteDrop()
	Forces an elite enemy spawn regardless of standard SpawnManager cooldown.
]]
function EventManager:TriggerEliteDrop()
	warn("[EventManager] ⚠ ELITE DROP")
	local model = self._spawnManager:SpawnElite(true)  -- forceSpawn = true
	self:_fire("eliteDrop", {model = model})
	return model
end

--[[
	TriggerSquadAttack()
	Spawns a coordinated squad of 3–5 enemies.
]]
function EventManager:TriggerSquadAttack()
	local def = EVENTS.squadAttack
	local count = randInt(def.groupSize[1], def.groupSize[2])

	warn(string.format("[EventManager] ⚠ SQUAD ATTACK — %d enemies", count))
	local spawned = self._spawnManager:SpawnGroup(count)

	self:_fire("squadAttack", {count = count, spawned = spawned})
	return spawned
end

--[[
	TriggerSniperSpawn()
	Spawns an elite in a high/far spawn point tagged "sniper".
]]
function EventManager:TriggerSniperSpawn()
	warn("[EventManager] ⚠ SNIPER SPAWN")

	-- Ask SpawnManager for a sniper-tagged point specifically
	local point = self._spawnManager:GetValidSpawnPoint({"sniper"})
	if not point then
		warn("[EventManager] No sniper spawn points available, skipping")
		self:_fire("sniperSpawn", {model = nil})
		return nil
	end

	local model = self._spawnManager:SpawnElite(true)
	self:_fire("sniperSpawn", {model = model, point = point})
	return model
end

-- ──────────────────────────────────────────────
--  Listener Registration
-- ──────────────────────────────────────────────

--[[
	OnEvent(eventName: string, callback: fn)
	Register a callback for a specific event type.
	callback receives an info table.
]]
function EventManager:OnEvent(eventName: string, callback)
	if not self._listeners[eventName] then
		self._listeners[eventName] = {}
	end
	table.insert(self._listeners[eventName], callback)
end

function EventManager:SetEnabled(enabled: boolean)
	self._enabled = enabled
end

-- ──────────────────────────────────────────────
--  Debug
-- ──────────────────────────────────────────────

function EventManager:GetCooldownStatus(): table
	local status = {}
	for name, def in pairs(EVENTS) do
		local elapsed  = tick() - (self._cooldowns[name] or -math.huge)
		local remaining = math.max(0, def.cooldown - elapsed)
		status[name] = {
			ready     = remaining <= 0,
			remaining = string.format("%.1fs", remaining),
		}
	end
	return status
end

function EventManager:GetEventLog(): table
	return self._eventLog
end

function EventManager:GetDebugInfo(): table
	return {
		Enabled        = self._enabled,
		TotalEventsFired = #self._eventLog,
		Cooldowns      = self:GetCooldownStatus(),
	}
end

return EventManager
