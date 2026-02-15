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
    |-- NetworkAdapter (local loopback transport)
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
  network/protocol_v1.md
```

## How To Run
```
./run_game.sh
```
Startup now opens a mode selector in `Main`:
- `offline_ai`: starts local world immediately.
- `mixed` / `human_only`: opens lobby queue flow.

For `mixed` / `human_only`, start the lobby service first:
```bash
cd backend/lobby-service
python3 app.py
```
Default lobby URL is `http://127.0.0.1:8080`.
Override if needed:
- env: `NEON_LOBBY_URL=http://<host>:<port> ./run_game.sh`
- arg: `./run_game.sh --lobby-url=http://<host>:<port>`

Useful startup overrides:
- `--skip-mode-select` (bypass menu)
- `NEON_MODE=offline_ai|mixed|human_only`
- `NEON_SERVER=1` or `--server` (headless/server path bypasses menu)
- `--test-human-mode` (starts lobby + human_only match server + two clients)
  - test window overrides:
  - `NEON_TEST_CLIENT_RESOLUTION` (default `960x540`)
  - `NEON_TEST_CLIENT_LEFT_POS` (default `0,0`)
  - `NEON_TEST_CLIENT_RIGHT_POS` (default `970,0`)

## First 5 Minutes (New Agent Session)
Run these in order before coding:
```bash
./run_game.sh --headless --script res://scripts/tests/network_protocol_validator.gd
./run_game.sh --headless --script res://scripts/tests/authority_guard_smoke.gd
timeout 12 ./run_game.sh
```

If gameplay appears frozen (player + AI not moving), check `GameWorld._validate_command()` first.
Local/offline commands must not be treated as network commands unless payload includes `__net`.

Dedicated ENet match server (headless):
```
NEON_SERVER=1 NEON_MODE=mixed NEON_NETWORK_ROLE=server NEON_TRANSPORT=enet NEON_PORT=7000 NEON_MAX_PLAYERS=10 ./run_game.sh --headless
```

ENet client:
```
NEON_MODE=mixed NEON_NETWORK_ROLE=client NEON_TRANSPORT=enet NEON_HOST=127.0.0.1 NEON_PORT=7000 ./run_game.sh
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
- Esc: open lobby

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
- `NetworkAdapter` validates a versioned envelope (`net.v1`) and routes command/state/event messages.
- `LocalNetworkAdapter` supports loopback simulation for commands/state/events with optional latency.
- `GameState` snapshots are JSON-ready dictionaries.
- Protocol examples exist under `docs/network/examples/`.
- ENet transport path is available in `NetworkAdapter` (CLI flags and env overrides).
- ENet single-process smoke script is fixed for Godot 4.5 branch multiplayer API:
  - `./run_game.sh --headless --script res://scripts/tests/enet_single_process_smoke.gd`
- Lobby UI scene exists at `scenes/Lobby.tscn` for local mode selection and queue->match flow.
- Lobby scene performs real HTTP flow: `hello -> auth -> queue_join -> queue_status -> match_assigned`.
- Server-side command guardrails in `GameWorld`: actor ownership, per-actor rate limiting, replay sequence drop, future timestamp drop.
- Local-player-by-actor-id binding is implemented in `World` (HUD/camera/game-over/input actor routing).
- Actor lifecycle registration/unregistration API is available in `GameWorld`.
- Reconciliation primitives are wired: `state_ack` and `resync_request`.
- Environment-based startup is supported for this binary:
  - `NEON_MODE=offline_ai|mixed|human_only`
  - `NEON_NETWORK_ROLE=offline|client|server`
  - `NEON_TRANSPORT=local|enet`
  - `NEON_HOST`, `NEON_PORT`, `NEON_MAX_PLAYERS`, `NEON_SERVER`

Validate protocol examples:
```
./run_game.sh --headless --script res://scripts/tests/network_protocol_validator.gd
```

Validate ENet adapter path:
```bash
./scripts/tests/run_enet_smoke.sh
```

ENet smoke caveat:
- In this sandbox, Godot may crash before ENet smoke script runtime.
- Validate ENet smoke on a normal host runtime before concluding ENet path health.

Deferred for later:
- Compact `state_delta` generation + deterministic client apply path.
- Match director service and server allocation orchestration.
- Full reconnect/session recovery policy.
- Deployment, observability, and load/rollout phases from `TODO.md`.

## Backend Scaffold
- `backend/lobby-service/app.py` provides an in-memory lobby + queue API.

Run:
```bash
cd backend/lobby-service
python3 app.py
```

Note:
- In this sandbox, binding/listening sockets may be restricted; run backend service tests outside sandbox if bind fails.
