# neon.io (Godot 4.5.1)

## Overview
This project is now structured around a command-driven simulation core that is ready for future multiplayer replication and external agent control. The current gameplay is unchanged, but inputs now flow through a clear pipeline:

```
InputSource -> CommandQueue -> GameWorld.apply(command) -> Events -> Presentation
                                      |
                                      +-> GameState snapshot -> Agent/Network bridges
```

## Architecture Diagram
```
World (presentation root)
|-- BlueprintGrid (visuals)
|-- Player (presentation + combatant logic)
|-- Enemies (container)
|-- BoostOrbs (drop container)
|-- HUD / GameOver (UI)
|-- GameWorld (domain boundary)
    |-- CommandQueue
    |-- HumanInputSource
    |-- AgentInputSource
    |-- AgentBridge
    |   |-- LocalAgentStub (disabled by default)
    |-- NetworkAdapter (local stub)
```

## Folder Structure
```
/assets
  audio/...
/src
  domain
    commands/        # GameCommand definitions
    events/          # GameEvent types
    state/           # GameState snapshot
    world/           # GameWorld authoritative boundary
    weapons/         # Domain data (WeaponSlot)
  input
    CommandQueue.gd
    InputSource.gd
    HumanInputSource.gd
    AgentInputSource.gd
    AIInputSource.gd
  infrastructure
    agent/           # Agent bridge + local stub
    network/         # Network adapter boundary
  presentation
    scenes/          # Main/World/Player/Enemy scenes
    world/           # World scripts
    player/          # Player + shape
    weapons/         # WeaponSystem + projectiles
    ui/              # HUD scripts
    enemies/         # Enemy presentation
/scenes              # Compatibility wrappers for original paths
/scripts             # Compatibility wrappers for original paths
/docs
  ARCHITECTURE.md
```

## How To Run
```
./run_game.sh
```

Debug collision overlay:
```
./run_game.sh --collision-debug
```

## Controls
- WASD / arrows: move
- Hold Shift: show expansion outlines from active cell
- While holding Shift + direction: expand (if empty) or set active cell (if occupied)
- Tab: next slot, `[` previous slot
- Q: toggle range ring
- 1/2/3/4: buy ammo pack + select weapon (Laser/Stun/Homing/Spread)
- R: restart

## Command Pipeline (Core Contract)
All gameplay input now routes through commands:
- `HumanInputSource` captures local input and enqueues `GameCommand`.
- `AgentInputSource` accepts external commands via `AgentBridge`.
- `GameWorld` consumes the queue in `_physics_process` and applies commands to actors.
- `GameWorld` emits `GameEvent` and periodic `GameState` snapshots.

## Agent Control (Commands + State)
Agent boundary lives in `src/infrastructure/agent` and is transport-agnostic.

Commands are `GameCommand` resources with:
- `type`
- `actor_id`
- `payload`

Current command types:
- `MOVE` (`payload.dir: Vector2`)
- `TOGGLE_EXPAND` (legacy)
- `PLACE_CELL` (legacy, `payload.grid_pos: Vector2i`)
- `SET_EXPAND_HOLD` (`payload.enabled: bool`)
- `EXPAND_DIRECTION` (`payload.dir: Vector2i`)
- `SELECT_WEAPON` (`payload.weapon_type`)
- `SELECT_NEXT_SLOT`
- `SELECT_PREV_SLOT`
- `TOGGLE_RANGE`
- `RESTART`

## Gameplay Notes
- Expansion cost: 60 credits per cell.
- Expansion armor: +4% damage reduction per extra cell (cap 40%).
- Starting credits: 250.
- Starting ammo: Laser 40, Stun 16, Homing 8, Spread 14.
- Global weapon selection: all cells fire the currently selected weapon.
- Homing missiles are capped per player (up to one active missile per cell).
- Camera follows the active cell with smoothing.
- Boost orbs spawn on any combatant death:
  - types: XP, weapon-specific ammo, health
  - ammo orb colors match weapon colors (laser cyan, stun green, homing orange, spread purple)
  - value scales by victim survival time + credits + cell count
  - both player and AI can consume
  - touching while capped still invalidates the orb (denial play), with a short CRT-style collapse/fade animation
  - XP orb shows `$`, health orb shows `+`
  - orb lifetime: 20s
- AI behavior includes profile/state-aware orb decisions:
  - pursues useful orb types based on health, ammo capacity need, credits, and nearby enemy pressure
  - blends orb pursuit with combat steering
- Enemy spawns are mixed:
  - near player, farther from player, or around ongoing action (other combatants / existing orbs)

State snapshots are `GameState.to_dict()` dictionaries:
- `actors`: list of `id`, `position`, `health`, `max_health`, `is_ai`
- `time`

### Local Agent Stub (Minimal Example)
Enable the local stub in `src/presentation/scenes/World.tscn`:
```
GameWorld/AgentBridge/LocalAgentStub.enabled = true
```
This will feed periodic `MOVE` commands to the player via the AgentBridge.

## How To Add A New Feature
### Example: New Weapon
1. Add weapon rules/data in `src/presentation/weapons/WeaponSystem.gd`.
2. If you need persistent data, add a `Resource` in `src/domain/weapons/`.
3. If you need input, add a new `GameCommand` type in `src/domain/commands/Command.gd` and handle it in `src/domain/world/GameWorld.gd`.

### Example: New Enemy Type
1. Create a new scene in `src/presentation/scenes/`.
2. Add behavior scripts under `src/presentation/enemies/`.
3. Spawn via `src/presentation/world/World.gd`.

### Example: New Network Message
1. Define a payload format in `src/domain/events/` or `src/domain/state/`.
2. Emit from `GameWorld` using `event_emitted` or `state_emitted`.
3. Implement handling in a concrete `NetworkAdapter` under `src/infrastructure/network/`.

## Coding Conventions
- Scene roots use `PascalCase` node names.
- Scripts use `class_name` for core types (e.g., `Player`, `WeaponSystem`).
- Domain resources live under `src/domain` and avoid direct Node dependencies when possible.
- Signals are verbs in past tense (`died`, `command_applied`) or intent (`state_emitted`).
- Autoloads are avoided unless truly global; current design is scene-contained.

## Networking Readiness
Ready now:
- Command/event boundaries exist and are isolated in `GameWorld`.
- `NetworkAdapter` is a clean stub where replication can be added without touching gameplay logic.
- `GameState` snapshots are JSON-ready dictionaries.

Deferred for later:
- Real transport (WebSocket/HTTP/gRPC).
- Authority reconciliation, prediction, rollback.
- Deterministic tick synchronization.
