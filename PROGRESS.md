# Mecha POC — build progress

Built in the spec's 17-step order, then a run of combat-design passes:
playtest feedback, readability UI, telegraphed reinforcements, mech rebalances,
the Grappler control rework, enemy-intent projection + terrain + the Interceptor,
prediction-consistency fixes + a data-driven mission format + the first
hand-designed vertical slice (**Reactor Breach**) + dev telemetry, and now a
**second** hand-designed slice (**The Chokepoint**) + a dev mission picker, an
isometric presentation prototype, and a **pre-mission squad customization**
screen (frames keep a fixed category + primary; players pick a secondary, two
Systems, and a Pilot per mech). All 183 GUT tests green; headless probes confirm
passive play loses both missions by turn 4.

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

## Iteration 10 — isometric presentation prototype

- Combat and both mission definitions are unchanged. No balance changes, camera,
  renderer toggle, elevation, or additional content. Existing HUD layout fits.
- `assets/tile.png`: 32?32 RGBA, transparent corners, nontransparent bounding box
  covers the canvas. The TOP is a 32?16 diamond; the remaining 16 pixels are
  decorative block sides, not gameplay elevation or clickable surface. The top
  vertex spans x=15..16 on row 0; its pixel staircase reaches the side corners
  around row 8 and front vertex at row 16. No rectangular padding to crop.
  `tile.aseprite` header: one frame, 32?32, 32-bit, 552 bytes; source unchanged.
- Render the actual texture at nearest-filtered 2? scale (64?64 image), with
  64?32 playable top, half-width 32, half-height 16. Texture anchor is source
  (16,8), displayed (32,16), at the projected cell centre. Mild 0.78 RGB
  modulation improves contrast while retaining the tile art.
- GridView owns all projection: centre = (424,220) + ((x-y)*32,(x+y)*16).
  Inverse: gx=(dx/32+dy/16)/2, gy=(dy/16-dx/32)/2; floor(g+0.5).
  Reject coordinates outside [-0.5,width-0.5] ? [-0.5,height-0.5]. Shared
  boundaries choose the higher logical coordinate; the outer rim is closed
  and belongs to its last in-board tile. Raster edge stair steps represent an
  ideal continuous diamond, not alpha-tested sides or rectangular hitboxes.
- API includes cell_polygon, cell_contains_point (normalized Manhattan diamond
  test), board_visual_bounds, diamond and visual_depth. Board visual bounds:
  (40,204), size (768,416), including decorative sides, clear of HUD x=836.
- OverlayLayer now fills/outlines GridView polygons for every existing layer:
  movement, hover path, targets, AoE, forced moves, enemy destinations/lanes,
  projected intent and reinforcements. Screen-facing destination rings shrink
  to the top-face height. A white diamond shows hovered cells.
- Floors draw back-to-front by x+y, preventing block sides hiding nearer tops.
  Walls are low extruded diamonds with their own depth. Walls, objects and
  animated units share z=100+round(projected_y*2); equal-depth ties retain
  stable scene insertion order. Units update depth during tweens. Pits are
  ground-level; overlays (1500), annotations (1600), transient FX (1700) remain
  above geometry. Wall visibility follows destruction without changing Grid.
- UnitView: smaller upright placeholders, feet at the projected centre, compact
  screen-facing HP/AP/selection. Existing path, lunge, push and death tweens
  preserved. GridObjectView: diamond pits, compact upright reactor/barrel/shield,
  spear on the surface. AnnotationLayer: smaller incoming silhouettes and badge
  offsets; arrows still join centres. INCOMING and PIT labels use screen offsets
  from their actual cell rather than misusing the preceding logical row.
- No square-cell geometry remains in battlefield rendering. Rect2 remains for
  texture bounds, upright placeholder bodies, HP bars and HUD, intentionally.
  Projection defaults to the current 12?12 boards; Battle passes actual bounds
  to picking. No generic renderer framework or developer comparison toggle.

### Validation and limits

- Added 8 projection tests: asset dimensions/alpha/anchor, all 144 centre round
  trips, interior points near every corner/edge on every tile, exact shared
  edges and corners, overlapping bounding boxes, outer edges/outside rejection,
  both missions and view-construction state immutability, bounds and depth.
- Added 3 scene integration tests: hover all 144 cells in both missions, select
  and move every mech via projected mouse events, path overlays and enemy phase
  playback/spawns; two-stage Grapple/Throw; thrust/lunge/push, spear throw/retrieve,
  shield deploy/retrieve, Charger movement and death. Assert final view positions
  against logical state. Existing gameplay and end-to-end mission tests retained.
- Full GUT: **148/148 passing, 3,747 assertions, 16 scripts**, Godot 4.7.2 /
  GUT 9.7.1. Godot editor import and real OpenGL scene capture also run.
- Reactor Breach: rendered opening inspected, full-board hover and squad movement
  plus enemy playback passed scripted input tests; original mission bot passes.
- The Chokepoint: same rendered and scripted checks passed; original mission bot
  passes. Geometry, pits, barrels and reactor visibly align in both captures. Also
  inspected turn-4 renders of both missions: Charger lanes, incoming markers
  and arrows align; stacked incoming enemies share a silhouette/label (the HUD
  lists their counts), and central reactor HP can be crowded by nearby units.
- These are scripted scene tests and screenshot inspection, NOT completed human
  manual playthroughs. Full subjective ability/intent readability checklist and
  play-feel judgment still require interactive human validation in both missions.
- Readability tradeoffs: half-height rows crowd HP/AP and intent labels; circles
  still look like tokens, and pale cyan art competes with blue move tint. The
  darkening helps, but dense combat needs further user testing. Information
  deliberately draws through terrain; no label collision-avoidance is added.
- The provided tile works well as a prototype floor and creates a coherent
  raised board. Isometric looks closer to the intended direction in captures,
  but stronger play feel is a provisional judgment, not established by tests.
- Recommended next task: a focused human playtest of both missions for targeting
  confidence and dense-turn intent/readout legibility, followed only by measured
  presentation adjustments. Keep balance and new systems separate.

## Iteration 11 — pre-mission squad customization

Design question under test: *can a Lancer / Bulwark / Grappler support
meaningfully different builds while keeping its frame identity?* No campaign,
economy, inventory, unlocks, XP, or persistence — every option is available
immediately, selections live only for the session.

### Data model

- `core/squad_loadout.gd` (`SquadLoadout`, RefCounted). `mechs` is keyed by
  `Unit.Kind` → `{secondary_id, systems:[slot0,slot1], pilot_id}`. Static tables:
  `SECONDARIES` (per frame), `SYSTEMS`, `PILOTS`, `DESCRIPTIONS`; static helpers
  `category()`, `primary()`, `label()`. `validation_errors()` enforces exactly
  three frames, in-list secondary, two System slots, no duplicate System *on one
  mech* (shared across mechs is fine), no duplicate Pilot across the squad.
  `copy()` deep-duplicates for hand-off. Menu produces data; battle consumes it.
- `BattleState.new(mission_data, squad_loadout)` applies the loadout when building
  player units. Baseline `SquadLoadout.new()` = current secondaries, no Systems,
  no Pilots, and reproduces prior combat exactly (`test_default_loadout_actions`).
- Per-mech runtime state lives on `Unit` (`systems`, `pilot_id`, `impaired_slot`,
  `braced`, once-per-turn/mission flags, `damage_state()`), reset deterministically
  by `_start_player_turn()` / mission restart.

### Menu flow

`Launch → Squad Loadout (mission picker + 3 mech cards) → Deploy → Battle`.
From battle: **Restart Mission** (same loadout) and **Return to Loadout** (keeps
selections for editing). `run/main.gd` `GameFlow` owns a `SquadLoadout` that
survives navigation; battle state is always rebuilt. The old dev mission picker
moved onto the loadout screen.

- `game/loadout_screen.gd` builds one card per frame: name, category, HP/MOVE,
  fixed primary, secondary / System 1 / System 2 / Pilot `OptionButton`s with
  live descriptions. Invalid choices are disabled in place (duplicate System on
  the same mech, Pilot already taken by another mech); Deploy is gated on
  `validation_errors()`. "Reset to baseline" restores the comparison loadout.
- **Bug fixed this pass:** `LoadoutScreen` (a `Control`) is parented under
  `GameFlow` (a `Node2D`), so `PRESET_FULL_RECT` had no parent rect to resolve
  against — the screen collapsed and only the title/mission/buttons showed, no
  mech cards. `_fit_viewport()` now sets equal anchors + explicit
  `get_viewport_rect().size` and follows `size_changed`. Regression test:
  `tests/integration/test_loadout_layout.gd`.

### Implemented secondaries (fixed primary always kept)

| Frame | Primary | Secondaries |
|---|---|---|
| Lancer (LIGHT) | Thrust | **Throw Spear** (unchanged) · **Impact Spear** — cardinal r3, dmg 1, push 2, shared Push collision, no spear object · **Thermal Lance** — cardinal r2, dmg 3, no push, breaks destructible terrain, reusable |
| Bulwark (HEAVY) | Shield Bash | **Deploy Shield** (unchanged) · **Brace** — 1 AP self, immune to enemy forced movement until next player phase, `braced` flag exposed · **Repulsor Plate** — adjacent enemy, 0 direct dmg, push 3, normal collision |
| Grappler (MEDIUM) | Grapple | **Throw** (unchanged) · **Anchor Shot** — empty cardinal tile r3, one Anchor per owner (re-place removes the old), walkable but blocks forced movement, valid Grapple self-reel anchor · **Tow Cable** — allied mech cardinal r3, safe pull 1–2 cells, no damage, reuses displacement planner |

All six run through the same planner/resolver in preview and execution
(`_parity()` asserts position / HP / impairment / object parity per test).

### Category effect

Deliberately small: **HEAVY** reduces incoming *enemy* forced movement by 1
(floor 0), reflected in both `Push.trace` preview and `Push.resolve`. LIGHT and
MEDIUM are baseline; LIGHT identity stays expressed through mobility only. No
weight points, no swappable categories.

### Implemented Systems (2 slots, `None` allowed, no dupes per mech)

- **Vector Thrusters** — first normal move each turn gets +1 range (consumed even
  on a short move); resets per turn.
- **Stabilizers** — incoming forced movement −1 (floor 0); willing-ally repositions
  exempt. Stacks with HEAVY toward the floor.
- **Reinforced Actuators** — actions that already push (Thrust/Bash/Impact/Repulsor
  and Throw/Grapple max distance) gain +1 through the shared planner; precise
  placement stays precise.
- **Shock Absorbers** — received collision damage −1 (floor 0), after stowed-shield
  mitigation; shown in preview.
- **Emergency Winch** — once per mission, free: move an adjacent ally one tile to a
  safe empty tile; not refunded per turn; rejects unsafe destinations without
  spending the charge.
- **Targeting Suite** — info only: while the mech is selected, emphasizes known
  enemy intents that intersect cells it can currently reach/influence. Reveals
  nothing otherwise hidden; disabled when the slot is impaired.

### Implemented Pilots (one per mech, unique across squad, `None` allowed)

- **Ace** — after moving ≥3 cells this turn, the next powered displacement action
  gets +1 push / max distance. Once per turn.
- **Brawler** — first damaging collision it causes each turn deals +1 collision
  damage to that collision's recipients.
- **Rescuer** — first intentional ally reposition it causes each turn refunds 1 AP
  (capped at max). Once per turn.
- **Engineer** — once per mission, free: repair the impaired System; if none is
  impaired, heal to the next damage-state threshold. No repair resource.

All procs bump telemetry (`secondary:*`, `system:*`, `pilot:*`, `impairment:*`,
`condition:*`) and push a `build_proc` event for the HUD.

### Damage model

Derived from HP, smallest state model that supports the rules:

| State | HP | Effect |
|---|---|---|
| NORMAL | >50% | none |
| DAMAGED | 26–50% | one System impaired — slot 1 first, then slot 0 |
| CRITICAL | 1–25% | impairment kept + movement −1 |
| DISABLED | 0 | existing disabled/death path |

Impairment is deterministic and latched (`impairment_triggered` /
`impaired_slot`), so an Engineer repair below the threshold is not immediately
re-impaired. No body-part damage.

### Battle HUD

Selecting a player mech shows a compact `Hud.build_summary()` line: category,
equipped secondary, Systems (impaired one tagged `IMPAIRED`), Pilot, damage
state.

### Tests / results

- **183/183 GUT green** (Godot 4.7.2 / GUT 9.7.1), up from 148. New:
  `tests/unit/test_loadout.gd` (35 cases — validation, every secondary/System/
  Pilot, preview==execution parity, once-per-turn/mission resets, damage
  thresholds, deterministic impairment, Engineer), `tests/integration/
  test_loadout_flow.gd` (launch→deploy→restart→return preserves selections;
  menu disables duplicates; Targeting Suite gating; HUD summary),
  `tests/integration/test_loadout_layout.gd` (card layout regression).
- Manual: launched the app, confirmed the loadout screen renders all three cards
  with working selectors, Deploy enters Reactor Breach with the chosen builds,
  and the battle HUD exposes the new Return to Loadout / Restart buttons.
  (Screenshots captured this session.)

### Observations

- **Feels distinct:** Impact Spear vs Thermal Lance genuinely re-poses the Lancer
  (displacement/setup vs terrain-break pressure) without touching Thrust. Brace
  turns the Bulwark into an immovable objective anchor; Repulsor Plate makes it a
  pure spacer — both read as "still a Bulwark". Anchor Shot gives the Grappler
  board control it never had while keeping Grapple central.
- **Watch for redundancy:** Stabilizers on a HEAVY frame partly overlaps the
  category modifier (both drive toward the forced-move floor) — fine as a stack
  for LIGHT/MEDIUM, thin on Bulwark. Vector Thrusters is a clean, low-drama pick
  that may become an auto-include.
- **Watch for power:** Reinforced Actuators + Ace on one mech chains to +2 push on
  a single action (`test_ace…` lands an enemy 3 cells out from range-3 Impact);
  worth a human check that it isn't the obvious dominant Lancer build.
- **Recommended follow-up:** human playtest for build-identity feel; consider a
  distinct HEAVY-only System so Stabilizers isn't its redundant pick; sanity-tune
  the Actuators+Ace stack if it dominates; only then look at a second mission's
  loadout constraints.

## Iteration 12 — loadout UX + battlefield space

Presentation only. No combat, mission, balance or data-model change.

### Loadout screen: one mech at a time

`game/loadout_screen.gd` rebuilt. A roster strip (`LANCER · LIGHT` /
`BULWARK · HEAVY` / `GRAPPLER · MEDIUM`) switches which frame fills the screen;
`active_kind` + `_rebuild_config()` regenerate the body on switch. The mission
picker moved to the header.

- Left: identity panel — name, category, HP/MOVE, the category's systemic effect,
  fixed primary + a one-line primary description (new `thrust` / `shield_bash` /
  `grapple` entries in `SquadLoadout.DESCRIPTIONS`).
- Right: four columns (Secondary, System 1, System 2, Pilot). Every option is a
  card showing its **name + full effect text inline** — no need to select it to
  see what it does. Selected card gets an accent border; a card disabled by the
  duplicate-System / one-Pilot-per-squad rules greys out and prints the reason.
  Click a card to equip it. `Enter` = Deploy.
- `selectors` is now the *active* mech's four slots only, each entry exposing
  `selected_id` and `disabled_ids` (was: an `OptionButton` per slot per frame).
  `_disabled_for()` is the single side-effect-free source of "can't pick this".
- Bug fix carried from iter 11: `_label()` no longer force-enables autowrap —
  an autowrapping label beside an expanding sibling in an `HBox` collapses to
  zero width and renders one glyph per line (it did, on the title).

### Battle: 1920×1080 + a camera

- `project.godot` viewport 1280×900 → **1920×1080**. `Hud.PANEL_POS` moved to the
  right edge (`x = 1476`), panel height 828 → 1008, win/lose banner recentred.
  `GridView` projection math is unchanged, so `test_projection` is untouched.
- `Battle` owns a `Camera2D` (`_reset_camera()` frames the board into the area
  left of the HUD). **Mouse wheel** zooms toward the cursor (0.6×–3.0×),
  **middle-drag** pans, **Home** resets. Camera input is handled before the
  playback-busy gate, so you can look around during the enemy turn.
- Screen⇄world uses an explicit inverse pair matching Camera2D's default
  (`_screen_to_world` / `_world_to_screen`) rather than `get_canvas_transform()`,
  so picking is correct regardless of when the viewport transform updates and the
  headless input tests stay deterministic (`test_isometric_view` now sends
  screen-space event positions through `_world_to_screen`).
- `run/main.gd` dev shortcut: `godot … -- battle [mission_id]` deploys the
  baseline squad straight into a mission.

### Tests / results

- **183/183 GUT green.** Updated: `test_isometric_view` (screen-space input),
  `test_loadout_flow` + `test_loadout_layout` (new one-at-a-time structure).
  Added the Camera2D round-trip implicitly (every existing hover/click test now
  exercises it).
- Manual: launched both screens. Loadout renders the roster + identity panel +
  four inline-description columns; roster switching rebuilds correctly. Battle
  board is visibly larger and centred beside the right-edge HUD; both Reactor
  Breach enemies are on-screen at the default frame (one was clipped at 1280).
  Screenshots captured this session.

### Observations / follow-up

- The Secondary column has only 3 rows so its space is under-used next to the
  7-row System columns — a 2×2 slot grid or letting the identity panel widen
  would balance it.
- Default camera frame leaves the rightmost board tiles close to the HUD on
  Reactor Breach; fine with pan/zoom but a hair more zoom-out margin wouldn't
  hurt.
- No zoom/pan affordance is shown on-screen yet (wheel / middle-drag / Home are
  discoverable only by trying). A one-line hint in the HUD would help.

## Iteration 13 — battlefield HUD, tactics-game layout

`game/hud.gd` rebuilt around the XCOM / Into the Breach convention: the board is
the frame, UI hugs the edges. Same `CanvasLayer`, same signals, same
`refresh(selected, pending, hint, inspect_id, inspect_spawn)` contract and
`Hud.build_summary()` static, so `battle.gd` and the tests are untouched.

- **Top status strip** (full width, 56 px): `TURN n/N` + phase (colour-coded per
  phase), primary objective, reactor bar + count, optional-objective ✓/✗, and a
  right-aligned `◤ INBOUND: Charger · Grunt` warning. Dev mission picker tucked
  far right.
- **Right squad rail** (thin): one colour-keyed tile per mech (frame colour from
  `unit_view.gd`), mini HP bar, AP pips, damage-state label, white border when
  selected, dimmed when down. Click to select.
- **Left dossier**: the selected mech — name, `LIGHT`/`NORMAL` chips, big HP bar,
  big AP, a wrap of live status chips (`BRACED`, `THRUSTERS READY`, `ACE 2/3`, …),
  then Secondary / Systems / Pilot. Hovering an enemy or a reinforcement marker
  swaps the same panel to its intent read-out.
- **Bottom action bar** (centred, shown only with a mech selected in the player
  phase): `[M] MOVE` + one card per available action — hotkey badge, name,
  FREE/1 AP pill, a stat line, tag line. Active action gets the accent border;
  unaffordable cards dim.
- **Bottom-right**: `END TURN` — green `✓ all mechs spent` when every mech is out
  of AP, amber `↵  N mechs still have AP` otherwise (Into the Breach's
  "you're not done" nudge). `Restart` / `Loadout` beneath.
- **Bottom-left**: the contextual hint, plus a faint
  `scroll — zoom · middle-drag — pan · Home — recentre` camera legend.
- `battle.gd _reset_camera()` reworked to fit the board into the clear rectangle
  between the top strip, the bottom bar and the rail (was: just "left of the HUD
  column"). `Hud.PANEL_POS` kept as the board's right limit (now 1820).

Tests: **183/183 GUT green** (no HUD-structure tests existed; the reused
`Hud.build_summary` token contract is preserved and still checked by
`test_loadout_flow`). Manual: launched into Reactor Breach, selected the Lancer
via a rail tile — dossier and action bar populate correctly, End-Turn nudge
shows "3 mechs still have AP". Screenshots captured this session.

Follow-up ideas: move-range tiles read faintly (teal-on-teal) — bump
`Battle.REACH_COL` alpha; the action-bar cards could carry small shape icons
instead of `[1]`/`[2]` once art exists; rail tiles are a little vertically
cramped.

### Iteration 13b — selected-unit dossier shows the full build

The selected-mech panel used to list Secondary / Systems / Pilot as bare names
("Throw Spear", "None · None", "None"). Now it reads like the loadout screen's
detail:

- `AP … MOVE n` on one line (MOVE reflects Vector Thrusters / a CRITICAL penalty).
- A one-line category note (`HEAVY — shrugs off 1 tile of incoming enemy force`).
- `PRIMARY / SECONDARY / SYSTEM 1 / SYSTEM 2 / PILOT` each as a labelled row:
  colour-coded name (secondary = accent, systems = green, pilot = violet) + the
  full effect text from `SquadLoadout.DESCRIPTIONS`, wrapped. Empty slots collapse
  to `— empty —`; an impaired System is tagged `IMPAIRED` and its text dims.
- `run/main.gd` dev arg gained `kit`: `godot … -- battle kit` deploys a sample
  Lancer build (Impact Spear / Vector Thrusters + Shock Absorbers / Ace) so the
  dossier can be screenshot with everything populated.

183/183 GUT green. Verified in-app: selecting the kitted Lancer shows all five
rows with descriptions, MOVE 6 (5 + Thrusters), and `THRUSTERS READY` /
`ACE 0/3 · READY` status chips.

### Iteration 13c — one bottom-left unit panel (was: top-left info + centred bar)

The split — mech details top-left, a wide centred action bar bottom — read as
disconnected and left a lot of dead space in the bottom middle. Consolidated into
a **single bottom-left panel** (`_unit_panel`, anchored to the bottom-left corner,
auto-height, grows upward — the XCOM / Into the Breach placement):

- Selected mech → stats + build (with effect text) + an `ACTIONS` card row, all
  in the one panel. Hovering an enemy / `◤` marker → the same panel shows its
  intent. Nothing selected → a small "NO SELECTION" stub.
- Action cards moved inside it as an `HFlowContainer` (wrap 2–3 per row),
  trimmed: hotkey badge, name, FREE/1 AP, one short stat line (no tag line).
  Contextual-ability stat lines shortened (`brace` → "Self · immune to enemy
  force", etc.).
- Bottom row is now: unit panel (left) · hint + camera legend (centre) ·
  `END TURN` + nav (right). No empty centre band.
- `Battle._reset_camera()` gives the board the freed vertical space (bottom
  reserve 150 → 84); the unit panel floats over the lower-left board corner.

183/183 GUT green; verified both states (kitted Lancer selected, and
no-selection) in a tracked instance.

### Iteration 13d — action cards back to bottom-centre

Per playtest feedback: the unit card (stats/build) reads well bottom-left, but
the action cards felt like they belonged in the middle. Split them out —
`_action_tray` is now a small panel anchored **centre-bottom**, auto-sized to its
cards, holding `[M] MOVE` + the ability cards. The bottom-left panel keeps just
stats + build. Hint line and camera legend re-centred beneath the tray.
`_bottom_label()` helper for the viewport-centred bottom labels. 185/185 green.

### Winch / contextual-ability clarity

- Battle action-card blurbs now describe targeting: `emergency_winch` →
  "Adjacent allied mech → safe tile 1 away · once/mission" (was "move ally 1");
  same for `brace` / `anchor_shot` / `tow_cable` / `engineer_repair`.
- Two-stage hint no longer misleads: arming Winch / Tow / Throw with **no valid
  stage-1 target** now says so ("No allied mech in an adjacent tile — move one
  next to <mech> first") instead of "Choose an ally…".
- `tests/integration/test_kit_deploy.gd` added (guards the `-- battle kit` dev
  path: turn 1, player phase, full AP, no telegraphs).
