# AGENTS.md

Project: Godot 4.5.1 game prototype in `/home/xtechkid/Work/neon.io`.

Quick run:
- `./run_game.sh` (uses `~/Downloads/Godot_v4.5.1-stable_linux.x86_64` or `GODOT_BIN`).

Core scenes:
- `scenes/Main.tscn` -> `scenes/World.tscn`
- `scenes/Player.tscn` is used for both human and AI.

Controls:
- WASD / arrows: move
- E: expand mode, LMB place
- Tab: next slot, `[` (left bracket) previous slot
- Q: toggle range ring
- 1/2/3: buy ammo pack + select weapon (Laser/Stun/Homing)
- R: restart

Gameplay systems:
- Weapons: `scripts/weapons/WeaponSystem.gd`
  - ammo per weapon, auto‑reload from credits when empty (auto_reload=true)
  - ammo packs: Laser (+10/4 credits), Stun (+5/8), Homing (+3/12)
  - homing capped to one active missile at a time
- Projectiles:
  - `scripts/weapons/projectiles/LaserShot.gd` uses shader glow; tracks origin/target
  - `scripts/weapons/projectiles/HomingShot.gd` accelerates over 4s, applies damage on hit, orange glow + trail, self‑destructs
- Player health and AI:
  - `scripts/player/Player.gd` has health, stun, damage flash, `died` signal; AI uses same scene
  - `scripts/ui/HealthBar.gd` draws always‑visible bar with delayed drain
  - `scripts/ai/AIController.gd` handles movement/targeting/dodging; AI profiles (laser/stun/homing/balanced), difficulty ramp (movement scale)
- World:
  - `scripts/world/World.gd` spawns AI players, ramps max AI count over time, free‑for‑all combatants
  - Game over overlay in `scenes/World.tscn` when human dies; press R to restart

Rendering:
- 2D MSAA enabled in `project.godot` (`anti_aliasing/quality/msaa_2d=3`)
- Laser glow shader: `scripts/weapons/projectiles/LaserGlow.gdshader`

Notes:
- AI targets are combatants (group `combatants`) not just player.
- Human player is in group `player`; AI sets `is_ai=true` and removes itself from `player` group.
