# TODO

## Orbs and AI
- Tune orb drop distribution by phase:
  - early game: slightly more ammo/health
  - late game: slightly more XP
- Add orb telemetry fields (`orbs_spawned`, `orbs_consumed`, `orb_type_breakdown`, `denied_orbs`) to measure impact.
- Consider profile-specific orb aggression multipliers so some AI variants are visibly more greedy.
- Add optional debug overlay for orb pickup radius/cell overlap checks.

## Economy and Progression
- Add `--audio-debug` flag for temporary event-sound tracing (`critical` trigger timestamps, combo bonus events), then remove once tuned.
- Tune low-credit safety net after more telemetry samples:
  - candidate knobs: `LOW_CREDIT_THRESHOLD`, `LOW_CREDIT_STIPEND`, `LOW_CREDIT_INTERVAL`
  - goal: reduce dead-economy stalls without trivializing pressure.
- Consider dynamic expansion cost scaling (`cost += per_cell_step`) if late-game slot snowball returns.
- Revisit weapon-specific economy if usage converges too hard on one pair:
  - spread sustain vs homing sustain
  - possible per-weapon kill-reward modifiers.

## Combat Excitement
- Add visible "SURGE" indicator in HUD during active surge window (`surge=1`) so pressure spikes are legible to players.
- Add optional surge variants (faster AI movement vs faster spawn) and A/B them with telemetry.
- Consider small score multiplier tied to surviving surge windows for risk/reward.

## Audio and Feedback
- `powerup.wav` is intentionally disabled in gameplay code for now.
- Keep `critical.wav` as low-health warning; validate loudness/mix relative to weapon SFX.
- If event audio is reintroduced, use non-positional `AudioStreamPlayer` for UI alerts.
- Consider adding dedicated mixer bus for UI alerts to tune independently.

## Telemetry and Analysis
- Keep collecting runs with current fields:
  - `credits`, `cells`, `expansions`, `enemies`, `surge`, weapon usage.
- Add derived metrics in logs:
  - credits delta per 10s
  - kill count per 10s
  - time spent below low-credit threshold.
- Add optional CSV dump mode for batch balancing sessions.

## UX and Clarity
- Show combo chain + bonus in HUD for short duration so bonus logic is understandable.
- Show low-credit stipend tick in HUD (small text pulse) to avoid "hidden mechanic" feeling.
- Color-shift health bar at critical threshold to align with critical audio timing.

## AI Capability Roadmap (Future)

### Phase 3 - Difficulty Matrix + Adaptive Control
- Split difficulty into two axes:
  - `competence` (planning horizon, target selection quality, timing),
  - `execution` (reaction delay, noise, occasional mistakes, commitment quality).
- Define clear tuning bands for `easy`, `normal`, `hard`, `adaptive`.
- Add adaptive pacing controls that adjust pressure/intensity before buffing raw AI precision.
- Ensure fairness guardrails:
  - no omniscient tracking, bounded reaction times, and recoverable failure states for players.

### Phase 4 - A/B Tuning + Validation
- Run structured A/B playtests for persona mixes, planner weights, and difficulty matrices.
- Compare versions using telemetry deltas:
  - survival time distribution, expansions/minute, kill tempo, orb contest rate, perceived unfair deaths.
- Promote only changes that improve both variety and fairness targets.
- Produce a balancing report and lock a v1 AI behavior spec for follow-on feature work.
