--[[
	Server/Init.server.lua
	─────────────────────────────────────────────────────────
	Bootstrap script. Place this as a Script inside ServerScriptService.

	Folder structure expected:
	  ServerScriptService
	    └── CombatFramework
	          └── Server
	                ├── Init.server.lua       ← this file
	                ├── Services/
	                │     ├── CombatService.lua
	                │     ├── HitboxService.lua
	                │     ├── DamageService.lua
	                │     ├── StatusService.lua
	                │     ├── ComboService.lua
	                │     └── AbilityHandler.lua
	                ├── Classes/
	                │     ├── PlayerState.lua
	                │     └── StatusEffect.lua
	                └── Abilities/
	                      ├── M1.lua
	                      ├── Dash.lua
	                      ├── Fireball.lua
	                      └── Block.lua

	  ReplicatedStorage
	    └── CombatRemotes
	          ├── AbilityRequest : RemoteEvent
	          └── VFXEvent       : RemoteEvent
	─────────────────────────────────────────────────────────
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─── Remote Setup ─────────────────────────────────────────────────────────────

local remotes = ReplicatedStorage:WaitForChild("CombatRemotes")
local abilityRemote: RemoteEvent = remotes:WaitForChild("AbilityRequest")
local vfxRemote:     RemoteEvent = remotes:WaitForChild("VFXEvent")

-- ─── Boot CombatService ───────────────────────────────────────────────────────

local CombatService = require(script.Parent.Services.CombatService)
local abilitiesFolder = script.Parent.Abilities

local combat = CombatService.new(abilitiesFolder, vfxRemote)
combat:BindRemote(abilityRemote)

print("[CombatFramework] Server initialised.")