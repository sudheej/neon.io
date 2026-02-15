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

## Current Live Blocker (2026-02-15 Handoff)
- In `./run_game.sh --test-human-mode`, both clients show:
  - same `match_id`
  - different `actor_id`
  - `conn=0`, `role=client`, `remotes=0` in net debug HUD
- Interpretation:
  - lobby assignment works,
  - authoritative ENet client->server connection is not established (or immediately dropped),
  - therefore no replicated remote actors appear and movement commands do not apply online.
- User screenshot reference:
  - `/home/xtechkid/Pictures/multiplayer_same_lobby_issue.png`

### Test-mode wiring currently in place
- `run_game.sh --test-human-mode` now does all of:
  - kills stale lobby/match server processes before launch,
  - starts lobby service if missing,
  - starts dedicated human_only match server (`NEON_SERVER=1`, `NEON_NETWORK_ROLE=server`, ENet transport),
  - launches two clients with shrink-mode windows (left/right),
  - enables network debug HUD (`match/actor/remotes/conn/role`) and net logs.

### Handoff debug checklist
- Server process:
  - confirm it loads `World`, not `Lobby`.
  - confirm `NetworkAdapter` server role starts ENet and binds UDP 7000.
- Client process:
  - confirm `NetworkAdapter` receives `connected_to_server`.
  - inspect connection failure/disconnect reasons in client logs.
- Artifacts to inspect first:
  - `/tmp/neon_human_server.log`
  - `/tmp/neon_human_client_1.log`
  - `/tmp/neon_human_client_2.log`
  - `/tmp/neon_lobby.log`

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
      {"id": "player", "position": Vector2, "health": 40, "max_health": 40, "is_ai": false}
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
- Remote actor state apply/render path in `World` from authoritative snapshots/deltas.
- Compact server delta generation and deterministic delta apply semantics.
- Dedicated match director service (registry + heartbeat + allocator) between lobby and match fleet.
- Reconnect/session recovery window with actor ownership reclaim policy.

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
