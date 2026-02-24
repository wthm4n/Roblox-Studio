--[[
	CombatService.lua
	Top-level server controller. Singleton.
	Supports players AND NPCs.
]]

local CombatService = {}
CombatService.__index = CombatService

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")

assert(RunService:IsServer(), "[CombatService] Must run on server")

local HitboxService  = require(script.Parent.HitboxService)
local DamageService  = require(script.Parent.DamageService)
local StatusService  = require(script.Parent.StatusService)
local ComboService   = require(script.Parent.ComboService)
local AbilityHandler = require(script.Parent.AbilityHandler)
local PlayerState    = require(script.Parent.Parent.Classes.PlayerState)

local ANTI_SPAM_RATE = 0.08
local COOLDOWN_GRACE = 0.05

-- ─── Constructor ──────────────────────────────────────────────────────────────

function CombatService.new(abilitiesFolder: Folder, vfxRemote: RemoteEvent)
	local self = setmetatable({}, CombatService)

	self._hitbox  = HitboxService.new()
	self._damage  = DamageService.new()
	self._status  = StatusService.new()
	self._combo   = ComboService.new()
	self._handler = AbilityHandler.new(abilitiesFolder)

	self._states      = {}  -- [userId | npcId] = PlayerState
	self._cooldowns   = {}
	self._lastRequest = {}
	self._vfxRemote   = vfxRemote

	Players.PlayerAdded:Connect(function(p) self:_OnPlayerAdded(p) end)
	Players.PlayerRemoving:Connect(function(p) self:_OnPlayerRemoving(p) end)

	for _, p in ipairs(Players:GetPlayers()) do
		self:_OnPlayerAdded(p)
	end

	return self
end

-- ─── Player Lifecycle ─────────────────────────────────────────────────────────

function CombatService:_InitState(id: number, player: Player?)
	self._states[id]      = PlayerState.new(player)
	self._cooldowns[id]   = {}
	self._lastRequest[id] = 0
end

function CombatService:_ResetState(id: number, player: Player?)
	local state = self._states[id]
	if not state then return end
	state:SetState("Idle")
	state.Stamina = state.MaxStamina
	state:RestoreGuard()
	self._status:ClearAll(state)
	if player then
		self._combo:Reset(player)
	end
end

function CombatService:_OnPlayerAdded(player: Player)
	local id = player.UserId
	self:_InitState(id, player)

	player.CharacterAdded:Connect(function()
		self:_ResetState(id, player)
	end)

	-- RACE FIX: character already exists on first join when service boots
	if player.Character then
		self:_ResetState(id, player)
	end
end

function CombatService:_OnPlayerRemoving(player: Player)
	local id    = player.UserId
	local state = self._states[id]
	if state then state:Destroy() end
	self._states[id]      = nil
	self._cooldowns[id]   = nil
	self._lastRequest[id] = nil
	self._combo:OnPlayerRemoving(player)
end

-- ─── NPC Support ──────────────────────────────────────────────────────────────

function CombatService:RegisterNPC(npcId: number)
	self:_InitState(npcId, nil)
	self:_ResetState(npcId, nil)
end

function CombatService:UnregisterNPC(npcId: number)
	local state = self._states[npcId]
	if state then state:Destroy() end
	self._states[npcId]      = nil
	self._cooldowns[npcId]   = nil
	self._lastRequest[npcId] = nil
end

-- Call this from your NPC AI script to use an ability
function CombatService:NPCRequest(npcId: number, abilityName: string, inputData: {}?)
	local state = self._states[npcId]
	if not state then warn("[CombatService] NPC not registered:", npcId) return end
	if not self:_ValidateAbilityExists(abilityName) then return end
	if not self:_ValidateCooldownById(npcId, abilityName) then return end
	if not self:_ValidateStateRaw(state) then return end

	self:_Execute(nil, npcId, abilityName, inputData or {}, state)
end

-- ─── Validation ───────────────────────────────────────────────────────────────

function CombatService:_ValidateStateRaw(state): boolean
	return state:CanAct() and not state:Is("Dead")
end

function CombatService:_ValidateAntiSpam(id: number): boolean
	local now = os.clock()
	if (now - (self._lastRequest[id] or 0)) < ANTI_SPAM_RATE then return false end
	self._lastRequest[id] = now
	return true
end

function CombatService:_ValidateAbilityExists(name: string): boolean
	return self._handler:Has(name)
end

function CombatService:_ValidateCooldownById(id: number, name: string): boolean
	local expires = self._cooldowns[id] and self._cooldowns[id][name]
	if not expires then return true end
	return os.clock() >= expires - COOLDOWN_GRACE
end

function CombatService:_ValidateStamina(state, name: string): boolean
	return state:HasStamina(self._handler:GetStaminaCost(name))
end

-- ─── Execution ────────────────────────────────────────────────────────────────

function CombatService:_Execute(player: Player?, id: number, name: string, inputData: {}, state)
	state:ConsumeStamina(self._handler:GetStaminaCost(name))

	local ctx = {
		hitbox  = self._hitbox,
		damage  = self._damage,
		status  = self._status,
		combo   = self._combo,
		states  = self._states,
		fireVfx = function(eventName: string, data: {})
			if self._vfxRemote then
				self._vfxRemote:FireAllClients(eventName, data)
			end
		end,
	}

	self._handler:Execute(player, name, inputData, ctx)

	local cd = self._handler:GetCooldown(name)
	if cd and cd > 0 then
		self._cooldowns[id][name] = os.clock() + cd
	end
end

-- ─── Player Remote Entry Point ────────────────────────────────────────────────

function CombatService:OnRequest(player: Player, abilityName: string, inputData: {}?)
	local id    = player.UserId
	local state = self._states[id]

	if not state then
		warn("[CombatService] No state for", player.Name, "- still spawning?")
		return
	end
	if not self:_ValidateAntiSpam(id) then return end
	if not self:_ValidateAbilityExists(abilityName) then
		warn("[CombatService] Unknown ability:", abilityName)
		return
	end
	if not self:_ValidateCooldownById(id, abilityName) then return end
	if not self:_ValidateStamina(state, abilityName) then
		warn("[CombatService] Not enough stamina for", abilityName, "stamina:", state.Stamina)
		return
	end
	if not self:_ValidateStateRaw(state) then
		warn("[CombatService] Bad state for", player.Name, "current:", state.State)
		return
	end

	self:_Execute(player, id, abilityName, inputData or {}, state)
end

function CombatService:BindRemote(remote: RemoteEvent)
	remote.OnServerEvent:Connect(function(player, abilityName, inputData)
		if typeof(abilityName) ~= "string" then return end
		self:OnRequest(player, abilityName, inputData)
	end)
end

function CombatService:GetState(id: number)
	return self._states[id]
end

return CombatService