# Mecha POC — build progress

Built in the spec's 17-step order, then a run of combat-design passes:
playtest feedback, readability UI, telegraphed reinforcements, mech rebalances,
the Grappler control rework, enemy-intent projection + terrain + the Interceptor,
prediction-consistency fixes + a data-driven mission format + the first
hand-designed vertical slice (**Reactor Breach**) + dev telemetry, and now a
**second** hand-designed slice (**The Chokepoint**) + a dev mission picker. All
137 GUT tests green; headless probes confirm passive play loses both missions by
turn 4.

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

## Iteration 9 — a second encounter: The Chokepoint

Purpose: use a second hand-built mission to check whether the existing systems
support a *meaningfully different* tactical puzzle without new mechanics.

- **`Mission` is now a small registry.** `Mission.catalog()` / `ids()` /
  `by_id(id)` / `display_name(id)`. `BattleState.new(Mission.by_id(x))` starts
  a mission. Not a campaign — just the set the dev picker can launch.
- **Dev mission picker.** An `OptionButton` at the top of the HUD sidebar
  (`Hud.mission_selected(id)` → `battle.gd` sets `mission_id`, restarts). No
  campaign flow; `battle.gd` never names a mission, it just reads `mission_id`.
- **`Mission.the_chokepoint()`** — one east-west divider wall with three
  two-wide gaps (west cols 2-3 / centre cols 6-7 / east cols 10-11) and a short
  dogleg on each flank. Centre is a clean straight line from the north edge to
  the reactor and the only lane both reinforcement Chargers use. Two pits on
  the centre lane's *shoulders* ((5,5)/(7,5) — a shove, not a walk, feeds
  them); two barrels beside the reactor's flank approaches ((5,7)/(7,7) —
  cluster clear, but a squad start tile sits in each blast). Two chamber nubs
  ((4,6)/(8,6)) keep the flanks from sliding straight in. Three grunts live
  from turn 1, one per lane; roster drops the Artillery. 5-turn hold.
- **Telemetry** — `note_death` now tags kills by cause; the summary prints
  `killed: N (direct · pit · blast · slam)` so a run shows how much of the
  work was positioning vs. damage.
- **Tests** — `tests/unit/test_chokepoint.gd` (registry/picker logic, data
  validity, reachability, init, determinism, reinforcement timing, the
  shove-into-pit tactic, telemetry categories) + 4 mission-level tests in
  `tests/integration/test_mission.gd`. 121 → 137. The shared greedy bot now
  path-follows instead of manhattan-stepping (robust on a divided map).

## Difficulty shape (verified headless)

- **Reactor Breach** — passive → DEFEAT (reactor gone turn 4); greedy → VICTORY,
  reactor ~1–2/12, squad intact.
- **The Chokepoint** — passive → DEFEAT (reactor gone on the turn-4 enemy
  phase). A damage-only bot (melee + spear, no repositioning) → also DEFEAT,
  one turn short. A bot that grapples / feeds the shoulder pits → VICTORY, tight
  at reactor 3/12, squad intact — and the win is *carried by positioning*: of
  5 enemy kills, 1 pit + 4 slam + 0 direct; collision damage ≈ direct damage.
  Pure damage does not hold this map; displacement does.

## Known rough edges / next iteration candidates

- **Charger windup (observed on The Chokepoint).** With the centre lane
  narrowed, a windup Charger is easy to neutralise — a body on the lane or a
  single shove ends it — and it never re-aims. It still creates a real "spend a
  turn on this or eat 3" decision the first time, but a Charger that telegraphs
  into a lane the player has already fortified is dead weight. Candidate fix
  (kept separate, not required for the mission): on its windup turn, let a
  Charger take up to `move/2` steps to line up a *different* clear lane to the
  reactor before committing — still a full-turn telegraph, but the player has
  to actually hold every lane, not just the one it first picked.
- **Enemy-turn playback (observed).** The Chokepoint routinely has 6–10 enemies
  moving in a phase; sequential fixed-timed playback of that many independent
  walks is noticeably slow and the individual moves stop carrying information.
  Focused follow-up (do NOT fold into a mission task): batch a phase's events
  into "waves" — resolve non-interacting moves in parallel, keep a beat only
  for damage / a charge / a detonation.
- **Grappler Throw targeting (observed).** The straight-line-away constraint
  read fine here: the useful plays (shove a centre enemy into a shoulder pit,
  a flanker into a chamber nub) all want the mech positioned first, which is
  the intended cost. It only felt bad when a pit was one tile off the throw
  line and the answer was "walk one tile, then throw" — annoying but legible.
  No change recommended yet.
- Enemy-turn playback is sequential and fixed-timed (see above).
- No sound. Placeholder shapes only, as intended.
- Balance constants (`mission.gd`, `mech_actions.gd`, `enemy_ai.gd`) are still
  first-pass — tune against real playtests.
- The Chokepoint sits right on the win/loss line for the crude probe bots —
  small schedule perturbations flip the positioning bot between a 3/12 win and
  a one-turn loss. Deliberately tuned by geometry/timing, not stats; wants a
  human playtest to confirm the "damage stalls / displacement holds" gap feels
  fair rather than punishing.
