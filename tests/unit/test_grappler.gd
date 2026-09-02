extends GutTest

## The reworked Grappler: variable-distance Grapple (enemy / ally / self),
## omnidirectional Throw, and the shared prediction path. Grapple deals no
## damage; Throw slams via the common Push rules. Both go through
## MechActions.grapple_plan / throw_plan, which the preview also uses.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func _grappler(s: BattleState, pos: Vector2i) -> Unit:
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, pos)
	g.ap = 2
	return g

# ------------------------------------------------------------- grapple: distance

func test_grapple_enemy_one_tile() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	assert_true(s.player_action(g, "grapple", Vector2i(6, 5), {"dest": Vector2i(5, 5)}))
	assert_eq(foe.pos, Vector2i(5, 5), "pulled exactly one tile")
	assert_eq(foe.hp, foe.max_hp, "grapple never damages")
	assert_eq(g.ap, 1, "grapple costs 1 AP")

func test_grapple_enemy_two_tiles() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	assert_true(s.player_action(g, "grapple", Vector2i(6, 5), {"dest": Vector2i(4, 5)}))
	assert_eq(foe.pos, Vector2i(4, 5))

func test_grapple_enemy_three_tiles() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	assert_true(s.player_action(g, "grapple", Vector2i(6, 5), {"dest": Vector2i(3, 5)}))
	assert_eq(foe.pos, Vector2i(3, 5), "full pull, up against the grappler")

func test_grapple_cannot_exceed_range() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(7, 5))   # 5 away, range 4
	assert_false(Vector2i(7, 5) in ActionPreview.valid_targets(s, g, "grapple"))
	assert_false(s.player_action(g, "grapple", Vector2i(7, 5), {"dest": Vector2i(6, 5)}))
	assert_eq(foe.pos, Vector2i(7, 5))
	assert_eq(g.ap, 2, "an illegal action spends no AP")

func test_grapple_cannot_pull_past_a_blocker() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	s.grid.set_wall(Vector2i(4, 5), true)   # wall between focus and grappler
	var dests := MechActions.grapple_dests(s, g, Vector2i(6, 5))
	assert_eq(dests, [Vector2i(5, 5)] as Array[Vector2i], "reel stops at the wall")

# ------------------------------------------------------------- grapple: ally / self

func test_grapple_ally_repositions_without_damage() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	var ally := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 5))
	assert_true(s.player_action(g, "grapple", Vector2i(6, 5), {"dest": Vector2i(4, 5)}))
	assert_eq(ally.pos, Vector2i(4, 5))
	assert_eq(ally.hp, ally.max_hp)

func test_grapple_terrain_reels_the_grappler_itself() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	s.grid.set_wall(Vector2i(6, 5), true)
	assert_true(Vector2i(6, 5) in ActionPreview.valid_targets(s, g, "grapple"), "the wall is a valid anchor")
	assert_true(s.player_action(g, "grapple", Vector2i(6, 5), {"dest": Vector2i(5, 5)}))
	assert_eq(g.pos, Vector2i(5, 5), "reeled itself up to the wall")
	assert_eq(g.hp, g.max_hp)
	assert_eq(g.ap, 1)

func test_grapple_self_can_stop_short() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	s.grid.set_wall(Vector2i(6, 5), true)
	assert_true(s.player_action(g, "grapple", Vector2i(6, 5), {"dest": Vector2i(4, 5)}))
	assert_eq(g.pos, Vector2i(4, 5), "player chose a nearer landing tile")

# ------------------------------------------------------------- grapple: intent

func test_grapple_can_interrupt_a_charge() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 3))
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(2, 6))
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 6))
	s.telegraphs.append(Telegraph.charge(charger.id, [] as Array[Vector2i], Vector2i(1, 0), Mission.CHARGER_DMG, 99))

	var p := ActionPreview.build(s, g, "grapple", Vector2i(2, 6), {"dest": Vector2i(2, 4)})
	assert_true(p.valid)
	var moves: Dictionary = {}
	for d: Dictionary in p.displacements:
		moves[d["id"]] = d["to"]
	var changes := Intent.project(s, moves, [])
	assert_eq(changes.size(), 1)
	assert_true(changes[0].interrupted, "charger reeled off row 6, no longer hits the Lancer")
	assert_eq(changes[0].safe_cell, lancer.pos)

# ------------------------------------------------------------- throw: direction

func test_throw_each_open_cardinal_direction() -> void:
	var cases := {
		"north": [Vector2i(3, 1), Vector2i(3, 1)],
		"east": [Vector2i(5, 3), Vector2i(5, 3)],
		"west": [Vector2i(1, 3), Vector2i(1, 3)],
	}
	for name: String in cases:
		var s := _state()
		var g := _grappler(s, Vector2i(3, 4))
		var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 3))
		var dest: Vector2i = cases[name][0]
		assert_true(s.player_action(g, "throw", Vector2i(3, 3), {"dest": dest}), name)
		assert_eq(foe.pos, cases[name][1], "flung " + name)

func test_throw_cannot_target_the_grappler_direction() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 3))
	var cells: Array = []
	for e: Dictionary in MechActions.throw_dests(s, g, Vector2i(3, 3)):
		cells.append(e["cell"])
	assert_false(Vector2i(3, 4) in cells, "cannot throw a unit back into the Grappler")
	assert_false(s.player_action(g, "throw", Vector2i(3, 3), {"dest": Vector2i(3, 4)}))

# ------------------------------------------------------------- throw: distance

func test_throw_honours_chosen_distance() -> void:
	for k: int in [1, 2, 3]:
		var s := _state()
		var g := _grappler(s, Vector2i(3, 4))
		var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 3))
		var dest := Vector2i(3 + k, 3)
		assert_true(s.player_action(g, "throw", Vector2i(3, 3), {"dest": dest}), "dist %d" % k)
		assert_eq(foe.pos, dest, "landed exactly %d tiles east" % k)

# ------------------------------------------------------------- throw: collisions

func test_throw_into_wall_slams_for_collision() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(3, 3))
	s.grid.set_wall(Vector2i(5, 3), true)
	assert_true(s.player_action(g, "throw", Vector2i(3, 3), {"dest": Vector2i(5, 3)}), "aim at the wall")
	assert_eq(foe.pos, Vector2i(4, 3), "stopped against the wall")
	assert_eq(foe.hp, foe.max_hp - MechActions.GRAPPLER_THROW_COLLISION)

func test_throw_into_another_unit_hurts_both() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	var thrown := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(3, 3))
	var blocker := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 3))
	assert_true(s.player_action(g, "throw", Vector2i(3, 3), {"dest": Vector2i(5, 3)}))
	assert_eq(thrown.pos, Vector2i(4, 3))
	assert_eq(thrown.hp, thrown.max_hp - MechActions.GRAPPLER_THROW_COLLISION)
	assert_eq(blocker.hp, blocker.max_hp - MechActions.GRAPPLER_THROW_COLLISION)

func test_throw_into_board_edge_slams() -> void:
	# No pit / hazard object type exists in this prototype; the board edge is
	# the only impassable boundary and it slams through the shared Push rules.
	var s := _state()
	var g := _grappler(s, Vector2i(9, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(10, 5))
	assert_true(s.player_action(g, "throw", Vector2i(10, 5), {"dest": Vector2i(11, 5)}))
	assert_eq(foe.pos, Vector2i(11, 5), "stopped at the last in-bounds cell")
	assert_eq(foe.hp, foe.max_hp - MechActions.GRAPPLER_THROW_COLLISION)

# ------------------------------------------------------------- throw: allies

func test_throw_ally_repositions_with_no_damage() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	var ally := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(3, 3))
	assert_true(s.player_action(g, "throw", Vector2i(3, 3), {"dest": Vector2i(5, 3)}))
	assert_eq(ally.pos, Vector2i(5, 3))
	assert_eq(ally.hp, ally.max_hp)

func test_ally_cannot_be_slammed() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	var ally := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(3, 3))
	s.grid.set_wall(Vector2i(5, 3), true)
	var cells: Array = []
	for e: Dictionary in MechActions.throw_dests(s, g, Vector2i(3, 3)):
		cells.append(e["cell"])
	assert_false(Vector2i(5, 3) in cells, "the wall is never offered as an ally throw target")
	assert_false(s.player_action(g, "throw", Vector2i(3, 3), {"dest": Vector2i(5, 3)}), "and it is rejected")
	# a gentle 1-tile placement beside the wall is still fine
	assert_true(s.player_action(g, "throw", Vector2i(3, 3), {"dest": Vector2i(4, 3)}))
	assert_eq(ally.pos, Vector2i(4, 3))
	assert_eq(ally.hp, ally.max_hp, "placed, not slammed")

# ------------------------------------------------------------- prediction parity

func test_prediction_matches_final_position() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 3))
	var p := ActionPreview.build(s, g, "throw", Vector2i(3, 3), {"dest": Vector2i(3, 1)})
	assert_true(p.valid)
	assert_eq(p.displacements[0]["to"], Vector2i(3, 1))
	MechActions.execute(s, g, "throw", Vector2i(3, 3), {"dest": Vector2i(3, 1)})
	assert_eq(foe.pos, p.displacements[0]["to"], "execution lands exactly where the preview said")

func test_prediction_matches_collision_result() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(3, 4))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(3, 3))
	s.grid.set_wall(Vector2i(5, 3), true)
	var p := ActionPreview.build(s, g, "throw", Vector2i(3, 3), {"dest": Vector2i(5, 3)})
	assert_eq(p.hits.size(), 1)
	assert_eq(p.hits[0]["id"], foe.id)
	var predicted: int = p.hits[0]["amount"]
	var before: int = foe.hp
	MechActions.execute(s, g, "throw", Vector2i(3, 3), {"dest": Vector2i(5, 3)})
	assert_eq(before - foe.hp, predicted, "preview's collision number == actual damage")

# ------------------------------------------------------------- AP

func test_ap_consumption() -> void:
	var s := _state()
	var g := _grappler(s, Vector2i(2, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(2, 7))
	assert_eq(g.ap, 2)
	assert_true(s.player_action(g, "grapple", Vector2i(5, 5), {"dest": Vector2i(3, 5)}))
	assert_eq(g.ap, 1, "grapple -1 AP")
	assert_true(s.player_action(g, "throw", Vector2i(3, 5), {"dest": Vector2i(3, 4)}))
	assert_eq(g.ap, 0, "throw -1 AP")
	assert_false(s.player_action(g, "grapple", Vector2i(2, 7), {"dest": Vector2i(2, 6)}), "no AP left")
