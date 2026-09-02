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

Mouse-driven, with hotkeys. Click a mech (or its squad card) to select it —
the card, its ability list, and its battlefield ring all light up together.
Each mech has **2 AP** per turn (shown as ◆ pips on the unit and the card);
spend them across mechs in any order.

- **Blue fill** = where the selected mech can move. Hover a tile to draw the
  **path** it will walk; click to go (1 AP). Out of AP → the range greys out.
- Pick an ability (click its card or press **1 / 2 / 3**, **M** for Move).
  Valid targets get a **gold outline** — deliberately different from the blue
  move fill. Right-click / Esc cancels.
- **Grapple / Throw are two clicks:** first click a gold target to *grab* it
  (it gets a bright ring), then click a **blue tile** to choose where it goes —
  or a **red tile** to slam it into a wall / unit / the edge. Right-click steps
  back to re-grab. Every placement previews its full outcome before you commit.
- Hover a target for the full on-grid preview *before* you commit:
  **`-N` damage numbers** on every unit that would be hit, a **skull** if it's
  lethal, **white arrows** for every forced move (`victim → tile`), a
  **burst + collision number** where something slams, the spear's landing
  cell, and a red reactor outline for friendly fire.
- **Every enemy's next move is on the board.** Charges show a red arrow down
  their lane; artillery a hatched ring on the reactor; grunts and interceptors
  a **thin dim arrow** to where they'll walk plus a ring on what they'll hit
  (a lighter treatment — they're not the scary ones). Hover any enemy for the
  exact destination, target and damage.
- **Reinforcements are telegraphed a turn early.** A pink **INCOMING** marker
  (spawn tile + entry arrow + enemy silhouette) appears the player phase
  *before* the unit enters; the unit then enters on the enemy phase and only
  acts the phase after that. The sidebar lists what's `INBOUND` and, on hover,
  what it'll do once it's active. You always get a full turn to reposition.
- **Repositioning that rewrites the enemy turn is shown live.** Preview an
  action that shoves a charger off its lane, drops a blocker across a grunt's
  route, or pulls the mech an interceptor is chasing: the old plan **fades**,
  the new projected path appears in yellow, and badges land — **interrupt** on
  a neutralised attacker, **safe** on the freed mech/reactor, a burst on a
  **newly threatened** tile, a skull on an enemy the action **destroys**.
- **Terrain is part of the simulation.** *Walls* stop movement, pathing, and
  slides (collision damage on impact). *Pits* — you can't walk in, but a
  forced shove drops a unit in and it's gone; the preview marks it `OUT`.
  *Barrels* block movement and detonate a plus-shaped blast when broken or
  slammed (chains into other barrels); the preview draws the blast and every
  unit / the reactor it catches.
- **Enter** ends the turn.

## The three mechs

| Mech | Identity |
|---|---|
| **Lancer** (blue) | Fast (move 5). *Thrust* — hit 2, push 1, extra damage on a wall/unit slam. *Throw Spear* — a range-4 line hit for 3, but the spear lands on the grid and you lose Thrust (only a weak *Punch*) until you walk over and *Retrieve* it. |
| **Bulwark** (green) | *Shield Bash* — hit 2, **push 2**, collision damage; its real weapon. *Deploy Shield* — drops the shield on an adjacent cell as terrain that blocks **movement** (cover you can hide behind, a wall chargers stop at) but not projectiles; you lose your -1 damage bonus while it's out. *Retrieve* to pick it back up. |
| **Grappler** (orange) | "I decide where everybody is." Move 5, 7 HP. *Grapple* (range 4, two clicks) — grab an enemy, ally, wall or the reactor in a cardinal line, then choose how far (1–3) to reel: pull an enemy off a charge lane / into a slam / next to your Lancer, yank an ally out of an AoE, or reel **yourself** up to 4 tiles to an anchor. **No damage** — pure repositioning. *Throw* (two clicks) — grab an adjacent unit, then pick **any** cardinal direction and distance (1–3). Slams into walls / units / the edge hit for 3 via the shared collision rules. Allies can be flung to safety but never slammed. |

## Enemies

- **Grunt** — walks to the reactor and hits it (or a mech in its way).
- **Charger** — telegraphs a straight charge lane one turn, dashes it the
  next. Blockable and dodgeable.
- **Enemy Artillery** — telegraphs an AoE on the reactor, strikes it next turn.
- **Interceptor** (pink) — *ignores the reactor.* Picks the mech closest by
  path (lowest id breaks ties), chases it, and melees it. It changes the
  question from "can I protect the reactor" to "where are my mechs safe".

Wave 1 starts on the board. Every later wave is telegraphed one player phase
before it enters, and enters one enemy phase before it acts.

## Architecture

Deliberately thin. No generic tactical framework.

```
core/   pure rules engine (RefCounted, no Node, fully headless-testable)
        grid, unit (unit.mitigate() = the one damage-modifier), grid_object
        (walls in grid; pits/barrels/shield/reactor as capability-tagged
        objects), battle_state, push (the one shared displacement resolver),
        terrain_fx (pure explosion chain), mech_actions, action_preview,
        enemy_ai (pure plan_grunt / plan_interceptor / plan_move),
        intent (Intent.project + Intent.charge_outcome — the shared "enemy
        turn" geometry), telegraph, telemetry (dev-only counters),
        mission_data (one mission as plain data), mission (rules + the
        reactor_breach() factory)
game/   view layer — grid_view, overlay_layer (cell tints),
        annotation_layer (arrows / grid text / badges / silhouettes), unit_view,
        grid_object_view, hud, battle (the controller)
run/    entry point
tests/  GUT unit + integration suites
```

`BattleState` is the whole engine. It exposes `player_move` / `player_action`
/ `end_player_turn` and accumulates view-facing `events` (moves, damage,
telegraphs, explosions…) that `battle.gd` drains and plays back as tweens.

**Prediction is execution.** The enemy AI's `plan_grunt` / `plan_interceptor` /
`plan_move` are pure functions over `BattleState` (plus an optional hypothetical
board); `EnemyAi.act()` applies the plan, and `Intent.project()` / the HUD
render the *same* plan. `ActionPreview.build()` and `TerrainFx.explosion_plan()`
mirror `Push.resolve()` / `BattleState.detonate()` cell for cell. No combat rule
has two implementations.

The view **never recomputes combat**. `ActionPreview.build()` is the one
dry-run: it returns a structured `Preview` (`hits[]` with lethality,
`displacements[]` with collision, `reactor_damage`, …) and `battle.gd` just
visualizes it. `Intent.project()` does the same for "would this action change
an enemy charge?" — it re-derives charge lanes against a hypothetical board.
Preview and execution share the same geometry helpers, so what you see is
what happens.

**Missions are data.** `MissionData` holds a single encounter's layout (map,
walls, pits, barrels, reactor, mech starts, initial enemies, spawn points +
schedule, turn limit, objectives, defeat flags). `BattleState.new(mission_data)`
reads it; `Mission.reactor_breach()` builds the one hand-designed slice. Shared
*rules* (unit stats, damage numbers, terrain damage) stay as consts on `Mission`
/ `enemy_ai.gd` — those aren't per-mission.

When a mission ends, a dev-only `Telemetry` summary prints to the console
(actions per mech, damage by category, enemies displaced, intents interrupted,
pit kills, charges blocked, barrels triggered…) so you can see whether the
mechanics are actually being used.
