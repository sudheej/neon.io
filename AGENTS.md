# AGENTS.md

Project: Godot 4.5.1 game prototype in `/home/xtechkid/Work/neon.io`.

Quick run:
- `./run_game.sh` (uses `~/Downloads/Godot_v4.5.1-stable_linux.x86_64` or `GODOT_BIN`).
- When suggesting playtests, run `./run_game.sh` first and check the console for errors before recommending the user play.
- `./run_game.sh --verbose` is supported for troubleshooting.
- Always run `./run_game.sh` and confirm stdout has no errors before presenting any next steps.
- Startup opens mode selection UI first (`offline_ai` / `mixed` / `human_only`) unless auto-bypassed in headless/server/env-driven runs.
- Test orchestration shortcuts:
  - `./run_game.sh --test-human-mode` starts lobby + human_only server + two clients.
  - `./run_game.sh --test-mixed-mode` starts lobby + mixed server + test clients.
  - both test modes enable net debug HUD (`match`, `actor`, `remotes`, `conn`, `role`) and net logs.
  - mixed test defaults `MIN_PLAYERS_TO_START_MIXED=2` unless explicitly overridden, so both clients land in the same match.

Core scenes:
- `scenes/Main.tscn` -> `scenes/World.tscn` (wrappers for `src/presentation/scenes/*`)
- `scenes/Player.tscn` is used for both human and AI.

Architecture (new):
- `src/domain/world/GameWorld.gd` is the command boundary.
- Input pipeline: `InputSource -> CommandQueue -> GameWorld.apply(command) -> Events -> Presentation`.
- Agent boundary: `src/infrastructure/agent/AgentBridge.gd` + `LocalAgentStub.gd` (disabled by default).
- Network boundary: `src/infrastructure/network/NetworkAdapter.gd` (concrete local + ENet path).

Controls:
- WASD / arrows: move
- Hold Shift: show expansion outlines (from active cell)
- While holding Shift + direction (WASD/arrows): expand or select active cell
- Tab: next slot, `[` (left bracket) previous slot
- Q: toggle range ring
- 1/2/3/4: buy ammo pack + select weapon (Laser/Stun/Homing/Spread)
- R: restart

Gameplay systems:
- Weapons: `scripts/weapons/WeaponSystem.gd` (wrapper for `src/presentation/weapons/WeaponSystem.gd`)
  - ammo per weapon, auto‑reload from credits when empty (auto_reload=true)
  - ammo packs: Laser (+15/4 credits), Stun (+8/6), Homing (+5/7), Spread (+9/5)
  - homing capped per player (up to one active missile per cell)
  - stun shots are green (custom beam/core color passed to `LaserShot`)
  - spread weapon: purple primary beam (75% of laser damage); on impact, spawns slim purple beams from impact center to nearby enemies (50% laser damage) within SPREAD_RADIUS
  - on game start, Stun and Spread auto-buy one pack (deducts credits)
  - global weapon selection: all cells fire the currently selected weapon
  - starting ammo: Laser 40, Stun 16, Homing 8, Spread 14
  - `add_weapon_ammo(weapon_type, amount)` respects weapon capacity (used by orb pickups)
- Projectiles:
  - `scripts/weapons/projectiles/LaserShot.gd` (wrapper) uses shader glow; tracks origin/target
    - plays randomized theremin laser SFX, distance‑attenuated; AudioStreamPlayer2D is parented to world to avoid being freed early
    - loads audio via `.import` remap (uses `res://.godot/imported/*.oggvorbisstr`) because this Godot binary does not load raw `.wav`/`.ogg`
    - supports flicker/jitter per beam for visual differentiation (used by spread beams)
  - `scripts/weapons/projectiles/HomingShot.gd` accelerates over 4s, applies damage on hit, orange glow + trail, self‑destructs
- Player health and AI:
  - `scripts/player/Player.gd` (wrapper) has health, stun, damage flash, `died` signal; AI uses same scene
    - human player takes reduced damage (`HUMAN_DAMAGE_MULTIPLIER`) so health drops slower than AI
    - expansion armor: extra cells reduce incoming damage (4% per cell, capped at 40%)
    - health regen after no damage (`regen_delay`, `regen_rate`)
    - kill reward formula (for killer): base 6.5 + 2.0 per victim extra cell, capped at 20 before world multiplier
    - kill combo bonus: 4s chain window, +1 per chained kill, capped +4
    - low-credit safety net: if credits < 10, +2 credits every 5s
    - low-health alert: `critical.wav` plays when health drops into critical zone (currently 40% threshold with cooldown)
    - soft collision separation between combatants with small repel ripple effect
  - `scripts/ui/HealthBar.gd` draws always‑visible bar with delayed drain
    - drain lerp is slower for the human player
  - `scripts/ai/AIController.gd` handles movement/targeting/dodging; AI profiles (laser/stun/homing/balanced), difficulty ramp (movement scale)
    - AI movement starts slower and ramps more gradually (RAMP_TIME 120s, scale 0.35→0.9)
    - AI now evaluates nearby boost orbs with profile/state-aware priorities (health missing, ammo need by weapon, low credits, local pressure)
    - AI may commit to orb pickups at close range, otherwise blends orb-seeking with combat movement
- World:
  - `scripts/world/World.gd` (wrapper) spawns AI players, ramps max AI count over time, free‑for‑all combatants
  - enemy spawn is no longer purely player-centric:
    - can spawn farther from player
    - can spawn around active action anchors (existing enemies or boost orbs)
  - timed surge events: every 36s cycle, 8s surge window with faster spawn cadence (`SPAWN_INTERVAL * 0.7`)
  - danger kill-reward multiplier: 1.35 during first 6s of each 25s ramp cycle
  - telemetry prints every 10s and on death; includes credits/cells/expansions/enemies/surge/weapon usage
  - `--no-telemetry` disables telemetry prints
  - Game over overlay in `scenes/World.tscn` when human dies; press R to restart
  - Game over shows Time Survived in hh:mm:ss with pulsing animation (`GameOver/TimeSurvived`)
  - camera centers on active cell with smoothed follow
    - online mode currently has a minor camera recenter/follow edge case around local death/respawn transitions (tracked in `TODO.md`)
  - boost orbs (`src/presentation/world/BoostOrb.gd`) spawn when any combatant dies:
    - types: XP, weapon-specific ammo, health
    - ammo orb color maps to weapon color (laser cyan, stun green, homing orange, spread purple)
    - orb value scales with victim value (survival time + credits + cell count), with capped visual diameter
    - both player and AI can consume; if full/capped, touching still invalidates orb (CRT-style collapse/fade)
    - health orb renders `+`, XP orb renders `$`
    - lifetime: 20s

Rendering:
- 2D MSAA enabled in `project.godot` (`anti_aliasing/quality/msaa_2d=3`)
- Laser glow shader: `scripts/weapons/projectiles/LaserGlow.gdshader` (wrapper for `src/presentation/weapons/projectiles/LaserGlow.gdshader`)

Notes:
- AI targets are combatants (group `combatants`) not just player.
- Human player is in group `player`; AI sets `is_ai=true` and removes itself from `player` group.
- Minimap local/enemy rendering in multiplayer is actor-id based:
  - local actor (`SessionConfig.local_actor_id`) renders as player marker
  - all other combatants (including other humans) render as enemy markers
- This Godot binary reports AudioStream extensions: `tres`, `res`, `sample`, `oggvorbisstr`, `mp3str`; raw `.wav`/`.ogg` do not load without import.
- Arrow keys use Godot 4 keycodes in `project.godot` (UP 4194320, DOWN 4194322, LEFT 4194319, RIGHT 4194321).
- Debug: run `./run_game.sh --collision-debug` to draw collision overlay and print collision distances.
- Economy: starting credits 250; expansion cost 60 credits per cell.
- Event audio:
  - `critical.wav` and `powerup.wav` live under `assets/audio/ui/`
  - `powerup.wav` is intentionally disabled in gameplay flow for now
  - run `./run_game.sh --headless --import` after moving/adding audio assets to refresh `.import` remaps
- Multiplayer phased implementation and handoff status are tracked in `TODO.md` (use it as source of truth for pending/complete).
- `--test-human-mode` current expected HUD state after queueing both clients:
  - same `match`, different `actor`, `conn=1`, `role=client`, `remotes=1`
- `--test-mixed-mode` current expected HUD state after queueing both clients:
  - same `match`, different `actor`, `conn=1`, `role=client`, `remotes=1`
