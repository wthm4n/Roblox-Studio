# NPC AI System

A modular NPC AI framework for Roblox that handles spawning, personalities, squad coordination, patrols, movement, and combat. Core pieces live under `src/` and are designed to be dropped into a Roblox place with minimal changes.

- Core spawner and runtime entry: [`NPCSpawner`](src/ServerScriptService/Main.server.lua) (see [`NPCSpawner.init`](src/ServerScriptService/Main.server.lua) and [`NPCSpawner.DamageNPC`](src/ServerScriptService/Main.server.lua))
- Central configuration: [`Config`](src/ReplicatedStorage/Shared/config.lua) (see [`Config.Detection`](src/ReplicatedStorage/Shared/config.lua), [`Config.Movement`](src/ReplicatedStorage/Shared/config.lua), [`Config.Squad`](src/ReplicatedStorage/Shared/config.lua), etc.)
- Rig builder defaults: [`RigBuilderConfig`](src/ReplicatedStorage/Shared/Monitor.lua)
- NPC AI modules: [`NPCController`](src/ServerScriptService/NPCAIModule/NPCController.lua) and related files in `src/ServerScriptService/NPCAIModule/` (e.g. [`PersonalityManager`](src/ServerScriptService/NPCAIModule/PersonalityManager.lua), [`SquadManager`](src/ServerScriptService/NPCAIModule/SquadManager.lua))

Quick links to files:
- [src/ServerScriptService/Main.server.lua](src/ServerScriptService/Main.server.lua)
- [src/ReplicatedStorage/Shared/config.lua](src/ReplicatedStorage/Shared/config.lua)
- [src/ReplicatedStorage/Shared/Monitor.lua](src/ReplicatedStorage/Shared/Monitor.lua)
- [src/ReplicatedStorage/init.meta.json](src/ReplicatedStorage/init.meta.json)
- [src/ServerScriptService/NPCAIModule/](src/ServerScriptService/NPCAIModule/)

Table of contents
- Overview
- Installation
- Spawn point attributes & examples
- Configuration reference
- Runtime API
- Squad behavior
- Debugging & visualizers
- Notes & best practices

Overview
--------
This system spawns NPC models from `ReplicatedStorage.NPCAssets`, attaches an AI brain implemented in `src/ServerScriptService/NPCAIModule/` (e.g. [`NPCController`](src/ServerScriptService/NPCAIModule/NPCController.lua)), and manages patrols, personalities, squads, combat, and respawning. Spawning and lifecycle logic live in [`src/ServerScriptService/Main.server.lua`](src/ServerScriptService/Main.server.lua).

Installation
------------
1. Place the `src` contents in your place (ServerScriptService, ReplicatedStorage, etc.).
2. Ensure `ReplicatedStorage.NPCAssets` contains your NPC models (each must include a `Humanoid` and `HumanoidRootPart`).
3. Create a `Folder` named `NPCSpawnPoints` in `Workspace` and add `BasePart` spawn points with attributes described below.
4. Server entrypoint: the spawner script [`src/ServerScriptService/Main.server.lua`](src/ServerScriptService/Main.server.lua) auto-initializes via [`NPCSpawner.init`](src/ServerScriptService/Main.server.lua).

Spawn point attributes & example
--------------------------------
Spawn points are `BasePart`s placed under `Workspace.NPCSpawnPoints`. Supported attributes (set in Studio or by script):

- `NPCTemplate` (string) — model name inside `ReplicatedStorage.NPCAssets` (default `"EnemyNPC"`).
- `Personality` (string) — `"Passive" | "Scared" | "Aggressive" | "Tactical"`.
- `EnableSquad` (bool) — allow squad coordination for spawned NPC.
- `PatrolFolder` (string) — name of a `Folder` in `Workspace` containing patrol `BasePart`s.
- `RespawnDelay` (number) — seconds before respawn (default 10).

Example: create a spawn point via script
```lua
-- lua
local spawn = Instance.new("Part")
spawn.Name = "Spawn1"
spawn.Size = Vector3.new(2,1,2)
spawn.Position = Vector3.new(0,5,0)
spawn.Parent = workspace:WaitForChild("NPCSpawnPoints")
spawn:SetAttribute("NPCTemplate", "EnemyNPC")
spawn:SetAttribute("Personality", "Aggressive")
spawn:SetAttribute("EnableSquad", true)
spawn:SetAttribute("PatrolFolder", "Patrols")
spawn:SetAttribute("RespawnDelay", 12)
```

How spawning works (key functions)
---------------------------------
- [`spawnNPC`](src/ServerScriptService/Main.server.lua) clones the template, stamps attributes (Personality, EnableSquad), positions it, creates the brain via [`NPCController.new`](src/ServerScriptService/NPCAIModule/NPCController.lua), and registers death/respawn handlers.
- [`getPatrolPoints`](src/ServerScriptService/Main.server.lua) looks up `PatrolFolder` and returns BasePart waypoints.
- The spawner stores active brains in `activeNPCs` and exposes helpers like [`NPCSpawner.DamageNPC`](src/ServerScriptService/Main.server.lua) to attribute damage.

Configuration reference
-----------------------
All runtime tunables live in [`src/ReplicatedStorage/Shared/config.lua`](src/ReplicatedStorage/Shared/config.lua). Highlights:

- [`Config.Detection`](src/ReplicatedStorage/Shared/config.lua)
  - SightRange, SightAngle, HearRange, LoseTargetTime, RaycastCooldown
- [`Config.Movement`](src/ReplicatedStorage/Shared/config.lua)
  - WalkSpeed, ChaseSpeed, FleeSpeed, PathRecalcDelay, WaypointReachDist
- [`Config.Combat`](src/ReplicatedStorage/Shared/config.lua)
  - AttackRange, AttackCooldown, Damage, FleeHealthPercent, ThreatDecayRate
- [`Config.Patrol`](src/ReplicatedStorage/Shared/config.lua)
  - WaitTime, RandomWander, WanderRadius
- [`Config.Debug`](src/ReplicatedStorage/Shared/config.lua)
  - Enabled, ShowPath, ShowSightCone, ShowStateLabel, PathColor, WaypointColor
- Personality-specific tables: [`Config.Passive`](src/ReplicatedStorage/Shared/config.lua), [`Config.Scared`](src/ReplicatedStorage/Shared/config.lua), [`Config.Aggressive`](src/ReplicatedStorage/Shared/config.lua), [`Config.Tactical`](src/ReplicatedStorage/Shared/config.lua)
- Squad tuning: [`Config.Squad`](src/ReplicatedStorage/Shared/config.lua) — SquadJoinRadius, MaxSquadSize, BackupRadius, etc.

Rig builder & Monitor
---------------------
Default rig and visual debug settings are provided by [`RigBuilderConfig`](src/ReplicatedStorage/Shared/Monitor.lua). Use this to control humanoid defaults, appearance, body part sizes, animation toggles, accessories, and AI defaults used by utilities that build NPCs.

Runtime API (exposed by spawner)
--------------------------------
- [`NPCSpawner.init`](src/ServerScriptService/Main.server.lua) — called at boot to spawn existing spawn points and bind to `ChildAdded`.
- [`NPCSpawner.DamageNPC(npcModel, attacker, amount)`](src/ServerScriptService/Main.server.lua) — register threat and apply damage; call from weapon scripts to properly attribute damage to players.

Squads & coordination
---------------------
Squad logic layers on personalities. Enable per-NPC (spawn point attribute `EnableSquad` or model attribute) and tune behavior in [`Config.Squad`](src/ReplicatedStorage/Shared/config.lua). Key concepts:
- NPCs spawned within `SquadJoinRadius` join the same squad.
- Leaders coordinate formation slots and call backup within `BackupRadius`.
- `AlertThreatBoost` and `AlertDuration` control how long nearby members stay in hunt mode.

Debugging & visualization
-------------------------
Toggle debug visuals via [`Config.Debug`](src/ReplicatedStorage/Shared/config.lua). Common flags:
- `ShowPath` — draws path lines.
- `ShowSightCone` — renders detection cone.
- `ShowStateLabel` — shows current state and debug text.

Notes & best practices
----------------------
- NPC models must include `Humanoid` and `HumanoidRootPart`. Optional components: attack animations, hitboxes, custom accessories.
- Keep `ReplicatedStorage.NPCAssets` organized; template names are used by spawn points via the `NPCTemplate` attribute.
- If you change config values at runtime, propagate to running brains if desired (the code reads `Config` when creating brains; modules may cache values).
- The spawner delays 0.1s on runtime-added spawn points to allow attribute initialization; if you're dynamically creating spawn parts, set attributes immediately or wait before spawning.

Metadata
--------
- init meta: [src/ReplicatedStorage/init.meta.json](src/ReplicatedStorage/init.meta.json)
- Entry point: [src/ServerScriptService/Main.server.lua](src/ServerScriptService/Main.server.lua)
- Config: [src/ReplicatedStorage/Shared/config.lua](src/ReplicatedStorage/Shared/config.lua)
- Monitor/rig defaults: [src/ReplicatedStorage/Shared/Monitor.lua](src/ReplicatedStorage/Shared/Monitor.lua)

If you want, I can:
- Produce a minimal sample NPC model for `ReplicatedStorage.NPCAssets`.
- Produce example patrol folders and spawn-point placement scripts.
- Generate docs for the `NPCAIModule` internals (e.g. [`NPCController`](src/ServerScriptService/NPCAIModule/NPCController.lua), [`PersonalityManager`](src/ServerScriptService/NPCAIModule/PersonalityManager.lua)).
