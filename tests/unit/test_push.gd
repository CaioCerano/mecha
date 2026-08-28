extends GutTest

## Push resolution: clear slides move the full distance, hard stops deal
## collision damage, and slamming into a unit hurts both.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func test_clear_push_moves_and_no_damage() -> void:
	var s := _state()
	var victim := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	var res := Push.resolve(s, victim, Vector2i(1, 0), 1, 2)
	assert_eq(victim.pos, Vector2i(6, 5))
	assert_eq(res.collided_with, "none")
	assert_eq(victim.hp, victim.max_hp, "no collision, no damage")
	assert_eq(s.occupancy.get(Vector2i(6, 5)), victim.id, "occupancy followed the unit")
	assert_false(s.occupancy.has(Vector2i(5, 5)))

func test_push_into_wall_deals_collision_damage_and_no_move() -> void:
	var s := _state()
	s.grid.set_wall(Vector2i(6, 5), true)
	var victim := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	var res := Push.resolve(s, victim, Vector2i(1, 0), 1, 2)
	assert_eq(victim.pos, Vector2i(5, 5), "wall stops the slide")
	assert_eq(res.collided_with, "wall")
	assert_eq(victim.hp, victim.max_hp - 2)

func test_push_into_board_edge() -> void:
	var s := _state()
	var victim := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(11, 5))
	var res := Push.resolve(s, victim, Vector2i(1, 0), 1, 2)
	assert_eq(res.collided_with, "edge")
	assert_eq(victim.hp, victim.max_hp - 2)

func test_push_into_unit_damages_both() -> void:
	var s := _state()
	var victim := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	var bystander := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	var res := Push.resolve(s, victim, Vector2i(1, 0), 1, 2)
	assert_eq(res.collided_with, "unit")
	assert_eq(victim.pos, Vector2i(5, 5), "blocked, stays put")
	assert_eq(victim.hp, victim.max_hp - 2, "pushed unit takes collision damage")
	assert_eq(bystander.hp, bystander.max_hp - 2, "the unit it slammed into takes it too")

func test_push_into_deployed_shield_is_a_hard_stop() -> void:
	var s := _state()
	var victim := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	s.place_object(GridObject.make_shield(Vector2i(6, 5), 999))
	var res := Push.resolve(s, victim, Vector2i(1, 0), 1, 2)
	assert_eq(res.collided_with, "object")
	assert_eq(victim.pos, Vector2i(5, 5))
	assert_eq(victim.hp, victim.max_hp - 2)
