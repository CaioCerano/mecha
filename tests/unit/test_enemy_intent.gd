extends GutTest

## Grunt intent as a first-class projection, and the generalized Intent.project
## that answers "if the player does X, what changes about the enemy turn" for
## charges AND deterministic movers together.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func _moved_path(s: BattleState, id: int) -> Array:
	for e in s.events:
		if e["t"] == "move" and e["id"] == id:
			return e["path"]
	return []

# ------------------------------------------------------------------- grunt intent

func test_grunt_projected_path_and_destination_match_actual() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(0, 6))
	var plan := EnemyAi.plan_grunt(s, g)
	EnemyAi.act(s, g)
	assert_eq(plan.path, _moved_path(s, g.id), "projected path == executed path")
	assert_eq(plan.dest, g.pos, "projected destination == where it ended up")

func test_grunt_reactor_target_prediction() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 6))
	var plan := EnemyAi.plan_grunt(s, g)
	assert_true(plan.will_attack)
	assert_eq(plan.target_kind, "reactor")
	assert_eq(plan.target_cell, s.reactor.pos)
	assert_eq(plan.damage, Mission.GRUNT_MELEE_DMG)

func test_grunt_adjacent_mech_fallback_target() -> void:
	var s := _state()
	s.grid.set_wall(Vector2i(0, 1), true)
	s.grid.set_wall(Vector2i(1, 0), true)
	s.grid.set_wall(Vector2i(2, 1), true)
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(1, 1))
	var mech := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(1, 2))
	var plan := EnemyAi.plan_grunt(s, g)
	assert_eq(plan.path.size(), 0, "boxed in -- can't move")
	assert_eq(plan.target_kind, "mech")
	assert_eq(plan.target_id, mech.id)
	assert_eq(plan.damage, Mission.GRUNT_MELEE_DMG)

func test_blocker_changes_grunt_path_and_destination() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(0, 6))
	var changes := Intent.project(s, {}, [Vector2i(3, 6)] as Array)
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_eq(ch.owner_id, g.id)
	assert_eq(ch.kind, "grunt")
	assert_eq(ch.original_dest, Vector2i(3, 6), "straight line without the blocker")
	assert_ne(ch.projected_dest, ch.original_dest, "reroutes around the blocker")
	assert_ne(ch.original_path, ch.projected_path)

func test_hypothetical_mech_move_redirects_grunt_target() -> void:
	var s := _state()
	# seal the reactor so the grunt must fall back to a mech
	for c in [Vector2i(5, 6), Vector2i(6, 5), Vector2i(7, 6)]:
		s.grid.set_wall(c, true)
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 9))
	var b := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(0, 0))
	var changes := Intent.project(s, {b.id: Vector2i(6, 7)}, [] as Array)
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_eq(ch.original_target, -1, "was walking in to hit the reactor")
	assert_eq(ch.projected_target, b.id, "now the Bulwark sits in the last open tile")
	assert_true(ch.redirected)

func test_unchanged_intent_produces_no_change() -> void:
	var s := _state()
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(0, 6))
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(10, 1))
	var changes := Intent.project(s, {lancer.id: Vector2i(9, 1)}, [] as Array)
	assert_true(changes.is_empty(), "an unrelated mech move rewrites nothing")

func test_destroyed_hypothetical_enemy_has_no_future_action() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(0, 6))
	var changes := Intent.project(s, {g.id: Vector2i(2, 7)}, [] as Array, {g.id: true})
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_true(ch.destroyed)
	assert_eq(ch.projected_path.size(), 1, "no walk -- just its current cell")

func test_two_intent_types_project_together() -> void:
	var s := _state()
	# grunt boxed beside the Lancer -> targets the Lancer
	s.grid.set_wall(Vector2i(1, 4), true)
	s.grid.set_wall(Vector2i(3, 4), true)
	s.grid.set_wall(Vector2i(2, 5), true)
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 3))
	var grunt := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(2, 4))
	# charger telegraphed straight down column 2, into the Lancer
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(2, 0))
	s.telegraphs.append(Telegraph.charge(charger.id, [] as Array[Vector2i], Vector2i(0, 1), Mission.CHARGER_DMG, 99))

	# one action: pull the Lancer away
	var changes := Intent.project(s, {lancer.id: Vector2i(0, 3)}, [] as Array)
	assert_eq(changes.size(), 2, "the charge AND the grunt both change")
	var kinds := []
	for ch in changes:
		kinds.append(ch.kind)
	assert_true("charge" in kinds and "grunt" in kinds)

func test_charge_projection_unchanged_by_generalization() -> void:
	var s := _state()
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, 6))
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 6))
	s.telegraphs.append(Telegraph.charge(charger.id, [] as Array[Vector2i], Vector2i(1, 0), Mission.CHARGER_DMG, 99))
	var changes := Intent.project(s, {charger.id: Vector2i(1, 3)}, [] as Array)
	assert_eq(changes.size(), 1)
	assert_eq(changes[0].kind, "charge")
	assert_true(changes[0].interrupted)
	assert_eq(changes[0].safe_cell, lancer.pos)
