# Network Protocol v1 (`net.v1`)

This document defines the first shared wire contract for lobby + match traffic.

## Envelope
Every message must include:
- `msg_type` (string)
- `protocol_version` (string, currently `net.v1`)
- `session_id` (string)
- `player_id` (string)
- `timestamp_ms` (int, Unix epoch milliseconds; never process-relative uptime)
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

## Match Authentication and Identity Binding

The lobby issues a short-lived `match_token` as `base64url(claims).base64url(HMAC-SHA256)`.
Claims bind `match_id`, `session_id`, `player_id`, `actor_id`, and `expires_at_ms`. The
lobby's `MATCH_TOKEN_SECRET` and the dedicated server's `NEON_MATCH_TOKEN_SECRET` must
contain the same high-entropy secret; the secret is never sent to clients. Dedicated
servers also set `NEON_MATCH_ID` and fail closed when no verification secret is present.

After ENet connects, the client sends reliable `match_join` with its signed token and
actor ID. Until the server replies with an accepted `match_join_ack`, the connection is
not application-ready. The server verifies the signature, expiry, match, envelope
session/player, and actor, then binds the ENet peer ID to that identity. Later messages
with a substituted session, player, or command actor are rejected and disconnected.
Snapshots and events are sent only to authenticated peers. Disconnect removes the peer
binding, acknowledgement state, replay sequence, rate-limit state, and actor ownership.

## Payload Conventions
- `Vector2` and `Vector2i` must be encoded as objects:
  - `{"x": <number>, "y": <number>}`
- Commands use domain shape:
  - `{"type": <GameCommand.Type int>, "actor_id": "...", "payload": {...}}`

## Replication Payload Shape (Current)
- `state_snapshot.payload.state.data` includes:
  - `time`
  - `actors`: each actor may contain `id`, `position`, `health`, `max_health`, `is_ai`, `xp`, `cells`, `selected_weapon`, `armed_cell`, `weapon_ammo`
  - `orbs`: each orb contains `id`, `position`, `boost_type`, `weapon_type`, `amount`
- `state_delta.payload.state.data` may include:
  - `actors_upsert`, `actors_remove`
  - `orbs_upsert`, `orbs_remove`

## Compatibility
- Client and backend must share the same `protocol_version`.
- Do not deploy partial schema changes without bumping protocol version.
- Recommended reject flow for mismatch:
  1. Send `error` with reason `protocol_mismatch`.
  2. Send `disconnect_reason`.
  3. Terminate connection.
