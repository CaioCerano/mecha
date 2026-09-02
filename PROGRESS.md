# Mecha POC — build progress

Built in the spec's 17-step order, then a run of combat-design passes:
playtest feedback, readability UI, telegraphed reinforcements, mech rebalances,
the Grappler control rework, enemy-intent projection + terrain + the Interceptor,
and now prediction-consistency fixes + a data-driven mission format + the first
hand-designed vertical slice (**Reactor Breach**) + dev telemetry. All 121 GUT
tests green; headless probes confirm passive play loses (turn 4) and greedy
play holds at 2/12 reactor.

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

## Iteration 2 — playtest feedback pass

- **Artillery replaced by the Grappler.** No raw-damage ranged mech. *Grapple*
  reels a unit toward you, or reels you toward a wall / the reactor; *Throw*
  hurls an adjacent unit and lets the collision system do the hurting. Cannon,
  Mortar, and the whole `pending_mortars` path are gone.
- **Bulwark leads with Bash** (dmg 2 / push 2 / collision 2). Deployed shield
  now blocks movement only — chargers still physically stop at it, but
  projectiles pass over. Removes the set-and-forget "wall off the one lane".
- **Movement** — Lancer 4→6 (it was too hard to reach things), Bulwark 3→4,
  Grappler 5.
- **Harder** — Grunt→reactor damage 2→3, reactor HP 10→12, fuller spawn
  schedule (2–3 enemies most turns), still 5 turns.
- **UI** — window 1280×900, cells 44→64, HUD panel 674→408 wide, map moved to
  the top-left. Move-hover draws the path; out-of-AP shows range greyed.

## Iteration 3 — combat-readability UI pass

Goal: read the fight off the board, not the sidebar. Systems untouched.

- **Richer preview model (core).** `ActionPreview.Preview` now carries
  `hits[] {id,amount,lethal}`, `displacements[] {from,to,collided,collision_amount}`,
  `mover_id`, `reactor_damage`. `MechActions` gained `action_damage / _collision /
  _range / _push / _tags` lookups — one source for card text and previews.
- **`core/intent.gd`** — `Intent.project(state, moves, blockers)` re-derives every
  charge lane against a hypothetical board and reports interrupts. The charge
  stop-and-strike rule in `battle_state._resolve_telegraph` is mirrored here (not
  duplicated logic the view owns — it's core, tested).
- **`game/annotation_layer.gd`** — new Node2D for arrows, on-grid `-N` numbers,
  and badges (collision / lethal / interrupt / safe). `overlay_layer` stays
  cell-tints only.
- **On-grid ability preview** — damage numbers on targets, lethal skulls, white
  forced-move arrows with collision bursts, gold *outline* for valid targets
  (distinct from blue move *fill*).
- **Units carry their own readout** — HP bar + AP pips drawn on the unit; exact
  `HP n/n` only on hover/select. Reactor HP bar replaces the `R 12/12` text.
- **Sidebar** — compact `TURN x/5 · PLAYER PHASE`, an OBJECTIVE block
  (`Mission.OBJECTIVE_MAIN` / `TURN_LIMIT` — data only, no campaign engine),
  squad cards with HP bar + big AP pips + selection-linked highlight, ability
  **cards** (`[1] THRUST  1 AP` / `Melee · Dmg 2 · Push 1` / keyword tags),
  hotkeys `1-4` + `M` + `Enter`, and an enemy **inspection card** on hover
  (`NEXT ACTION · Charge · Dmg 3 · interrupted if pushed off lane`).
- **Enemy intent, first-class** — charge lanes get a red arrow, AoE gets a
  hatched centre ring, always drawn on top of ability overlays.
- **Intent-change preview** — previewing a shove/block that rewrites a charge
  fades the old lane, draws the projected lane in yellow, badges the charger
  `interrupt` and the freed mech/reactor `safe`.

## Iteration 4 — telegraphed reinforcements

Core rule: *no unavoidable damage from information the player couldn't have had.*

- **`BattleState.pending_spawns`** — reinforcements are announced at the top of
  their player phase (`_announce_spawns`), physically enter on the next enemy
  phase (`_resolve_due_spawns`), and are frozen out of that phase's acting set,
  so they only act the phase after. `spawn_schedule()` is now keyed by the
  *announce* phase; wave 1 is still placed on the board at mission start.
- **Spawn telegraph = same enemy-intent system.** `game/battle.gd`
  `_draw_spawn_telegraphs()` renders, persistently through move/targeting: a
  pink cell outline, an entry-direction arrow, a faded enemy silhouette
  (`annotation_layer.set_silhouettes`), and an INCOMING label. Sidebar gets an
  always-on `◤ INBOUND` line plus an INCOMING inspection card on hover
  (`enters at col/row · from the N edge · then next phase: …`).
- **Rebalance.** The extra phase of warning made the reactor much easier to
  defend, so: mid-edge spawn points moved first (wave 1 lands closer), waves 2
  and 4 grew. Passive now loses on turn 4; greedy wins with the reactor at ~½.
  Wants a real playtest pass.

## Iteration 5 — Lancer/Grappler balance (playtest feel)

- **Lancer was a board-wide sniper.** Throw Spear 4→3 dmg, range 6→4; move 6→5.
  Still a reach-and-displace mech, no longer hits anything from anywhere.
- **Grappler's turn could be a pure zero.** Grapple now bites a reeled *enemy*
  for 1 (allies / self-pull unaffected); Throw's slam 2→3; Grappler HP 6→7 so
  it can survive setting up a Throw. The intended loop: Grapple a charger off
  its lane (the intent preview shows the interrupt) → Throw it into a wall.

## Iteration 6 — Grappler as the pure control mech

Fix: its usefulness now comes from *where it puts things*, not damage.

- **Grapple** is variable-distance and multi-target. Range 6→4. Grab the first
  unit / wall / reactor in a cardinal line, then choose to reel it (or yourself,
  for an anchor) **1..3 tiles** — the player picks the resting tile. **0 damage**
  (the old 1-dmg chip is gone). Solves lane-break / interrupt / rescue / collision
  setup on its own, no Throw follow-up required.
- **Throw** is omnidirectional. Grab an adjacent unit, then pick **any** cardinal
  direction + distance 1..3. Slam damage stays 3, resolved by the shared Push
  rules (walls / units / board edge — there is no pit/hazard object type yet).
  Allies can be placed but never slammed (harmful ally destinations are simply
  not offered / rejected — no confirm dialog exists).
- **Architecture.** Both are `{entity, dir, dist, collision}` commands built by
  `MechActions.grapple_plan` / `throw_plan` and fed to `Push`. `ActionPreview`
  and execution both call the same planners, so preview == result. New
  `MechActions.grapple_dests` / `throw_dests` enumerate stage-2 tiles for the UI.
- **UI.** `player_action` / `ActionPreview.build` / `MechActions.execute` gained
  an `opts` dict (`opts.dest`). `battle.gd` now has a two-stage targeting flow
  (`focus_cell`): stage 1 highlights grabbable targets, stage 2 rings every valid
  placement (blue) / slam tile (red) and previews the hovered one — arrows,
  damage, collisions, and charge-interrupt / SAFE marks all reuse the existing
  annotation + Intent systems.

## Iteration 7 — see the future, then rewrite it

- **Enemy intent is one shared model.** `EnemyAi` is now pure planners:
  `plan_move` (A* → trim → cap → greedy fallback), `plan_grunt`, `plan_interceptor`
  each return an `EnemyPlan {path, dest, will_attack, target_kind/id/cell,
  damage, destroyed}`. `EnemyAi.act()` *applies* the plan; the HUD and
  `Intent.project()` *render* the same plan; projection re-runs the planners
  against a hypothetical board — so prediction == execution by construction.
- **`Intent.project(state, moves, blockers, removed)`** generalized past
  Charger: it now also emits `Change`s for grunt/interceptor **path**, **dest**
  and **target** shifts, plus `redirected` / `destroyed` / `newly_threatened_cell`.
  Charger behaviour and the old `Change` fields are unchanged.
- **Data-driven terrain.** `GridObject` gained `PIT` + `EXPLOSIVE` and a
  capability API (`blocks_move` / `blocks_forced_move` / `blocks_line` /
  `is_hazard` / `is_collision_surface` / `is_destructible`). Walls stay in
  `Grid` (pure geometry). Pits: pathing avoids them, a Push slides *in* and
  `PIT_DAMAGE` (999) destroys via normal damage handling. Barrels: `hp` 2,
  broken by a ≥2 slam / line hit / blast → `BattleState.detonate()` runs a
  breadth-first plus-AoE chain (`EXPLOSIVE_DMG` 3 to units + reactor). All of it
  flows through `Push` — no Grappler-specific wall/pit/barrel code.
- **`TerrainFx.explosion_plan()`** — pure mirror of `detonate()` (local HP,
  Bulwark stow reduction, `damage_so_far` so a slam-then-blast doesn't
  double-count). `ActionPreview` uses it to preview blasts + pit `OUT`.
- **Interceptor** — new enemy, `hp 4 / move 4`. Targets the mech closest by
  path length; lowest unit id breaks ties; pursues via `plan_move`; melees for
  `INTERCEPTOR_DMG` 2; never touches the reactor. Two of them ride the spawn
  schedule (waves 2 & 4).
- Reactor pressure eased slightly (interceptors don't attack it) — by design;
  greedy probe now holds the reactor at ~¾. Not rebalanced (spec).

## Iteration 8 — one complete encounter

- **Prediction fixes.** `Unit.mitigate()` is now the single damage-modifier
  (stowed Bulwark −1). `damage_unit`, `ActionPreview._add_hit` and
  `TerrainFx.explosion_plan` all call it, so a collision / blast preview number
  equals what execution does. `_add_hit(pre_mitigated)` stops the explosion
  path from mitigating twice. (Audit: this −1 is the ONLY modifier in the game.)
- **Charge geometry unified.** `Intent.charge_outcome()` is the one function;
  `BattleState._resolve_telegraph` calls it instead of a hand-rolled copy. It
  now returns `stop` + `pit`, so the UI shows `→ PIT` + a skull on a live or
  projected charge that self-destructs, and `Intent.project` flags such a
  Change `destroyed` (and `interrupted` on whatever it was going to hit).
- **Intent visual hierarchy.** Grunt / Interceptor arrows: shaft α 0.26 normal
  / 0.90 when the enemy is hovered / 0.10 when superseded by the active
  preview; destination and target rings stay readable at all times. Nothing is
  hidden — every enemy's deterministic plan is still inspectable.
- **`MissionData`** — a mission is now plain data (map, terrain, spawns,
  schedule, objectives, defeat flags). `BattleState.new(mission_data)` reads
  it; `Mission.reactor_breach()` is the factory. Rules consts stay on `Mission`.
- **REACTOR BREACH** — the hand-built slice (layout + waves below).
- **`Telemetry`** — dev-only per-mission counters, printed on mission end.

## Difficulty shape (verified headless)

- Passive play (End Turn only) → **DEFEAT**, reactor gone by turn 4.
- Greedy play (melee in reach, throw/spear, grapple the frontrunner, else
  close in) → **VICTORY**, reactor at ~half, squad usually intact.

## Known rough edges / next iteration candidates

- Grappler *Throw* always launches straight away from the mech (the clicked
  adjacent cell is the direction). No free-aim; reposition to change the line.
- Charger never repositions on its windup turn (kept simple; telegraph is a
  fair full-turn warning). Revisit if chargers feel toothless.
- Enemy-turn playback is sequential and fixed-timed; fine for a POC, could
  batch simultaneous events.
- No sound. Placeholder shapes only, as intended.
- Balance constants (`mission.gd`, `mech_actions.gd`, `enemy_ai.gd`) are still
  first-pass — tune against real playtests.
