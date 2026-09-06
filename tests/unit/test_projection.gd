extends GutTest

func test_asset_geometry() -> void:
	var image := GridView.TILE.get_image()
	assert_eq(image.get_size(), Vector2i(32, 32))
	assert_eq(image.get_pixel(0, 0).a, 0.0)
	assert_eq(image.get_pixel(16, 8).a, 1.0)
	assert_eq(GridView.TEXTURE_ANCHOR, Vector2(32, 16))

func test_every_cell_center_round_trips() -> void:
	for y: int in 12:
		for x: int in 12:
			var c := Vector2i(x, y)
			assert_eq(GridView.world_to_cell(GridView.cell_to_world(c)), c)

func test_interior_near_all_corners_and_edges() -> void:
	for y: int in 12:
		for x: int in 12:
			var c := Vector2i(x, y)
			var center := GridView.cell_to_world(c)
			var poly := GridView.cell_polygon(c)
			for i: int in 4:
				for p: Vector2 in [center.lerp(poly[i], 0.99), center.lerp((poly[i] + poly[(i + 1) % 4]) * 0.5, 0.99)]:
					assert_true(GridView.cell_contains_point(c, p))
					assert_eq(GridView.world_to_cell(p), c)

func test_shared_edges_choose_neighbor_deterministically() -> void:
	var c := Vector2i(5, 5)
	for dir: Vector2i in Grid.DIRS:
		var a := GridView.cell_to_world(c)
		var b := GridView.cell_to_world(c + dir)
		assert_eq(GridView.world_to_cell(a.lerp(b, 0.499)), c)
		assert_eq(GridView.world_to_cell(a.lerp(b, 0.501)), c + dir)
		assert_eq(GridView.world_to_cell(a.lerp(b, 0.5)), c + dir if dir.x + dir.y > 0 else c)
	assert_eq(GridView.world_to_cell(GridView.cell_to_world(c) + Vector2(32, 0)), Vector2i(6, 5))
	assert_eq(GridView.world_to_cell(GridView.cell_to_world(c) + Vector2(0, 16)), Vector2i(6, 6))

func test_overlapping_bounding_rectangles_use_diamond() -> void:
	var p := GridView.cell_to_world(Vector2i(5, 5)) + Vector2(25, 12)
	assert_false(GridView.cell_contains_point(Vector2i(5, 5), p))
	assert_eq(GridView.world_to_cell(p), Vector2i(6, 5))

func test_outer_edges_and_outside_board() -> void:
	for c: Vector2i in [Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 11), Vector2i(11, 11)]:
		for dir: Vector2i in Grid.DIRS:
			var outside := c + dir
			if outside.x >= 0 and outside.y >= 0 and outside.x < 12 and outside.y < 12:
				continue
			var a := GridView.cell_to_world(c)
			var b := GridView.cell_to_world(outside)
			assert_eq(GridView.world_to_cell(a.lerp(b, 0.5)), c)
			assert_eq(GridView.world_to_cell(a.lerp(b, 0.501)), GridView.INVALID_CELL)
	for p: Vector2 in [Vector2.ZERO, Vector2(40, 220), Vector2(808, 220), Vector2(424, 620)]:
		assert_eq(GridView.world_to_cell(p), GridView.INVALID_CELL)

func test_both_missions_views_do_not_mutate_state() -> void:
	for id: String in Mission.ids():
		var state := BattleState.new(Mission.by_id(id))
		var before := var_to_bytes_with_objects(state)
		var view := GridView.new()
		view.setup(state)
		for y: int in state.grid.height:
			for x: int in state.grid.width:
				var c := Vector2i(x, y)
				assert_eq(GridView.world_to_cell(GridView.cell_to_world(c)), c)
		for u: Unit in state.units.values():
			var uv := UnitView.new()
			uv.setup(u)
			assert_eq(uv.position, GridView.cell_to_world(u.pos))
			uv.free()
		for o: GridObject in state.objects.values():
			var ov := GridObjectView.new()
			ov.setup(o)
			assert_eq(ov.position, GridView.cell_to_world(o.pos))
			ov.free()
		view.free()
		assert_eq(var_to_bytes_with_objects(state), before)

func test_bounds_fit_beside_hud_and_depth_tracks_animation() -> void:
	var bounds := GridView.board_visual_bounds()
	assert_lte(bounds.end.x, Hud.PANEL_POS.x)
	assert_lte(bounds.end.y, 900.0)
	var a := GridView.cell_to_world(Vector2i(2, 2))
	var b := GridView.cell_to_world(Vector2i(3, 2))
	assert_lt(GridView.visual_depth(a), GridView.visual_depth(a.lerp(b, 0.5)))
	assert_lt(GridView.visual_depth(a.lerp(b, 0.5)), GridView.visual_depth(b))
