--!strict
-- MinionService.lua
-- The single authoritative manager for all minions on the server.
-- Owns the entity registry and a per-owner index for O(1) lookups.
-- Server authoritative: clients never spawn, destroy, or mutate minions
-- directly — they send requests via RemoteEvents, which this service
-- validates and applies.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework = ReplicatedStorage.Framework
local MinionEntity = require(Framework.MinionEntity)
local Signal = require(Framework.Signal)

export type SpawnOptions = {
	Model: Model?,
}

local MinionService = {}
MinionService.__index = MinionService

-- entityId -> MinionEntity
local entities: { [number]: MinionEntity.MinionEntity } = {}

-- Player -> { [entityId]: true } ; set semantics for O(1) add/remove
local ownerIndex: { [Player]: { [number]: true } } = {}

local entityCount = 0
local nextId = 0

local MinionSpawned = Signal.new() -- (entity)
local MinionDestroyed = Signal.new() -- (entity)

local function generateId(): number
	nextId += 1
	return nextId
end

local function ensureOwnerSet(owner: Player): { [number]: true }
	local set = ownerIndex[owner]
	if not set then
		set = {}
		ownerIndex[owner] = set
	end
	return set
end

--[[
	Spawns a new minion owned by `owner`. The caller (server-side game logic,
	never the client directly) is responsible for deciding *whether* a spawn
	is allowed (limits, cooldowns, currency, etc.) before calling this.
]]
function MinionService.Spawn(owner: Player, options: SpawnOptions?): MinionEntity.MinionEntity
	options = options or {}

	local id = generateId()
	local entity = MinionEntity.new(id, owner, options.Model)

	entities[id] = entity
	ensureOwnerSet(owner)[id] = true
	entityCount += 1

	entity.Destroying:Once(function()
		MinionService._unregister(entity)
	end)

	MinionSpawned:Fire(entity)
	return entity
end

function MinionService._unregister(entity: MinionEntity.MinionEntity)
	local id = entity.Id
	if not entities[id] then
		return
	end

	entities[id] = nil

	local set = ownerIndex[entity.Owner]
	if set then
		set[id] = nil
		if next(set) == nil then
			ownerIndex[entity.Owner] = nil
		end
	end

	entityCount -= 1
	MinionDestroyed:Fire(entity)
end

--[[
	Destroys a minion by id. Idempotent — destroying an already-destroyed
	or nonexistent id is a no-op.
]]
function MinionService.Destroy(id: number)
	local entity = entities[id]
	if not entity then
		return
	end
	entity:Destroy()
end

--[[
	Destroys every minion owned by `owner`. Used on PlayerRemoving and for
	explicit "clear my minions" actions.
]]
function MinionService.DestroyAllForOwner(owner: Player)
	local set = ownerIndex[owner]
	if not set then
		return
	end

	-- Snapshot ids first: Destroy() mutates `set` via the Destroying signal,
	-- so iterating the live table while destroying would skip entries.
	local ids = {}
	for id in pairs(set) do
		table.insert(ids, id)
	end

	for _, id in ipairs(ids) do
		MinionService.Destroy(id)
	end
end

function MinionService.Get(id: number): MinionEntity.MinionEntity?
	return entities[id]
end

function MinionService.Exists(id: number): boolean
	return entities[id] ~= nil
end

--[[
	Returns a fresh array of entities owned by `owner`. O(n) in the number
	of that owner's minions, not the global registry.
]]
function MinionService.GetByOwner(owner: Player): { MinionEntity.MinionEntity }
	local set = ownerIndex[owner]
	if not set then
		return {}
	end

	local result = {}
	for id in pairs(set) do
		local entity = entities[id]
		if entity then
			table.insert(result, entity)
		end
	end
	return result
end

--[[
	Iterates every live minion. Safe against the callback destroying the
	entity it's currently visiting (snapshot semantics), but does not
	guarantee inclusion of minions spawned during iteration.
]]
function MinionService.ForEach(callback: (entity: MinionEntity.MinionEntity) -> ())
	for _, entity in pairs(entities) do
		if not entity.Destroyed then
			callback(entity)
		end
	end
end

function MinionService.Count(): number
	return entityCount
end

function MinionService.CountForOwner(owner: Player): number
	local set = ownerIndex[owner]
	if not set then
		return 0
	end

	local count = 0
	for _ in pairs(set) do
		count += 1
	end
	return count
end

MinionService.MinionSpawned = MinionSpawned
MinionService.MinionDestroyed = MinionDestroyed

Players.PlayerRemoving:Connect(function(player: Player)
	MinionService.DestroyAllForOwner(player)
end)

return MinionService
