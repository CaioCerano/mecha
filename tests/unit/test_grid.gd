extends GutTest

## Grid geometry: reachability respects range + walls + blockers, pathfinding
## routes around walls, straight-line traces stop on the right things.

func test_reachable_respects_range() -> void:
	var g := Grid.new(12, 12)
	var reach := g.reachable(Vector2i(5, 5), 2, {})
	assert_true(reach.has(Vector2i(5, 7)), "2 straight steps is in range")
	assert_false(reach.has(Vector2i(5, 8)), "3 steps is out of range")
	assert_eq(reach.get(Vector2i(7, 5)), 2)
	assert_false(reach.has(Vector2i(5, 5)), "start cell is not included")

func test_reachable_blocked_by_wall_and_units() -> void:
	var g := Grid.new(12, 12, [Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 4)] as Array[Vector2i])
	var blocked: Dictionary[Vector2i, bool] = {Vector2i(5, 6): true}
	var reach := g.reachable(Vector2i(5, 5), 3, blocked)
	assert_false(reach.has(Vector2i(7, 5)), "wall wall at x=6 blocks the straight route")
	assert_false(reach.has(Vector2i(5, 6)), "blocked cell is not enterable")
	assert_true(reach.has(Vector2i(4, 5)), "open direction still reachable")

func test_find_path_routes_around_wall() -> void:
	var g := Grid.new(12, 12, [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6)] as Array[Vector2i])
	var path := g.find_path(Vector2i(4, 5), Vector2i(6, 5), {})
	assert_gt(path.size(), 2, "must detour around the 3-cell wall")
	assert_eq(path[path.size() - 1], Vector2i(6, 5))
	assert_false(path.has(Vector2i(5, 5)), "path never crosses a wall cell")

func test_find_path_goal_may_be_blocked() -> void:
	var g := Grid.new(12, 12)
	var blocked: Dictionary[Vector2i, bool] = {Vector2i(6, 5): true}
	var path := g.find_path(Vector2i(3, 5), Vector2i(6, 5), blocked)
	assert_eq(path[path.size() - 1], Vector2i(6, 5), "goal itself is allowed even when blocked")
	assert_eq(path[path.size() - 2], Vector2i(5, 5), "the step before the goal is a real open cell")

func test_line_cells_clip_to_board() -> void:
	var g := Grid.new(12, 12)
	var cells := g.line_cells(Vector2i(10, 0), Vector2i(1, 0), 5)
	assert_eq(cells, [Vector2i(11, 0)] as Array[Vector2i])

func test_cardinal_dir() -> void:
	assert_eq(Grid.cardinal_dir(Vector2i(2, 2), Vector2i(5, 2)), Vector2i(1, 0))
	assert_eq(Grid.cardinal_dir(Vector2i(2, 2), Vector2i(2, 0)), Vector2i(0, -1))
	assert_eq(Grid.cardinal_dir(Vector2i(2, 2), Vector2i(4, 5)), Vector2i.ZERO, "diagonals are not cardinal")

func test_line_attack_stops_at_wall_then_unit_then_reactor() -> void:
	var s := TestUtil.bare_state()
	# clear the mission walls that would interfere, we set our own
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	var shooter := TestUtil.add(s, Unit.Kind.ARTILLERY, Unit.Team.PLAYER, Vector2i(1, 1))
	var target := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(4, 1))

	var la := s.line_attack(shooter.pos, Vector2i(1, 0), 8)
	assert_eq(la["hit_unit"], target, "hits the first unit in the line")
	assert_eq(la["cells"][la["cells"].size() - 1], Vector2i(4, 1))

	s.grid.set_wall(Vector2i(3, 1), true)
	var la2 := s.line_attack(shooter.pos, Vector2i(1, 0), 8)
	assert_null(la2["hit_unit"], "wall now blocks before the unit")
	assert_true(la2["blocked_by_wall"])
