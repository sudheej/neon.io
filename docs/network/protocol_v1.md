# Network Protocol v1 (`net.v1`)

This document defines the first shared wire contract for lobby + match traffic.

## Envelope
Every message must include:
- `msg_type` (string)
- `protocol_version` (string, currently `net.v1`)
- `session_id` (string)
- `player_id` (string)
- `timestamp_ms` (int)
- `seq` (int, monotonically increasing per sender)
- `payload` (object)

If `protocol_version` does not match exactly, receivers reject the message with `error` / `disconnect_reason`.

## Transport Split
- Lobby/control plane: reliable transport (WebSocket or HTTPS polling).
- Match/simulation plane: ENet/UDP.

## Message Catalog
- Lifecycle/auth:
  - `hello`, `auth`, `heartbeat`, `disconnect_reason`, `error`
- Queue/lobby:
  - `queue_join`, `queue_leave`, `queue_status`, `match_assigned`
- Match join/flow:
  - `match_join`, `match_join_ack`, `match_exit`, `return_to_lobby`, `player_died`
- Gameplay replication:
  - `player_command`, `state_snapshot`, `state_delta`, `state_ack`, `resync_request`, `game_event`

## Reliability and Ordering
- Reliable:
  - `hello`, `auth`, `queue_*`, `match_*`, `player_died`, `return_to_lobby`, `disconnect_reason`, `error`, critical `game_event`
- Unreliable ordered:
  - high-frequency `player_command`, `state_delta`
- Snapshot fallback:
  - `state_snapshot` sent periodically and on desync/late-join.
  - clients send `state_ack` with latest snapshot tick.
  - clients may send `resync_request` when delta stream gaps exceed threshold.

## Payload Conventions
- `Vector2` and `Vector2i` must be encoded as objects:
  - `{"x": <number>, "y": <number>}`
- Commands use domain shape:
  - `{"type": <GameCommand.Type int>, "actor_id": "...", "payload": {...}}`

## Compatibility
- Client and backend must share the same `protocol_version`.
- Do not deploy partial schema changes without bumping protocol version.
- Recommended reject flow for mismatch:
  1. Send `error` with reason `protocol_mismatch`.
  2. Send `disconnect_reason`.
  3. Terminate connection.
