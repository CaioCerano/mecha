# Mecha POC — build progress

Built in the spec's 17-step order. Every step kept the project runnable.
All 37 GUT tests green; headless smoke tests drive the real scene through
full turns and every mech action without errors.

## Done

- [x] 1. Scaffold — project.godot (4.7, GL compat), GUT vendored, entry scene
- [x] 2. Grid — `core/grid.gd` + `game/grid_view.gd`, 12×12 checkerboard + walls
- [x] 3. Units + selection — `unit.gd`, `battle_state.gd`, `unit_view.gd`
- [x] 4. Movement range highlight + grid movement — BFS `reachable`, path tween
- [x] 5. Action Points — 2 AP/mech, free activation order
- [x] 6. Turn switching — player ⇄ enemy, End Turn
- [x] 7. Basic enemy — Grunt marches on the reactor
- [x] 8. Basic attacks — cannon / punch / grunt melee, deterministic, no rolls
- [x] 9. Push — `push.gd`, Into-the-Breach knockback + collision damage
- [x] 10. Wall / unit collision — walls, units, deployed shield all stop pushes and lines
- [x] 11. Enemy telegraphs — `telegraph.gd`, Charger + Enemy Artillery, persistent overlays
- [x] 12. Spear Mech — thrust / throw (spear becomes a grid object) / retrieve / punch fallback
- [x] 13. Shield Mech — bash / deploy (real blocking terrain) / retrieve / defensive-bonus toggle
- [x] 14. Artillery Mech — cannon line / mortar (delayed, plus-AoE, clears a wall)
- [x] 15. Reactor objective — `mission.gd`, defend 5 turns, edge spawns, schedule
- [x] 16. Win / loss — reactor dead or squad wiped = loss; turn 5 survived = win; restart
- [x] 17. UI + feedback — HUD (turn/AP/HP/actions/End Turn), full action previews,
        tweens for move / attack / push / spear throw+retrieve / damage / death

## Difficulty shape (verified headless)

- Passive play (End Turn ×5, no actions) → **DEFEAT** on turn 5 — you must engage.
- Simple greedy play (attack what's in reach, else close in) → **VICTORY** with margin.

## Known rough edges / next iteration candidates

- Charger never repositions on its windup turn (kept simple; telegraph is a
  fair full-turn warning). Revisit if chargers feel toothless.
- Enemy-turn playback is sequential and fixed-timed; fine for a POC, could
  batch simultaneous events.
- No sound. Placeholder shapes only, as intended.
- Balance constants (`mission.gd`, `mech_actions.gd`, `enemy_ai.gd`) are
  first-pass — tune against real playtests.
