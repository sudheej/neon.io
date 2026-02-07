# AGENTS.md

Project: Godot 4.5.1 game prototype in `/home/xtechkid/Work/neon.io`.

Quick run:
- `./run_game.sh` (uses `~/Downloads/Godot_v4.5.1-stable_linux.x86_64` or `GODOT_BIN`).
- When suggesting playtests, run `./run_game.sh` first and check the console for errors before recommending the user play.
- `./run_game.sh --verbose` is supported for troubleshooting.
- Always run `./run_game.sh` and confirm stdout has no errors before presenting any next steps.

Core scenes:
- `scenes/Main.tscn` -> `scenes/World.tscn` (wrappers for `src/presentation/scenes/*`)
- `scenes/Player.tscn` is used for both human and AI.

Architecture (new):
- `src/domain/world/GameWorld.gd` is the command boundary.
- Input pipeline: `InputSource -> CommandQueue -> GameWorld.apply(command) -> Events -> Presentation`.
- Agent boundary: `src/infrastructure/agent/AgentBridge.gd` + `LocalAgentStub.gd` (disabled by default).
- Network boundary: `src/infrastructure/network/NetworkAdapter.gd` (stub).

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
  - ammo packs: Laser (+15/4 credits), Stun (+8/8), Homing (+5/12), Spread (+9/6)
  - homing capped per player (up to one active missile per cell)
  - stun shots are green (custom beam/core color passed to `LaserShot`)
  - spread weapon: purple primary beam (75% of laser damage); on impact, spawns slim purple beams from impact center to nearby enemies (50% laser damage) within SPREAD_RADIUS
  - on game start, Stun and Spread auto-buy one pack (deducts credits)
  - global weapon selection: all cells fire the currently selected weapon
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
    - soft collision separation between combatants with small repel ripple effect
  - `scripts/ui/HealthBar.gd` draws always‑visible bar with delayed drain
    - drain lerp is slower for the human player
  - `scripts/ai/AIController.gd` handles movement/targeting/dodging; AI profiles (laser/stun/homing/balanced), difficulty ramp (movement scale)
    - AI movement starts slower and ramps more gradually (RAMP_TIME 120s, scale 0.35→0.9)
- World:
  - `scripts/world/World.gd` (wrapper) spawns AI players, ramps max AI count over time, free‑for‑all combatants
  - Game over overlay in `scenes/World.tscn` when human dies; press R to restart
  - Game over shows Time Survived in hh:mm:ss with pulsing animation (`GameOver/TimeSurvived`)
  - camera centers on active cell with smoothed follow

Rendering:
- 2D MSAA enabled in `project.godot` (`anti_aliasing/quality/msaa_2d=3`)
- Laser glow shader: `scripts/weapons/projectiles/LaserGlow.gdshader` (wrapper for `src/presentation/weapons/projectiles/LaserGlow.gdshader`)

Notes:
- AI targets are combatants (group `combatants`) not just player.
- Human player is in group `player`; AI sets `is_ai=true` and removes itself from `player` group.
- This Godot binary reports AudioStream extensions: `tres`, `res`, `sample`, `oggvorbisstr`, `mp3str`; raw `.wav`/`.ogg` do not load without import.
- Arrow keys use Godot 4 keycodes in `project.godot` (UP 4194320, DOWN 4194322, LEFT 4194319, RIGHT 4194321).
- Debug: run `./run_game.sh --collision-debug` to draw collision overlay and print collision distances.
- Economy: starting credits 450; expansion cost 50 credits per cell.
- Starting ammo: 50 for all weapon types.
