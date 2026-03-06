-- DirectorController.lua
-- Main AI Director orchestrator.
-- Coordinates StressCalculator, PacingManager, SpawnManager,
-- EventManager, and DifficultyScaler in a single update loop.

-- ──────────────────────────────────────────────
--  Service & Module Imports
-- ──────────────────────────────────────────────
local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

-- Resolve sibling module paths (adjust to your DataModel layout)
local directorFolder = script.Parent
local spawningFolder = directorFolder.Parent.Spawning

local StressCalculator = require(directorFolder.StressCalculator)
local PacingManager    = require(directorFolder.PacingManager)
local SpawnManager     = require(directorFolder.SpawnManager)
local EventManager     = require(directorFolder.EventManager)
local DifficultyScaler = require(directorFolder.DifficultyScaler)
local SpawnPool        = require(spawningFolder.SpawnPool)
local SpawnPoint       = require(spawningFolder.SpawnPoint)

-- ──────────────────────────────────────────────
--  Director State Enum
-- ──────────────────────────────────────────────
local DirectorState = {
	INACTIVE = "INACTIVE",
	ACTIVE   = "ACTIVE",
	PAUSED   = "PAUSED",
}

-- ──────────────────────────────────────────────
--  Config
-- ──────────────────────────────────────────────
local UPDATE_INTERVAL         = 1.0   -- seconds between Director ticks
local DIFFICULTY_EVAL_INTERVAL = 10.0 -- seconds between skill evaluations
local SPAWN_POINT_FOLDER_NAME  = "SpawnPoints"  -- folder in Workspace

-- ──────────────────────────────────────────────
--  Class
-- ──────────────────────────────────────────────
local DirectorController = {}
DirectorController.__index = DirectorController

function DirectorController.new()
	local self = setmetatable({}, DirectorController)

	-- Public state (read by debugger / external systems)
	self.CurrentState  = DirectorState.INACTIVE
	self.CurrentStress = 0
	self.ActiveEnemies = 0
	self.LastSpawnTime = 0

	-- Internal subsystems (created in Initialize)
	self._stressCalc    = nil
	self._pacingMgr     = nil
	self._spawnPool     = nil
	self._spawnMgr      = nil
	self._eventMgr      = nil
	self._diffScaler    = nil

	-- Loop state
	self._accumulator        = 0
	self._diffAccumulator    = 0
	self._heartbeatConn      = nil
	self._initialized        = false

	-- Player data cache (populated each tick)
	self._playerDataCache    = {}

	return self
end

-- ──────────────────────────────────────────────
--  Initialization
-- ──────────────────────────────────────────────

--[[
	Initialize()
	Creates all subsystems, registers spawn points from Workspace,
	and wires up inter-system callbacks. Call once on server start.
]]
function DirectorController:Initialize()
	assert(not self._initialized, "[Director] Already initialized")

	-- 1. Create subsystems
	self._stressCalc = StressCalculator.new()
	self._pacingMgr  = PacingManager.new()
	self._spawnPool  = SpawnPool.new()
	self._diffScaler = DifficultyScaler.new()

	-- SpawnManager depends on pool
	self._spawnMgr   = SpawnManager.new(self._spawnPool)

	-- EventManager depends on SpawnManager
	self._eventMgr   = EventManager.new(self._spawnMgr)

	-- 2. Register spawn points from Workspace folder
	self:_registerSpawnPoints()

	-- 3. Wire callbacks
	self._spawnMgr.OnEnemySpawned = function(model, spawnType, position)
		self.LastSpawnTime = tick()
		self.ActiveEnemies = self._spawnMgr:GetActiveEnemyCount()
		print(string.format("[Director] Spawned %s at %s", spawnType, tostring(position)))
	end

	self._spawnMgr.OnEnemyDied = function(model)
		self.ActiveEnemies = self._spawnMgr:GetActiveEnemyCount()
		-- Report kill to difficulty scaler
		self._diffScaler:ReportKill()
	end

	self._pacingMgr:OnStateChanged(function(newState, prevState)
		print(string.format("[Director] Pacing: %s → %s", prevState, newState))
	end)

	-- 4. Start update loop
	self._heartbeatConn = RunService.Heartbeat:Connect(function(dt)
		self:Update(dt)
	end)

	self.CurrentState = DirectorState.ACTIVE
	self._initialized = true

	print("[DirectorController] Initialized ✓")
end

-- ──────────────────────────────────────────────
--  Spawn Point Registration
-- ──────────────────────────────────────────────

function DirectorController:_registerSpawnPoints()
	local folder = workspace:FindFirstChild(SPAWN_POINT_FOLDER_NAME)
	if not folder then
		warn("[Director] Workspace." .. SPAWN_POINT_FOLDER_NAME .. " not found — no spawn points registered")
		return
	end

	local count = 0
	for _, obj in ipairs(folder:GetDescendants()) do
		if obj:IsA("BasePart") then
			-- Read tags from StringValue children or CollectionService tags
			local tags = {}
			for _, child in ipairs(obj:GetChildren()) do
				if child:IsA("StringValue") and child.Name == "Tag" then
					table.insert(tags, child.Value)
				end
			end

			-- Optionally read weight from a NumberValue child
			local weightVal = obj:FindFirstChild("Weight")
			local weight = weightVal and weightVal.Value or 1

			local pt = SpawnPoint.new({
				part   = obj,
				tags   = tags,
				weight = weight,
			})
			self._spawnPool:Register(pt)
			count += 1
		end
	end

	print(string.format("[Director] Registered %d spawn points", count))
end

-- ──────────────────────────────────────────────
--  Player Data Sampling
-- ──────────────────────────────────────────────

function DirectorController:_samplePlayerData()
	-- For simplicity: aggregate stats across all players
	-- (In a real game you'd track per-player then average/max)
	local players = Players:GetPlayers()
	if #players == 0 then return nil end

	local totalHealth    = 0
	local totalMaxHealth = 0
	local totalAmmo      = 0
	local totalMaxAmmo   = 0
	local totalDamage    = 0

	for _, player in ipairs(players) do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then
				totalHealth    += hum.Health
				totalMaxHealth += hum.MaxHealth
			end
		end

		-- Ammo: read from a custom "Ammo" IntValue if it exists
		local ammoVal    = player:FindFirstChild("Ammo")
		local maxAmmoVal = player:FindFirstChild("MaxAmmo")
		totalAmmo    += ammoVal    and ammoVal.Value    or 30
		totalMaxAmmo += maxAmmoVal and maxAmmoVal.Value or 30

		-- Damage taken: read from a "DamageTaken" NumberValue (reset each tick externally)
		local dmgVal = player:FindFirstChild("DamageTaken")
		totalDamage += dmgVal and dmgVal.Value or 0
	end

	local n = #players
	return {
		health          = totalHealth    / n,
		maxHealth       = totalMaxHealth / n,
		enemiesNearby   = self.ActiveEnemies,
		damageTaken     = totalDamage    / n,
		ammo            = totalAmmo      / n,
		maxAmmo         = totalMaxAmmo   / n,
		timeSinceCombat = self._timeSinceCombat or 0,
	}
end

-- ──────────────────────────────────────────────
--  Main Update Loop
-- ──────────────────────────────────────────────

--[[
	Update(dt: number)
	Called every Heartbeat. Throttled to UPDATE_INTERVAL seconds.
]]
function DirectorController:Update(dt: number)
	if self.CurrentState ~= DirectorState.ACTIVE then return end

	self._accumulator     += dt
	self._diffAccumulator += dt

	-- Throttle Director ticks
	if self._accumulator < UPDATE_INTERVAL then return end
	local tickDt = self._accumulator
	self._accumulator = 0

	-- Sample player state
	local playerData = self:_samplePlayerData()
	if not playerData then return end

	-- Update time-since-combat heuristic
	if playerData.damageTaken > 0 then
		self._timeSinceCombat = 0
	else
		self._timeSinceCombat = (self._timeSinceCombat or 0) + tickDt
	end
	playerData.timeSinceCombat = self._timeSinceCombat

	-- 1. Stress
	self.CurrentStress = self._stressCalc:CalculateStress(playerData)

	-- 2. Pacing
	self._pacingMgr:UpdateState(self.CurrentStress, tickDt)
	local spawnMult   = self._pacingMgr:GetSpawnMultiplier()
	local eventProb   = self._pacingMgr:GetEventProbability()

	-- 3. Difficulty evaluation (throttled)
	if self._diffAccumulator >= DIFFICULTY_EVAL_INTERVAL then
		self._diffAccumulator = 0
		self._diffScaler:EvaluatePlayerSkill()
		self._spawnMgr:SetSpawnRateModifier(self._diffScaler:GetSpawnRateModifier())
	end

	-- 4. Evaluate state (may trigger spawn / event)
	self:EvaluateState(spawnMult, eventProb)
end

--[[
	EvaluateState(spawnMult, eventProb)
	Decides whether to spawn enemies or trigger events this tick.
]]
function DirectorController:EvaluateState(spawnMult: number, eventProb: number)
	-- Spawn attempt
	if spawnMult > 0 then
		self:RequestSpawn(spawnMult)
	end

	-- Event attempt
	self:TriggerEvent(eventProb)
end

--[[
	RequestSpawn(pacingMultiplier: number)
	Asks SpawnManager to spawn a standard enemy.
]]
function DirectorController:RequestSpawn(pacingMultiplier: number)
	self._spawnMgr:SpawnEnemy(pacingMultiplier)
	self.ActiveEnemies = self._spawnMgr:GetActiveEnemyCount()
end

--[[
	TriggerEvent(eventProbability: number)
	Asks EventManager to attempt triggering a special event.
]]
function DirectorController:TriggerEvent(eventProbability: number)
	self._eventMgr:TryTriggerEvent(self.CurrentStress, eventProbability)
end

-- ──────────────────────────────────────────────
--  Lifecycle Controls
-- ──────────────────────────────────────────────

function DirectorController:Pause()
	self.CurrentState = DirectorState.PAUSED
	print("[Director] Paused")
end

function DirectorController:Resume()
	if self._initialized then
		self.CurrentState = DirectorState.ACTIVE
		print("[Director] Resumed")
	end
end

function DirectorController:Shutdown()
	if self._heartbeatConn then
		self._heartbeatConn:Disconnect()
		self._heartbeatConn = nil
	end
	self.CurrentState = DirectorState.INACTIVE
	print("[Director] Shutdown")
end

-- ──────────────────────────────────────────────
--  External Reporter Hooks
-- (Call these from your combat/weapon scripts)
-- ──────────────────────────────────────────────

function DirectorController:ReportShot(hit: boolean)
	if self._diffScaler then
		self._diffScaler:ReportShot(hit)
	end
end

function DirectorController:ReportKill()
	if self._diffScaler then
		self._diffScaler:ReportKill()
	end
end

-- ──────────────────────────────────────────────
--  Debug Info Aggregator
-- ──────────────────────────────────────────────

function DirectorController:GetDebugInfo(): table
	return {
		Director = {
			State          = self.CurrentState,
			Stress         = string.format("%.1f", self.CurrentStress),
			ActiveEnemies  = self.ActiveEnemies,
			LastSpawnTime  = string.format("%.1fs ago", tick() - self.LastSpawnTime),
		},
		Pacing     = self._pacingMgr     and self._pacingMgr:GetDebugInfo()     or {},
		Spawning   = self._spawnMgr      and self._spawnMgr:GetDebugInfo()       or {},
		Events     = self._eventMgr      and self._eventMgr:GetDebugInfo()       or {},
		Difficulty = self._diffScaler    and self._diffScaler:GetDebugInfo()     or {},
		Pool       = self._spawnPool     and self._spawnPool:GetDebugInfo()      or {},
	}
end

-- ──────────────────────────────────────────────
--  Subsystem Accessors (for debugger / external tools)
-- ──────────────────────────────────────────────

function DirectorController:GetPacingManager()    return self._pacingMgr  end
function DirectorController:GetSpawnManager()     return self._spawnMgr   end
function DirectorController:GetEventManager()     return self._eventMgr   end
function DirectorController:GetDifficultyScaler() return self._diffScaler end
function DirectorController:GetSpawnPool()        return self._spawnPool  end
function DirectorController:GetStressCalculator() return self._stressCalc end

return DirectorController
