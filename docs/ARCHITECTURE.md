# Architecture Notes

## Core Flow
```
InputSource -> CommandQueue -> GameWorld.apply(command) -> Events
                                          |
                                          +-> GameState snapshot -> Agent/Network
```

## Responsibilities
- `GameWorld` is the authoritative command boundary.
- Presentation nodes (`World`, `Player`, `WeaponSystem`, UI) remain scene-driven.
- Infrastructure boundaries (`AgentBridge`, `NetworkAdapter`) are stubs that can be swapped without touching gameplay logic.

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
