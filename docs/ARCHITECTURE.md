# Architecture Notes

## Core Flow
```

## Session Bootstrap (for new agents)
Use this sequence before making changes:
1. `./run_game.sh --headless --script res://scripts/tests/network_protocol_validator.gd`
2. `./run_game.sh --headless --script res://scripts/tests/authority_guard_smoke.gd`
3. `timeout 12 ./run_game.sh`
InputSource -> CommandQueue -> GameWorld.apply(command) -> Events
                                          |
                                          +-> GameState snapshot -> Agent/Network

Presentation World Loop:
  combatants -> weapon processing -> boost orb processing -> HUD/announcements -> spawning
```

## Responsibilities
- `GameWorld` is the authoritative command boundary.
- Presentation nodes (`World`, `Player`, `WeaponSystem`, UI) remain scene-driven.
- Infrastructure boundaries (`AgentBridge`, `NetworkAdapter`) are stubs that can be swapped without touching gameplay logic.
- `World` owns dynamic encounter systems: enemy spawning, surge pacing, telemetry, and boost-orb lifecycle.
- `BoostOrb` is a presentation-world entity that encapsulates drop type/value, visual state, pickup overlap checks, and consume/invalidate behavior.
- `NetProtocol` (`src/infrastructure/network/NetProtocol.gd`) defines `net.v1` envelope validation and transport payload normalization.

## Startup Flow
- `Main` scene is now a mode-selection entry point:
  - `offline_ai` -> loads `World`.
  - `mixed` / `human_only` -> loads `Lobby` queue flow.
- Non-interactive startup bypasses menu for server/headless/env-driven runs.

## Current Multiplayer State (2026-02-16)
- `./run_game.sh --test-human-mode` reaches connected client state:
  - same `match_id`, distinct `actor_id`
  - `conn=1`, `role=client`, `remotes=1`
- `./run_game.sh --test-mixed-mode` reaches connected client state:
  - same `match_id`, distinct `actor_id`
  - `conn=1`, `role=client`, `remotes=1`
- Online command path verified for:
  - movement
  - weapon select + HUD sync per local actor
  - slot/range actions
  - shift+direction expansion actions
- Respawn/replication stability fixes are in place:
  - client applies `actors_remove` before `actors_upsert` to avoid stale-node respawn races
  - local actor is recreated correctly after remove/upsert cycles
  - queued-for-deletion combatants are ignored for actor lookup/rebinding
  - dedicated server ignores local game-over path on actor death (prevents global combat freeze)
  - network-driven player hit flash now decays (no persistent red bar tint)
- Remaining known polish item:
  - camera follow/recenter edge case around local death/respawn transitions.

### Test-mode wiring currently in place
- `run_game.sh --test-human-mode` now does all of:
  - kills stale lobby/match server processes before launch,
  - starts lobby service if missing,
  - starts dedicated human_only match server (`NEON_SERVER=1`, `NEON_NETWORK_ROLE=server`, ENet transport),
  - launches two clients with shrink-mode windows (left/right),
  - enables network debug HUD (`match/actor/remotes/conn/role`) and net logs.
- `run_game.sh --test-mixed-mode` now does all of:
  - kills stale lobby/match server processes before launch,
  - starts lobby service if missing,
  - starts dedicated mixed match server (`NEON_SERVER=1`, `NEON_NETWORK_ROLE=server`, ENet transport),
  - launches test clients (default 2, configurable/clamped with `NEON_TEST_MIXED_CLIENT_COUNT`),
  - defaults lobby mixed queue start threshold to 2 players in test mode (unless explicitly overridden) to ensure same-match assignment,
  - enables network debug HUD (`match/actor/remotes/conn/role`) and net logs.

### Recent implementation updates
- `NetworkAdapter` ENet startup now reuses `multiplayer_peer` only when it is an actual `ENetMultiplayerPeer`; otherwise it resets and creates ENet explicitly.
- `HumanInputSource` now throttles move uplink to avoid starving non-move commands under authority rate limits.
- Snapshot/delta replication now includes gameplay-critical actor fields:
  - `xp`
  - `cells`
  - `selected_weapon`
  - `armed_cell`
- `World` applies local actor authoritative state, adds client-side position smoothing, and updates minimap local/enemy classification by `actor_id`.

## Actor Identity
- Human player uses `actor_id = "player"`.
- AI actors use `actor_id = "ai_<instance_id>"`.
- Commands carry `actor_id` so future networking can route input to the correct entity.
- `SessionConfig.local_actor_id` binds local HUD/camera/input/game-over to the local controlled combatant.

## Command Notes
Expansion is now hold + directional:
- `SET_EXPAND_HOLD` toggles the expansion preview while a key is held.
- `EXPAND_DIRECTION` expands (or selects) the active cell in the given direction.
Legacy expand commands remain for compatibility (`TOGGLE_EXPAND`, `PLACE_CELL`).

## Snapshot Format
```
{
  "tick": <int>,
  "data": {
    "time": <float>,
    "actors": [
      {
        "id": "player",
        "position": Vector2,
        "health": 40,
        "max_health": 40,
        "is_ai": false,
        "xp": 250.0,
        "cells": [{"x": 0, "y": 0}],
        "selected_weapon": 0,
        "armed_cell": {"x": 0, "y": 0}
      }
    ]
  }
}
```

## Multiplayer Wiring
- Local and remote commands both converge through `GameWorld.submit_command`.
- `InputSource` sends commands to queue for offline play, and uplinks through `NetworkAdapter` in online client mode.
- `GameWorld` emits snapshots and gameplay events through `NetworkAdapter`.
- `LocalNetworkAdapter` can loopback commands/state/events for transport simulation without backend dependencies.
- `GameWorld` applies authority checks for network commands: actor ownership binding, per-actor rate limits, replay sequence rejection, and future timestamp rejection.
- `GameWorld` now supports dynamic actor registration/unregistration for multiplayer lifecycle.
- `NetworkAdapter` supports reconciliation primitives:
  - `state_ack` emission/receipt.
  - `resync_request` on delta-gap detection with full snapshot fallback.

## Critical Invariants
- Local/offline commands do not include `payload.__net`; they must bypass network authority validation.
- Only inbound network commands should carry `payload.__net`.
- `InputSource` should route to network only when adapter role is `client` and adapter is connected.
- AI command `actor_id` must match owning actor (`ai_<id>`), never `"player"` for enemy AI.

## Lobby Client Flow
- Lobby scene (`scenes/Lobby.tscn`) queues online modes through backend HTTP endpoints.
- Flow:
  - `POST /v1/hello`
  - `POST /v1/auth`
  - `POST /v1/queue/join`
  - `GET /v1/queue/status` polling until `match_assigned`
- On `match_assigned`, lobby writes session/network settings into `SessionConfig`, then loads `World`.
- Queue flow now includes assignment expiry/requeue and queue join cooldown handling.

## Multi-Session Pending Architecture Work
- Dedicated match director service (registry + heartbeat + allocator) between lobby and match fleet.
- Reconnect/session recovery window with actor ownership reclaim policy.
- Camera follow/recenter polish for local death/respawn transitions in online mode.

## Boost Orbs
- Spawn trigger: any combatant death (`Player.died` signal from player or AI instances).
- Types:
  - XP
  - Ammo (weapon-specific: laser/stun/homing/spread)
  - Health
- Value model:
  - base by type + victim survival-time bonus + victim credit bonus + victim cell-count bonus
  - clamped per type for gameplay and visual readability
- Consumption:
  - all combatants can consume
  - health and ammo respect caps (`max_health`, weapon capacity)
  - if a combatant touches an orb while capped, orb is still invalidated (denial mechanic)
  - invalidation uses a short CRT-like collapse/fade effect
- Pickup geometry:
  - cell-aware overlap against `PlayerShape` cell footprints to avoid premature pickup

## AI Orb Decisions
- `AIInputSource` evaluates nearby `boost_orbs` and scores them by:
  - orb type/value
  - current health deficit
  - weapon-specific ammo need relative to capacity
  - credit state
  - local enemy pressure
  - profile bias (laser/stunner/homing/spreader/balanced)
- Orb-seeking is blended with target-seeking, separation, and dodge vectors.
- Close orbs can trigger stronger commitment for deterministic pickup behavior.

## Spawn Anchors
- Enemy spawning is not strictly player-centric.
- Spawn anchors are selected from:
  - player position (standard/far variants)
  - active action positions (existing enemies or active boost orbs)
- This creates off-screen fights and encounter variety without requiring player proximity.
