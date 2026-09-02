extends GutTest

## Interceptor: the enemy that ignores the reactor and hunts mechs.
## Deterministic target = closest mech by path length, lowest unit id breaks ties.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func test_selects_nearest_mech_by_path() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(5, 5))
	var near := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 7))
	TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(0, 0))
	var plan := EnemyAi.plan_interceptor(s, i)
	assert_eq(plan.target_id, near.id, "pursues the closer mech")

func test_deterministic_tiebreak_is_lowest_id() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(5, 5))
	var a := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(3, 5))
	TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(7, 5))
	var plan := EnemyAi.plan_interceptor(s, i)
	assert_eq(plan.target_id, a.id, "equal distance -> lowest id wins")

func test_moves_toward_and_melees_when_adjacent() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(5, 5))
	var m := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 7))
	var plan := EnemyAi.plan_interceptor(s, i)
	assert_eq(plan.dest, Vector2i(5, 6), "stops adjacent to the target")
	assert_true(plan.will_attack)
	assert_eq(plan.target_kind, "mech")
	assert_eq(plan.damage, Mission.INTERCEPTOR_DMG)
	var before := m.hp
	EnemyAi.act(s, i)
	assert_eq(i.pos, Vector2i(5, 6))
	assert_eq(m.hp, before - Mission.INTERCEPTOR_DMG)

func test_never_targets_the_reactor() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(6, 7))
	var m := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(0, 0))
	var plan := EnemyAi.plan_interceptor(s, i)
	assert_eq(plan.target_id, m.id)
	assert_ne(plan.target_kind, "reactor")
	var rb := s.reactor.hp
	EnemyAi.act(s, i)
	assert_eq(s.reactor.hp, rb, "walks past the reactor without touching it")

func test_target_switches_on_hypothetical_mech_movement() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(5, 5))
	var a := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 5))
	var b := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(8, 5))
	assert_eq(EnemyAi.plan_interceptor(s, i).target_id, a.id, "tie -> lower id (Lancer)")
	# player pulls the Lancer far away -> Bulwark is now strictly closer
	var changes := Intent.project(s, {a.id: Vector2i(0, 5)}, [] as Array)
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_eq(ch.owner_id, i.id)
	assert_eq(ch.kind, "interceptor")
	assert_eq(ch.original_target, a.id)
	assert_eq(ch.projected_target, b.id, "switches to the now-nearest mech")
	assert_true(ch.redirected)

func test_blocker_changes_interceptor_path() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(0, 5))
	TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	var changes := Intent.project(s, {}, [Vector2i(2, 5)] as Array)
	assert_eq(changes.size(), 1)
	assert_eq(changes[0].kind, "interceptor")
	assert_ne(changes[0].original_path, changes[0].projected_path, "detours around the blocker")

func test_preview_matches_actual_enemy_turn() -> void:
	var s := _state()
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(0, 5))
	TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 5))
	var plan := EnemyAi.plan_interceptor(s, i)
	EnemyAi.act(s, i)
	assert_eq(plan.dest, i.pos)
	var moved: Array = []
	for e in s.events:
		if e["t"] == "move" and e["id"] == i.id:
			moved = e["path"]
	assert_eq(plan.path, moved)
