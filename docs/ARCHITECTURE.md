# Architecture Notes

## Core Flow
```
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

## Actor Identity
- Human player uses `actor_id = "player"`.
- AI actors use `actor_id = "ai_<instance_id>"`.
- Commands carry `actor_id` so future networking can route input to the correct entity.

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
