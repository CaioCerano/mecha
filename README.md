# Mecha — tactical combat POC

A small Godot 4 proof of concept. **Not a game** — one 5–10 minute mission
built to answer a single design question:

> Is it fun to solve tactical situations using mechs with unusual *physical*
> mechanics — throwing and recovering a spear, deploying a shield into the
> environment, and manipulating enemy positioning?

It borrows turn-based squad control from XCOM, compact telegraphed maps from
Into the Breach, and per-mech identity from Lancer.

## Run it

Open the project in **Godot 4.7.2** and press Play, or:

```
"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --path . run/main.tscn
```

## Tests

Pure-logic core (`core/`) is headless-testable with GUT:

```
"C:\Program Files\Godot\Godot_v4.7.2-stable_win64.exe" --headless -s addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
```

If GUT reports missing class_names, run `--headless --import` once first.

## The mission

Defend the reactor (purple) for **5 turns**. Enemies (red) pour in from the
edges and make for the reactor.

- **Win:** reactor still alive at the end of turn 5.
- **Lose:** reactor HP hits 0, or all three mechs are destroyed.
- You do **not** need to kill everything. Doing nothing loses — you have to
  actively solve each turn.

## Controls

Mouse only. Click a mech (or the squad list) to select it. Each mech has
**2 AP** per turn; spend them across mechs in any order.

- Click a **blue** tile to move (1 AP).
- Click an action button, then a **gold** tile to aim it (1 AP). Right-click
  or Esc cancels aiming. *Retrieving your own spear / shield is free* — the
  cost of throwing or deploying is positional, not AP.
- Hovering a target shows the full preview: attack line, AoE, push
  destination, spear landing cell, which units get hit, and a red outline on
  the reactor if your own shot would clip it.
- Enemy telegraphs (charges, artillery) stay on the board through your turn —
  move out of them, block them, or reposition the enemy before they fire.
- **End Turn** hands control to the enemy.

## The three mechs

| Mech | Identity |
|---|---|
| **Spear** (blue) | *Thrust* — hit, push 1, extra damage if they slam a wall/unit. *Throw Spear* — big straight-line hit, but the spear lands on the grid and you lose Thrust (only a weak *Punch*) until you walk over and *Retrieve* it. |
| **Shield** (green) | *Shield Bash* — small hit + push. *Deploy Shield* — drops the shield on an adjacent cell as real terrain that blocks movement **and** line attacks; you lose your -1 damage bonus while it's out. *Retrieve* to pick it back up. |
| **Artillery** (yellow) | *Cannon* — straight-line hit. *Mortar* — mark a plus-shaped area within range; it lands at the start of your next turn (and clears a wall tile it covers). |

## Enemies

- **Grunt** — walks to the reactor and hits it.
- **Charger** — telegraphs a straight charge lane one turn, dashes it the
  next. Blockable and dodgeable.
- **Enemy Artillery** — telegraphs an AoE on the reactor, strikes it next turn.

## Architecture

Deliberately thin. No generic tactical framework.

```
core/   pure rules engine (RefCounted, no Node, fully headless-testable)
        grid, unit, grid_object, battle_state, push, mech_actions,
        action_preview, telegraph, enemy_ai, mission
game/   view layer — grid_view, overlay_layer, unit_view,
        grid_object_view, hud, battle (the controller)
run/    entry point
tests/  GUT unit + integration suites
```

`BattleState` is the whole engine. It exposes `player_move` / `player_action`
/ `end_player_turn` and accumulates view-facing `events` (moves, damage,
telegraphs…) that `battle.gd` drains and plays back as tweens. Preview and
execution share the same geometry helpers, so what you see is what happens.

**Every tunable** — map, walls, spawn schedule, HP, move ranges, damage — is
in `core/mission.gd` and the `const` blocks of `mech_actions.gd` / `enemy_ai.gd`.
