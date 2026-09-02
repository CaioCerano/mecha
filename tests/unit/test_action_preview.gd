extends GutTest

## The structured Preview the UI consumes: hit list (with lethality),
## displacement list (with collision), self-move flag, reactor damage.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func test_thrust_preview_reports_hit_and_push() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	var grunt := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	var p := ActionPreview.build(s, lancer, "thrust", Vector2i(6, 5))
	assert_true(p.valid)
	assert_eq(p.hits.size(), 1)
	assert_eq(p.hits[0]["id"], grunt.id)
	assert_eq(p.hits[0]["amount"], MechActions.THRUST_DMG, "open push -> just the thrust damage")
	assert_false(p.hits[0]["lethal"])
	assert_eq(p.displacements.size(), 1)
	assert_eq(p.displacements[0]["to"], Vector2i(7, 5))
	assert_eq(p.displacements[0]["collided"], "none")

func test_thrust_into_wall_preview_adds_collision_and_flags_lethal() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	s.grid.set_wall(Vector2i(7, 5), true)
	var p := ActionPreview.build(s, lancer, "thrust", Vector2i(6, 5))
	assert_eq(p.hits[0]["amount"], MechActions.THRUST_DMG + MechActions.THRUST_COLLISION)
	assert_true(p.hits[0]["lethal"], "2 + 2 >= 3 hp")
	assert_eq(p.displacements[0]["collided"], "wall")
	assert_eq(p.displacements[0]["collision_amount"], MechActions.THRUST_COLLISION)

func test_throw_slam_preview_damages_both_units() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var flung := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 5))
	var wall_of_meat := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	var p := ActionPreview.build(s, grappler, "throw", Vector2i(3, 5))
	assert_eq(p.displacements[0]["to"], Vector2i(4, 5))
	assert_eq(p.displacements[0]["collided"], "unit")
	var ids: Array = []
	for h: Dictionary in p.hits:
		ids.append(h["id"])
	assert_true(flung.id in ids and wall_of_meat.id in ids, "both take collision damage in the preview")

func test_grapple_preview_reports_no_damage() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	var p := ActionPreview.build(s, grappler, "grapple", Vector2i(6, 5))
	assert_true(p.hits.is_empty(), "grapple never deals damage")
	assert_eq(p.push_to, Vector2i(3, 5), "default preview shows the maximum pull")

func test_grapple_preview_honours_chosen_pull_distance() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	var p := ActionPreview.build(s, grappler, "grapple", Vector2i(6, 5), {"dest": Vector2i(5, 5)})
	assert_true(p.valid)
	assert_eq(p.push_to, Vector2i(5, 5), "pulled only 1 tile, as chosen")

func test_grapple_to_wall_preview_marks_self_move() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	s.grid.set_wall(Vector2i(6, 5), true)
	var p := ActionPreview.build(s, grappler, "grapple", Vector2i(6, 5))
	assert_eq(p.mover_id, grappler.id, "grapple-to-anchor repositions the grappler itself")
	assert_eq(p.displacements[0]["id"], grappler.id)
	assert_eq(p.displacements[0]["to"], Vector2i(5, 5))
	assert_true(p.hits.is_empty(), "grapple deals no damage")

func test_throw_spear_into_reactor_preview_reports_reactor_damage() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 4))
	var p := ActionPreview.build(s, lancer, "throw_spear", Vector2i(6, 6))
	assert_true(p.hits_reactor)
	assert_eq(p.reactor_damage, MechActions.THROW_DMG)
