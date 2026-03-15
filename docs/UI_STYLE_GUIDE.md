# UI Style Guide

This file captures the current UI visual language for the Godot prototype so future sessions can extend screens without drifting style.

## Visual Direction

- Tone: tactical neon HUD over a deep cobalt battlefield.
- Contrast model: dark blue foundations with bright cyan/ice highlights.
- Shape language: rounded panels with subtle glow borders, no heavy drop shadows.
- Motion: slow ambient background movement; UI motion is short and functional.
- Readability first: text remains high-contrast even when panels are translucent.

## Core Color Tokens

Use these as canonical references unless a screen has a strong reason to diverge.

- Gameplay base background: `Color(0.03, 0.05, 0.10, 1.0)`  
  Source: `src/presentation/world/BlueprintGrid.gd`
- Gameplay minor grid: `Color(0.10, 0.20, 0.35, 0.35)`
- Gameplay major grid/accent: `Color(0.20, 0.50, 0.80, 0.55)`

Menu/lobby UI tokens aligned to gameplay palette:

- Main mode-select backdrop: `Color(0.04, 0.07, 0.13, 1)`
- Main mode-select shade overlay: `Color(0.08, 0.14, 0.24, 0.18)`
- Mode card panel fill: `Color(0.08, 0.14, 0.24, 0.76)`
- Mode card border: `Color(0.20, 0.50, 0.80, 0.82)`
- Secondary pill fill: `Color(0.08, 0.14, 0.24, 0.82)`
- Secondary pill border: `Color(0.24, 0.56, 0.86, 0.70)`

Particle backdrop (squares):

- Core field tint: `Color(0.52, 0.78, 1.0, 0.95)`
- Glow field tint: `Color(0.42, 0.68, 0.98, 0.42)`
- Heavy field tint: `Color(0.72, 0.88, 1.0, 0.58)`

## Opacity Rules

- Large panels: alpha `~0.74 - 0.86`
- Secondary chips/pills: alpha `~0.80 - 0.90`
- Background shading overlays: alpha `~0.16 - 0.24`
- Avoid opaque black fills on top-level selection cards.

## Component Aesthetics

- Cards: rounded corners, thin bright border, gentle cyan-blue shadow.
- Borders: bright enough to define hierarchy, never pure white.
- Labels: cool off-white/cyan; selected states increase alpha, not saturation spikes.
- Selected mode emphasis: scale + border alpha increase; keep timing short (`~0.13s`).
- Utility controls: prefer compact, intentional affordances over inline HUD clutter.
- Global settings affordance: bottom-right floating gear icon with no heavy border treatment; clicking opens a compact translucent popup for audio controls.

## Screen Consistency Notes

- Mode-select and lobby should feel like pre-combat UI in the same universe as `World`.
- Prefer cobalt/blue accents over teal/purple drift.
- Keep custom cutout/decorative rects transparent unless intentionally used for a motif.

## Files To Update When Restyling

- `src/presentation/scenes/Main.tscn`
- `src/presentation/main/Main.gd`
- `src/presentation/main/StarfieldBackdrop.gd`
- `src/presentation/scenes/Lobby.tscn`
- `src/presentation/lobby/Lobby.gd`
- `src/presentation/audio/MusicController.gd`
- `src/presentation/world/BlueprintGrid.gd`
- `src/presentation/scenes/World.tscn`

## Guardrails For Future Sessions

- Match hue family to gameplay grid before tuning brightness.
- Increase visibility via alpha/contrast first; avoid returning to near-black overlays.
- If changing perceived brightness, verify both:
  - background effects remain visible
  - text contrast still passes quick visual check at 1080p
- After UI edits, run `./run_game.sh` and confirm stdout has no startup errors.
