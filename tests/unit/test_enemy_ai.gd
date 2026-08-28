extends GutTest

## Enemy behaviour: grunts march on the reactor and hit it, chargers
## telegraph then charge (and can be blocked), enemy-artillery telegraphs an
## AoE then strikes it.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func test_grunt_steps_toward_reactor() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(0, 6))
	EnemyAi.act(s, g)
	assert_lt(Grid.manhattan(g.pos, s.reactor.pos), Grid.manhattan(Vector2i(0, 6), s.reactor.pos),
		"moved closer to the reactor")

func test_grunt_attacks_reactor_when_adjacent() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(s.reactor.pos.x - 1, s.reactor.pos.y))
	var before := s.reactor.hp
	EnemyAi.act(s, g)
	assert_eq(s.reactor.hp, before - Mission.GRUNT_MELEE_DMG)

func test_charger_telegraphs_then_charges_next_turn() -> void:
	var s := _state()
	var c := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, s.reactor.pos.y))
	s.turn_number = 1
	EnemyAi.act(s, c)
	assert_eq(s.telegraphs.size(), 1, "charge is telegraphed, not resolved")
	assert_eq(s.telegraphs[0].kind, Telegraph.Kind.CHARGE_LINE)
	assert_eq(c.charge_state, Unit.ChargeState.WINDING)
	var start := c.pos

	# next enemy turn: telegraph is due
	s.turn_number = 2
	var due := s.telegraphs[0]
	s._resolve_telegraph(due)
	s.telegraphs.clear()
	assert_gt(c.pos.x, start.x, "charged forward along the telegraphed line")
	assert_eq(c.charge_state, Unit.ChargeState.READY, "ready to wind up again")

func test_charger_charge_is_stopped_by_a_blocker() -> void:
	var s := _state()
	var c := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, s.reactor.pos.y))
	s.turn_number = 1
	EnemyAi.act(s, c)   # telegraph toward the reactor row
	# player drops a shield right in front of the charger
	s.place_object(GridObject.make_shield(Vector2i(2, s.reactor.pos.y), 999))
	s.turn_number = 2
	s._resolve_telegraph(s.telegraphs[0])
	assert_eq(c.pos, Vector2i(1, s.reactor.pos.y), "the shield stopped the charge cold")
	assert_eq(s.reactor.hp, s.reactor.max_hp, "reactor never got hit")

func test_enemy_artillery_telegraphs_aoe_then_hits_reactor() -> void:
	var s := _state()
	var a := TestUtil.add(s, Unit.Kind.ARTILLERY_ENEMY, Unit.Team.ENEMY,
		Vector2i(s.reactor.pos.x, s.reactor.pos.y - 3))
	s.turn_number = 1
	EnemyAi.act(s, a)
	assert_eq(s.telegraphs.size(), 1)
	assert_eq(s.telegraphs[0].kind, Telegraph.Kind.AOE)
	assert_true(s.reactor.pos in s.telegraphs[0].cells, "AoE is marked on the reactor")

	var before := s.reactor.hp
	s.turn_number = 2
	s._resolve_telegraph(s.telegraphs[0])
	assert_eq(s.reactor.hp, before - Mission.ENEMY_ARTILLERY_DMG)

func test_ai_is_deterministic() -> void:
	var a := _state()
	var b := _state()
	for st in [a, b]:
		TestUtil.add(st, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(0, 0))
		TestUtil.add(st, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(11, 11))
	for st in [a, b]:
		st.turn_number = 1
		for u in st.living_enemies():
			EnemyAi.act(st, u)
	var ea := a.living_enemies()
	var eb := b.living_enemies()
	for i in ea.size():
		assert_eq(ea[i].pos, eb[i].pos, "same start state -> same moves")
