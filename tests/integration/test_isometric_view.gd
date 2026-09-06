extends GutTest

func _hover(b: Battle, cell: Vector2i) -> void:
	var event := InputEventMouseMotion.new()
	event.position = b._world_to_screen(GridView.cell_to_world(cell))
	b._unhandled_input(event)

func _click(b: Battle, cell: Vector2i) -> void:
	var event := InputEventMouseButton.new()
	event.position = b._world_to_screen(GridView.cell_to_world(cell))
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	b._unhandled_input(event)

func _settle(b: Battle) -> void:
	while b._busy:
		await get_tree().process_frame

func _aligned(b: Battle) -> void:
	for uv: UnitView in b.unit_views.values():
		assert_eq(uv.position, GridView.cell_to_world(uv.unit.pos))
	for ov: GridObjectView in b.object_views:
		assert_eq(ov.position, GridView.cell_to_world(ov.obj.pos))

func test_both_missions_hover_selection_move_and_enemy_playback() -> void:
	for id: String in Mission.ids():
		var b := Battle.new()
		b.mission_id = id
		add_child_autofree(b)
		for y: int in 12:
			for x: int in 12:
				_hover(b, Vector2i(x, y))
				assert_eq(b.hover_cell, Vector2i(x, y))
		for m: Unit in b.state.player_mechs():
			b.selected_id = -1
			_click(b, m.pos)
			assert_eq(b.selected_id, m.id)
			var dest: Vector2i = b.state.reachable_for(m).keys()[0]
			_hover(b, dest)
			assert_true(b.overlay._layers["path"]["cells"].has(dest))
			_click(b, dest)
			await _settle(b)
			assert_eq(m.pos, dest)
			_aligned(b)
		await b._on_end_turn()
		_aligned(b)
		assert_false(b.state.pending_spawns.is_empty())
		assert_false(b.annot._sils.is_empty())
		b.queue_free()
		await get_tree().process_frame

func _fixture(kind: Unit.Kind) -> Battle:
	var b := Battle.new()
	add_child_autofree(b)
	for uv: UnitView in b.unit_views.values():
		uv.free()
	for ov: GridObjectView in b.object_views:
		ov.free()
	b.unit_views.clear()
	b.object_views.clear()
	b.state = TestUtil.bare_state()
	for w: Vector2i in b.state.grid.wall_cells():
		b.state.grid.set_wall(w, false)
	var m := TestUtil.add(b.state, kind, Unit.Team.PLAYER, Vector2i(3, 4))
	m.ap = m.max_ap
	b._add_unit_view(m)
	b.selected_id = m.id
	return b

func test_two_stage_grapple_and_throw_input_and_playback() -> void:
	var b := _fixture(Unit.Kind.GRAPPLER)
	var foe := TestUtil.add(b.state, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(3, 1))
	b._add_unit_view(foe)
	b.pending_action = "grapple"
	_click(b, foe.pos)
	assert_eq(b.focus_cell, foe.pos)
	_hover(b, Vector2i(3, 3))
	assert_true(b.annot._arrows.has("disp_0"))
	_click(b, Vector2i(3, 3))
	await _settle(b)
	assert_eq(foe.pos, Vector2i(3, 3))
	_aligned(b)
	b.pending_action = "throw"
	_click(b, foe.pos)
	assert_eq(b.focus_cell, foe.pos)
	_hover(b, Vector2i(5, 3))
	_click(b, Vector2i(5, 3))
	await _settle(b)
	assert_eq(foe.pos, Vector2i(5, 3))
	_aligned(b)

func test_spear_shield_lunge_push_charge_and_death_playback() -> void:
	var b := _fixture(Unit.Kind.LANCER)
	var m: Unit = b.state.units[b.selected_id]
	var foe := TestUtil.add(b.state, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(3, 3))
	b._add_unit_view(foe)
	await b._do_action(m, "thrust", foe.pos)
	_aligned(b)
	await b._do_action(m, "throw_spear", foe.pos)
	_aligned(b)
	assert_false(m.has_spear)
	var spear := Vector2i.ZERO
	for o: GridObject in b.state.objects.values():
		if o.kind == GridObject.Kind.THROWN_SPEAR:
			spear = o.pos
	b.state.move_unit(m, spear + Vector2i(0, 1))
	await b.unit_views[m.id].tween_to(m.pos, 0.01)
	await b._do_action(m, "retrieve_spear", spear)
	assert_true(m.has_spear)
	_aligned(b)
	var charger := TestUtil.add(b.state, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, 1))
	b._add_unit_view(charger)
	b.state.move_unit(charger, Vector2i(1, 4))
	await b._play_one({"t": "charge_move", "id": charger.id, "to": charger.pos})
	_aligned(b)
	b.state.damage_unit(charger, 999)
	await b._play(b.state.take_events())
	assert_false(b.unit_views.has(charger.id))
	var shield_b := _fixture(Unit.Kind.BULWARK)
	var bulwark: Unit = shield_b.state.units[shield_b.selected_id]
	await shield_b._do_action(bulwark, "deploy_shield", Vector2i(4, 4))
	_aligned(shield_b)
	assert_true(bulwark.shield_deployed)
	await shield_b._do_action(bulwark, "retrieve_shield", Vector2i(4, 4))
	assert_false(bulwark.shield_deployed)
