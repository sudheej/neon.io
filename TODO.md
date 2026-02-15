# TODO

## Multiplayer + Dedicated Lobby Implementation Plan

## Status Snapshot (Updated 2026-02-15)

### Current Online Status (`--test-human-mode`)
- User-verified now working:
  - both clients in same match with distinct actor ids
  - `conn=1`, `role=client`, `remotes=1`
  - movement replicated both ways
  - weapon/slot/range/expand actions now apply in online mode
- Remaining minor issue:
  - camera recenter/follow has edge-case polish needed around local death/respawn transitions.

### Debug Findings (2026-02-15, this session)
- Root cause identified in `src/infrastructure/network/NetworkAdapter.gd`:
  - `_start_enet_transport()` treated any non-null `multiplayer.multiplayer_peer` as reusable ENet.
  - In runtime this can be a non-ENet default/offline peer, so adapter never called `create_client()` / `create_server()`.
  - Observable symptom from this bug matches blocker: `role=client` with `conn=0`, `remotes=0`, and no UDP listener on expected port.
- Fix implemented:
  - only reuse existing peer when it is actually `ENetMultiplayerPeer`.
  - if an existing non-ENet peer is present, clear it and create fresh ENet peer.
  - added explicit ENet startup logs (`start enet`, `replacing non-ENet peer`, `enet_start_failed`) when `NEON_NET_LOG=1`.
- Verification completed:
  - `./run_game.sh --headless --script res://scripts/tests/enet_single_process_smoke.gd` => PASS.
- Verification still blocked in sandbox:
  - full `./run_game.sh --test-human-mode` external flow cannot be fully validated here due lobby bind restriction (`PermissionError: [Errno 1] Operation not permitted` for Python socket bind in this sandbox).

### Already attempted in this session
- Lobby runtime hardening:
  - changed lobby default bind host to loopback (`LOBBY_HOST=127.0.0.1`) in `backend/lobby-service/app.py`.
  - improved lobby client error text and URL overrides in `src/presentation/lobby/Lobby.gd`.
- Test orchestration:
  - `run_game.sh --test-human-mode` now:
    - starts/ensures lobby,
    - starts dedicated human_only match server,
    - opens two shrink-mode clients (left/right),
    - force-cleans stale lobby/match processes before launch,
    - enables net debug HUD + `NEON_NET_LOG`.
- Replication groundwork:
  - server-side network actor spawn hook added (`GameWorld -> World.spawn_network_human_actor`).
  - world replication path for snapshot/delta apply exists in `src/presentation/world/World.gd`.
- Main startup regression fix:
  - server path no longer forces offline config in `src/presentation/main/Main.gd`.

### Highest-priority next actions
- [ ] Camera polish:
  - tighten local camera recenter/follow on death/respawn actor transitions in online mode.
- [ ] Add one dedicated external-runtime smoke test:
  - boot one headless server + one client and assert `connection_changed(true)` within timeout.
  - fail test if client remains `conn=0`.
- [ ] Add one longer online replication soak:
  - 5+ minute dual-client run and verify no command starvation/jitter regressions.

### Completed in repo
- Protocol contract and examples:
  - `docs/network/protocol_v1.md`
  - `docs/network/examples/*.json`
  - `src/infrastructure/network/NetProtocol.gd`
- Protocol smoke test:
  - `scripts/tests/network_protocol_validator.gd`
- Network adapter implementation:
  - `src/infrastructure/network/NetworkAdapter.gd` (local + ENet path, message routing, version checks)
  - `src/infrastructure/network/LocalNetworkAdapter.gd`
  - fixed ENet startup peer reuse bug (`multiplayer_peer` now reused only when actual ENet peer)
- Online/offline input routing:
  - `src/input/InputSource.gd`
  - movement command uplink throttling in `src/input/HumanInputSource.gd` to prevent non-move command starvation
- Authority checks in `GameWorld` for network-tagged commands:
  - actor ownership
  - rate limiting
  - replay/future-drop
  - plus smoke test `scripts/tests/authority_guard_smoke.gd`
- Lobby + queue scaffold:
  - `backend/lobby-service/app.py` (hello/auth/queue join/leave/status + match_assigned)
  - `src/presentation/lobby/Lobby.gd` (hello -> auth -> queue_join -> poll -> match_assigned flow)
  - `scenes/Lobby.tscn`
- Death -> lobby return hook for online modes:
  - `src/presentation/world/World.gd`
- Local startup mode selection UI:
  - `src/presentation/scenes/Main.tscn` + `src/presentation/main/Main.gd`
  - select `offline_ai` / `mixed` / `human_only` before entering world/lobby
- Multiplayer actor-local binding and lifecycle:
  - local player by `actor_id` wiring for HUD/camera/game-over/input in `World.gd`
  - dynamic actor register/unregister API in `GameWorld.gd`
- Authoritative replication improvements:
  - local actor state now applies from snapshots/deltas (not only remotes)
  - replicated fields now include gameplay-critical data (`xp`, cells, selected weapon, armed cell)
  - client-side network position smoothing for less coarse motion
  - minimap identifies local actor by `actor_id`, showing other human players as enemies
- Reconciliation primitives:
  - `state_ack` + `resync_request` support in `NetProtocol.gd` / `NetworkAdapter.gd` / `GameWorld.gd`
- ENet single-process smoke fix:
  - `scripts/tests/enet_single_process_smoke.gd` now passing in-repo

### Important caveats
- ENet single-process smoke script is now fixed and passing (`scripts/tests/enet_single_process_smoke.gd`), but full external-runtime ENet validation is still required outside sandbox.
- Backend runtime socket bind could not be validated in this sandbox (permission restriction), though Python compile passes.
- A critical local-input regression was fixed: local commands must bypass network authority checks unless payload includes `__net`.
- Camera follow still has a minor online respawn edge case pending polish.

This is the execution plan for:
- VPC-hosted backend.
- Match servers with max `10` active players.
- Overflow players waiting in lobby.
- On death: player exits match and returns to lobby queue.
- Game modes:
  - `offline_ai` (single-player, no server dependency)
  - `mixed` (humans + AI fill)
  - `human_only` (no AI)

### Delivery Rules (for all agents)
- Keep gameplay simulation authoritative on server for online modes.
- Keep `offline_ai` path fully local and playable with no backend.
- Do not merge partial protocol changes without version bump.
- For each completed phase:
  - update docs,
  - add/adjust smoke tests,
  - run `./run_game.sh` and verify no new script/runtime errors.

### Suggested Workstreams
- `WS-A` Godot transport + replication (`src/infrastructure/network`, `src/domain/world`, `src/presentation/world`).
- `WS-B` Lobby/match backend service (new `backend/` service tree).
- `WS-C` Deployment/ops (VPC, networking, observability).
- `WS-D` QA/load/perf and rollout.

---

## Phase 0 - Project Setup and Contracts

### P0.1 Lock architecture decisions
- [ ] Record ADR: authoritative Godot match servers + separate lobby/matchmaker service.
- [ ] Record transport decision:
  - match traffic: ENet/UDP
  - lobby traffic: WebSocket or HTTPS + polling
- [ ] Define global limits:
  - active match capacity = `10`
  - lobby wait queue behavior = FIFO (per mode queue)
- [ ] Define reconnect policy and timeout windows.

### P0.2 Protocol versioning baseline
- [x] Create protocol version string (e.g. `net.v1`).
- [ ] Add compatibility matrix doc: client version <-> backend version.
- [x] Add reject behavior for mismatched versions.

### Exit criteria
- [ ] ADR merged.
- [ ] Protocol versioning policy merged.
- [ ] Team agrees on queue and reconnect behavior.

---

## Phase 1 - Wire Protocol and Shared Schemas

### P1.1 Message catalog
- [x] Define canonical messages:
  - `hello`, `auth`, `queue_join`, `queue_leave`, `queue_status`
  - `match_assigned`, `match_join`, `match_join_ack`
  - `player_command`, `state_snapshot`, `state_delta`, `game_event`
  - `player_died`, `match_exit`, `return_to_lobby`
  - `heartbeat`, `disconnect_reason`, `error`

### P1.2 Schema details
- [x] Define required fields for every message:
  - `msg_type`, `protocol_version`, `session_id`, `player_id`, `timestamp_ms`, `seq`.
- [x] Normalize Godot vector-like payloads for transport:
  - `Vector2 -> {"x": float, "y": float}`
  - `Vector2i -> {"x": int, "y": int}`
- [x] Add command schema for every `GameCommand` type.
- [x] Add server event schema for kill/death/score/lobby-return.

### P1.3 Reliability/channel mapping
- [x] Assign delivery guarantees:
  - unreliable ordered: movement commands/snapshot deltas
  - reliable: lifecycle/events/match transitions
- [x] Define resend/ack strategy for reliable messages.

### Exit criteria
- [x] `docs/network/protocol_v1.md` committed.
- [x] JSON examples committed for every message.
- [x] At least one parser/validator test per message type.

---

## Phase 2 - Dedicated Match Server Runtime (Godot)

### P2.1 Server boot mode
- [x] Add startup config for dedicated server role:
  - `--server`
  - `--mode=<mixed|human_only>`
  - `--max-players=10`
  - `--match-id=<id>`
- [x] Ensure headless-safe runtime path (no UI assumptions).

### P2.2 Scene/server boundaries
- [ ] Introduce server-only match scene/bootstrap if needed.
- [ ] Ensure `GameWorld` can run without local human input nodes.
- [x] Add dynamic actor spawn/registration API by `actor_id`.

### P2.3 AI policy by mode
- [x] `offline_ai`: existing local behavior unchanged.
- [x] `mixed`: AI fill enabled to target configured occupancy.
- [x] `human_only`: AI spawn disabled.

### Exit criteria
- [ ] Headless server process starts and simulates match loop.
- [ ] No dependency on local UI for authoritative execution.
- [ ] Mode toggles validated in logs.

---

## Phase 3 - Network Adapter Implementation (Game Client + Server)

### P3.1 Replace stubs
- [x] Implement concrete adapter replacing no-op behavior in:
  - `src/infrastructure/network/NetworkAdapter.gd`
  - `src/infrastructure/network/LocalNetworkAdapter.gd` (or create `EnetNetworkAdapter.gd`)
- [x] Support connect/disconnect/error callbacks.
- [x] Implement inbound command/event routing.

### P3.2 Client command uplink
- [x] Route local `HumanInputSource` commands to server in online modes.
- [x] Keep local command queue path for offline mode.
- [x] Stamp commands with sequence numbers and local tick.

### P3.3 Server state downlink
- [x] Send periodic snapshots from authoritative server.
- [x] Add compact delta format for high-frequency updates.
- [x] Add full snapshot fallback on desync or late join.

### Exit criteria
- [x] Two online clients can connect and receive authoritative state.
- [x] Command->apply path observed on server with actor ownership checks.
- [ ] Snapshot stream stable for 5+ minutes without fatal errors.

---

## Phase 4 - Authoritative Gameplay Refactor for Online Modes

### P4.1 Eliminate single-local-player assumptions
- [x] Refactor `src/presentation/world/World.gd` to support:
  - local controlled actor reference (not hardcoded `$Player` semantics)
  - multiple human actors in combatants
- [x] Refactor HUD/camera to bind to local actor id.
- [x] Refactor game-over flow to local-player death, not global hard stop unless mode requires.

### P4.2 Server authority checks
- [x] Validate incoming command actor ownership.
- [x] Add per-client command rate limiting.
- [x] Drop invalid/replayed/future commands.

### P4.3 Determinism and reconciliation guardrails
- [x] Add server tick id in every snapshot.
- [x] Track client acked snapshot/tick.
- [x] Add server-triggered resync path.

### Exit criteria
- [ ] 10 concurrent humans supported in one match process.
- [ ] Cheating via client-side state mutation is ineffective.
- [ ] Local UI follows local player in multiplayer correctly (minor camera respawn edge case remains).

---

## Phase 5 - Lobby + Queue Service (Backend)

### P5.1 Service foundation (new backend service)
- [x] Create backend project scaffold (recommended `backend/lobby-service/`).
- [x] Implement session/auth bootstrap (anonymous token first, upgrade later).
- [x] Implement mode-separated queues:
  - queue `mixed`
  - queue `human_only`

### P5.2 Queueing semantics
- [x] Enforce active match cap = 10.
- [x] Overflow players remain in waiting lobby queue.
- [x] Implement queue status events:
  - position estimate
  - queue size
  - matchmaking ETA bucket

### P5.3 Match assignment
- [ ] Integrate with match director (Phase 6).
- [x] Emit `match_assigned` with endpoint + match token.
- [x] Handle assignment expiration and retry.

### Exit criteria
- [ ] Players can join/leave queues reliably.
- [ ] Overflow behavior works consistently at/over 10 active.
- [ ] Assignment payload consumed by client successfully.

---

## Phase 6 - Match Director and Server Allocation

### P6.1 Allocation strategy v1
- [ ] Implement simple allocator:
  - find available server with free slots
  - or boot new match server process/container
- [ ] Add mode constraints to allocation.

### P6.2 Server registration/health
- [ ] Match servers register heartbeat to director.
- [ ] Director tracks:
  - server state (`booting`, `ready`, `full`, `draining`, `dead`)
  - active players count
  - mode

### P6.3 Capacity policy
- [ ] Keep hard cap `10` active players per match.
- [ ] Place over-cap into lobby wait state.
- [ ] Optionally define multiple simultaneous matches per mode.

### Exit criteria
- [ ] Director can allocate and recycle match servers.
- [ ] Full servers are never over-assigned.
- [ ] Dead/unhealthy servers are removed from rotation.

---

## Phase 7 - Death -> Return to Lobby Loop

### P7.1 Match-side death terminal event
- [ ] On local player death (online), server emits `player_died` + `match_exit`.
- [x] Client transitions out of match scene to lobby scene.

### P7.2 Lobby re-entry flow
- [x] Client auto re-queues in previous selected mode (configurable).
- [x] Preserve user-selected mode unless manually changed.
- [x] Add cooldown/rate limit to prevent rapid queue churn abuse.

### Exit criteria
- [ ] Dead players reliably return to lobby and queue again.
- [ ] No stuck states between match and lobby transitions.

---

## Phase 8 - Mode Completion

### P8.1 `offline_ai`
- [ ] Ensure zero backend dependency and instant local start.
- [ ] Keep all current AI/world systems functional.

### P8.2 `mixed`
- [ ] Allow humans up to cap with AI fill.
- [ ] Define AI fill target policy:
  - fixed minimum occupancy, or
  - dynamic based on current humans.

### P8.3 `human_only`
- [ ] Disable AI spawn.
- [ ] Start thresholds:
  - either strict 10 players, or
  - configurable minimum start count.

### Exit criteria
- [ ] All three modes selectable and functioning end-to-end.
- [ ] Behavior matches documented design contracts.

---

## Phase 9 - Deployment in VPC

### P9.1 Network topology
- [ ] Public ingress for lobby service (TLS).
- [ ] Controlled UDP ingress for match servers.
- [ ] Private subnets for internal services/datastore.

### P9.2 Security baseline
- [ ] Security groups/firewall least-privilege rules.
- [ ] Secret storage for service credentials.
- [ ] TLS cert rotation policy.

### P9.3 Runtime packaging
- [ ] Containerize headless Godot match server.
- [ ] Containerize lobby/director services.
- [ ] Define environment variable contract.

### Exit criteria
- [ ] Internet clients can connect lobby and play match in VPC.
- [ ] No internal datastore publicly exposed.

---

## Phase 10 - Observability, Operations, and Resilience

### P10.1 Metrics
- [ ] Emit:
  - queue depth, wait time, assignments/sec
  - active matches, players/match
  - server tick duration, command drop rate
  - packet loss/RTT buckets

### P10.2 Logs and tracing
- [ ] Correlation ids: `session_id`, `match_id`, `player_id`.
- [ ] Structured logs across client/lobby/director/match.

### P10.3 Failure handling
- [ ] Graceful reconnect window.
- [ ] Match server crash handling -> return survivors to lobby.
- [ ] Circuit breaker/backoff for lobby->director dependencies.

### Exit criteria
- [ ] On-call dashboard and alert thresholds exist.
- [ ] Simulated failures do not strand players permanently.

---

## Phase 11 - QA and Load Validation

### P11.1 Automated tests
- [ ] Protocol encode/decode tests.
- [ ] Authority validation tests.
- [ ] Queue fairness and overflow behavior tests.

### P11.2 Soak/load tests
- [ ] 10 active + waiting overflow scenario.
- [ ] Repeated death->requeue cycles.
- [ ] Mode-switch churn and reconnect storm tests.

### P11.3 Release gating
- [ ] Define SLOs:
  - lobby connect success
  - match join success
  - median queue wait
  - crash-free session rate

### Exit criteria
- [ ] Load test report published.
- [ ] SLO targets met for launch gate.

---

## Phase 12 - Rollout Plan

### P12.1 Incremental launch
- [ ] Internal playtest (dev-only backend).
- [ ] Closed alpha with low concurrency cap.
- [ ] Gradual ramp of queue limits and match fleet.

### P12.2 Rollback readiness
- [ ] Feature flags:
  - disable online modes
  - disable `human_only`
  - force `offline_ai` fallback
- [ ] One-command rollback procedure documented.

### Exit criteria
- [ ] Controlled rollout complete.
- [ ] Post-launch incident playbook finalized.

---

## Parallelizable Starter Tasks (good first picks)

- [x] Implement protocol doc + examples (`Phase 1`).
- [x] Implement concrete `NetworkAdapter` skeleton with connect/disconnect callbacks (`Phase 3`).
- [x] Refactor world to local-player-by-id abstraction (`Phase 4`).
- [x] Scaffold backend lobby service and queue endpoints (`Phase 5`).
- [ ] Build match director registry + heartbeat model (`Phase 6`).
- [x] Add death->lobby scene transition state machine (`Phase 7`).

---

## Multi-Session Implementation Plan (ordered)

### Session A - Replication and Client Apply Path
1. [x] Implement compact delta generation in `NetworkAdapter`/`GameWorld` (`P3.3`).
2. [x] Implement client-side snapshot+delta apply path in `World.gd` for non-local actors.
3. Add divergence detection test cases and long-run snapshot stability smoke.
Exit criteria:
- Two clients stay visually synchronized for 5+ minutes.

### Session B - Dedicated Match Runtime Hardening
1. Remove remaining local input dependencies from server-authoritative headless path (`P2.2`).
2. Add/validate server-only bootstrap scene if needed for clean process role separation.
3. Validate mode toggles (`mixed`/`human_only`) and AI policy in server logs.
Exit criteria:
- Headless server runs authoritative loop without UI/human input assumptions.

### Session C - Match Director v1
1. Build director service (server registry, heartbeat, lifecycle state machine) (`P6`).
2. Add allocator that respects mode and hard cap=10.
3. Integrate lobby assignment with director endpoints.
Exit criteria:
- Full/draining/dead servers are never assigned; new matches allocate correctly.

### Session D - Death/Exit/Requeue End-to-End
1. Emit and consume `player_died` + `match_exit` from authoritative server (`P7.1`).
2. Add stuck-state guards and retry windows for lobby re-entry (`P7` exit criteria).
Exit criteria:
- Repeated death->requeue cycles do not strand players.

### Session E - Scale, Ops, and Launch
1. Complete deployment packaging and VPC networking baseline (`P9`).
2. Add observability + SLO dashboards (`P10`).
3. Run load/soak + rollout gates (`P11`/`P12`).
Exit criteria:
- 10 active + overflow scenario validated with rollback-ready release process.

## Next Session Priorities (immediate)

1. [x] Session A step 1: implement compact `state_delta` format + tests.
2. [x] Session A step 2: apply remote actor replication in `World.gd`.
3. Validate ENet E2E outside sandbox using `scripts/tests/run_enet_smoke.sh`.

---

## Legacy Gameplay Backlog (pre-multiplayer, optional)

- [ ] Tune orb drop distribution by game phase.
- [ ] Add orb telemetry fields (`orbs_spawned`, `orbs_consumed`, `orb_type_breakdown`, `denied_orbs`).
- [ ] Add visible surge indicator in HUD.
- [ ] Add derived telemetry metrics (credits delta, kill tempo, low-credit duration).
- [ ] Improve HUD clarity for combo and low-credit stipend.
