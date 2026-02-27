# 🧠 Roblox AI NPC System — Phase 1

A clean, modular AI NPC system in Luau covering:
- Smart Pathfinding (jump, climb, swim, door-ready)
- Threat-based Target System with Line-of-Sight
- Finite State Machine (Idle → Patrol → Chase → Attack → Flee)

---

## 📁 File Structure

```
AI_NPC/
├── Shared/
│   ├── Config.lua            ← All tunable constants (ranges, speeds, damage…)
│   └── StateMachine.lua      ← Reusable FSM — clean, no spaghetti
│
└── Server/
    ├── NPCController.lua     ← Main NPC brain; wires all systems together
    ├── PathfindingController.lua  ← PathfindingService wrapper (jump/climb/swim/stuck)
    ├── TargetSystem.lua      ← Detection, LoS raycasts, threat tracking
    ├── States.lua            ← State definitions (Idle/Patrol/Chase/Attack/Flee)
    └── NPCSpawner.lua        ← ServerScript; spawns & respawns NPCs
```

---

## 🔧 Roblox Studio Setup

### 1. Place Files

```
ServerScriptService/
└── Server/           ← paste all Server/ files here
    └── NPCSpawner    ← this is the entry-point Script (not ModuleScript)

ReplicatedStorage/
└── Shared/           ← paste Shared/ files here

ReplicatedStorage/
└── NPCAssets/
    └── EnemyNPC      ← your NPC Model goes here
```

> **Important:** Change `require()` paths in each file to match where you put them.
> They currently use `script.Parent.Parent.Shared.X` — adjust as needed.

---

### 2. NPC Model Requirements

Your NPC Model (e.g. `EnemyNPC`) needs:
- `Humanoid`
- `HumanoidRootPart`
- `Animator` (auto-created by Humanoid usually)
- *(optional)* `AttackAnim` — an `Animation` instance for melee attacks

---

### 3. Spawn Points

Create a **Folder** in Workspace named `NPCSpawnPoints`.

Add `BasePart`s inside it. Each part can have these **Attributes**:

| Attribute       | Type   | Description                                      |
|----------------|--------|--------------------------------------------------|
| `NPCTemplate`  | string | Name of model in `NPCAssets` (default: EnemyNPC) |
| `PatrolFolder` | string | Name of a Workspace Folder with patrol BaseParts  |
| `RespawnDelay` | number | Seconds before respawn (default: 10)              |

---

### 4. Patrol Points (optional)

Create a **Folder** in Workspace (e.g. `PatrolRoute_1`).

Put `BasePart`s inside — the NPC will walk to them in order, looping.

Set the spawn point's `PatrolFolder` attribute to `"PatrolRoute_1"`.

If no patrol folder is set, the NPC will **random wander** instead.

---

### 5. Weapon Integration (Proper Threat Attribution)

Instead of letting `Humanoid:TakeDamage()` happen externally, call:

```lua
-- From your weapon script (server-side):
local NPCSpawner = require(path.to.NPCSpawner)
NPCSpawner.DamageNPC(npcModel, attackingPlayer, damageAmount)
```

This properly registers the attacker as a threat, so the NPC prioritizes them.

---

## ⚙️ Tuning — Config.lua

Everything is centralized:

```lua
Config.Detection.SightRange    = 60    -- studs
Config.Detection.SightAngle    = 110   -- degrees
Config.Combat.AttackRange      = 5     -- studs
Config.Combat.Damage           = 15
Config.Combat.FleeHealthPercent = 0.25 -- flee below 25% HP
Config.Patrol.WanderRadius     = 30    -- studs
Config.Movement.ChaseSpeed     = 20
```

---

## 🐛 Debug Mode

In `Config.lua`:

```lua
Config.Debug.Enabled        = true   -- master toggle
Config.Debug.ShowPath       = true   -- visualize pathfinding waypoints
Config.Debug.ShowStateLabel = true   -- billboard showing current state
Config.Debug.ShowSightCone  = false  -- (future phase)
```

Debug parts live in `workspace._NPCDebug` and auto-clean per NPC.

---

## 🗺️ State Machine Flow

```
          ┌──────────┐
    ┌────▶│   IDLE   │◀────────────────────────┐
    │     └────┬─────┘                          │
    │          │ timer                          │
    │          ▼                                │
    │     ┌──────────┐    target found          │
    │     │  PATROL  │──────────────────┐       │
    │     └──────────┘                  │       │
    │                                   ▼       │
    │                            ┌──────────┐   │
    │      HP recovered          │  CHASE   │   │
    └────────────────────────────│          │   │
                                 └────┬─────┘   │
                                      │ in range │
                                      ▼         │
                                 ┌──────────┐   │
                                 │  ATTACK  │   │
                                 └────┬─────┘   │
                                      │ low HP  │
                                      ▼         │
                                 ┌──────────┐   │
                                 │   FLEE   │───┘
                                 └──────────┘
```

---

## 🚀 Phase 2 Ideas (next steps)

- [ ] Door interaction (open/close via proximity)
- [ ] Sight cone debug visualization
- [ ] Hearing system (footstep events)
- [ ] Group awareness (alert nearby NPCs)
- [ ] Animation controller integration
- [ ] Ranged attack state
