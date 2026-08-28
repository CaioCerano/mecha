class_name Battle
extends Node2D

## Wires input -> BattleState -> animated playback. Owns the state and all the
## view nodes; holds only selection/targeting UI state itself.

const REACH_COL: Color = Color(0.35, 0.60, 1.00, 0.20)
const TARGET_COL: Color = Color(1.00, 0.90, 0.35, 0.28)
const LINE_COL: Color = Color(1.00, 0.55, 0.20, 0.40)
const AOE_COL: Color = Color(1.00, 0.35, 0.20, 0.32)
const PUSH_COL: Color = Color(1.00, 1.00, 1.00, 0.85)
const LAND_COL: Color = Color(0.40, 0.65, 1.00, 0.95)
const TELE_FILL: Color = Color(1.00, 0.20, 0.20, 0.22)
const TELE_EDGE: Color = Color(1.00, 0.35, 0.35, 0.90)
const MORTAR_COL: Color = Color(0.55, 0.85, 1.00, 0.22)
const FF_COL: Color = Color(1.00, 0.15, 0.15, 1.0)
const AFFECT_COL: Color = Color(1, 1, 1, 0.9)

var state: BattleState
var grid_view: GridView
var overlay: OverlayLayer
var hud: Hud
var _units_root: Node2D
var _objects_root: Node2D
var unit_views: Dictionary[int, UnitView] = {}
var object_views: Array[GridObjectView] = []
var reactor_view: GridObjectView

var selected_id: int = -1
var pending_action: String = ""       # "" | "move" | an action id
var hover_cell: Vector2i = Vector2i(-1, -1)
var _busy: bool = false

func _ready() -> void:
	_start_mission()

# ---------------------------------------------------------------- setup

func _start_mission() -> void:
	for node: Node in [grid_view, overlay, _units_root, _objects_root, hud]:
		if is_instance_valid(node):
			node.queue_free()
	unit_views.clear()
	object_views.clear()
	reactor_view = null
	selected_id = -1
	pending_action = ""
	_busy = false

	state = BattleState.new()

	grid_view = GridView.new()
	add_child(grid_view)
	grid_view.setup(state)

	overlay = OverlayLayer.new()
	add_child(overlay)

	_objects_root = Node2D.new()
	add_child(_objects_root)
	_units_root = Node2D.new()
	add_child(_units_root)

	for pos: Vector2i in state.objects:
		_add_object_view(state.objects[pos])
	for id: int in state.units:
		_add_unit_view(state.units[id])

	hud = Hud.new()
	add_child(hud)
	hud.setup(state)
	hud.action_chosen.connect(_on_action_chosen)
	hud.mech_chosen.connect(_on_mech_chosen)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.restart_pressed.connect(_start_mission)

	refresh()

func _add_unit_view(u: Unit) -> void:
	var uv := UnitView.new()
	_units_root.add_child(uv)
	uv.setup(u)
	unit_views[u.id] = uv

func _add_object_view(o: GridObject) -> void:
	var ov := GridObjectView.new()
	_objects_root.add_child(ov)
	ov.setup(o)
	object_views.append(ov)
	if o.kind == GridObject.Kind.REACTOR:
		reactor_view = ov

# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if _busy or state == null:
		return
	if event is InputEventMouseMotion:
		var c: Vector2i = GridView.world_to_cell(event.position)
		if c != hover_cell:
			hover_cell = c
			_update_overlays()
		return
	if event.is_action_pressed("cancel_action"):
		if pending_action != "":
			pending_action = ""
			refresh()
		elif selected_id != -1:
			selected_id = -1
			refresh()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state.phase == BattleState.Phase.PLAYER:
			_on_click(GridView.world_to_cell(event.position))

func _on_click(cell: Vector2i) -> void:
	var sel: Unit = state.units.get(selected_id)
	if not state.grid.in_bounds(cell):
		selected_id = -1
		pending_action = ""
		refresh()
		return

	if pending_action != "":
		if sel != null and sel.is_alive():
			if pending_action == "move":
				if state.player_move(sel, cell):
					pending_action = ""
					_after_local_action()
					return
			elif cell in ActionPreview.valid_targets(state, sel, pending_action):
				_do_action(sel, pending_action, cell)
				return
		pending_action = ""
		refresh()
		return

	var clicked: Unit = state.unit_at(cell)
	if clicked != null and clicked.is_player() and clicked.is_alive():
		selected_id = clicked.id
		refresh()
		return
	if sel != null and sel.is_alive() and cell in state.reachable_for(sel):
		if state.player_move(sel, cell):
			_after_local_action()
			return
	selected_id = -1
	refresh()

# ---------------------------------------------------------------- hud signals

func _on_mech_chosen(id: int) -> void:
	if _busy:
		return
	selected_id = id
	pending_action = ""
	refresh()

func _on_action_chosen(action_id: String) -> void:
	if _busy:
		return
	pending_action = "" if pending_action == action_id else action_id
	refresh()

func _on_end_turn() -> void:
	if _busy or state.phase != BattleState.Phase.PLAYER:
		return
	selected_id = -1
	pending_action = ""
	state.end_player_turn()
	await _play(state.take_events())
	_after_resolve()

# ---------------------------------------------------------------- action flow

func _do_action(sel: Unit, action_id: String, cell: Vector2i) -> void:
	pending_action = ""
	if not state.player_action(sel, action_id, cell):
		refresh()
		return
	await _play(state.take_events())
	_after_resolve()

func _after_local_action() -> void:
	await _play(state.take_events())
	_after_resolve()

func _after_resolve() -> void:
	refresh()
	if state.phase == BattleState.Phase.WON:
		hud.show_banner(true)
	elif state.phase == BattleState.Phase.LOST:
		hud.show_banner(false)

# ---------------------------------------------------------------- rendering

func refresh() -> void:
	_update_overlays()
	for id: int in unit_views:
		var uv: UnitView = unit_views[id]
		uv.set_selected(id == selected_id)
		uv.refresh()
	if is_instance_valid(reactor_view):
		reactor_view.refresh()
	hud.refresh(selected_id, pending_action, _hint())

func _update_overlays() -> void:
	if overlay == null:
		return
	overlay.clear_all()

	var i: int = 0
	for tg: Telegraph in state.telegraphs:
		overlay.set_fill("tele_%d" % i, tg.cells, TELE_FILL)
		overlay.set_outline("teleedge_%d" % i, tg.cells, TELE_EDGE)
		i += 1
	i = 0
	for pm: Dictionary in state.pending_mortars:
		overlay.set_fill("pm_%d" % i, pm["cells"], MORTAR_COL)
		i += 1

	if state.phase != BattleState.Phase.PLAYER:
		return
	var sel: Unit = state.units.get(selected_id)
	if sel == null or not sel.is_alive():
		return

	if pending_action == "" or pending_action == "move":
		overlay.set_fill("reach", state.reachable_for(sel).keys(), REACH_COL)
		return

	var targets: Array[Vector2i] = ActionPreview.valid_targets(state, sel, pending_action)
	overlay.set_fill("targets", targets, TARGET_COL)
	if not hover_cell in targets:
		return
	var p := ActionPreview.build(state, sel, pending_action, hover_cell)
	if not p.valid:
		return
	if not p.line_cells.is_empty():
		overlay.set_fill("line", p.line_cells, LINE_COL)
	if not p.aoe_cells.is_empty():
		overlay.set_fill("aoe", p.aoe_cells, AOE_COL)
	if p.push_to.x > -9000 and p.push_to != p.push_from:
		overlay.set_rings("push", [p.push_to], PUSH_COL)
	if p.spear_landing.x >= 0:
		overlay.set_rings("land", [p.spear_landing], LAND_COL)
	if p.hits_reactor:
		overlay.set_outline("ff", [state.reactor.pos], FF_COL)
	var affected: Array[Vector2i] = []
	for uid: int in p.affected_ids:
		var u: Unit = state.units.get(uid)
		if u != null:
			affected.append(u.pos)
	if not affected.is_empty():
		overlay.set_outline("affected", affected, AFFECT_COL)

func _hint() -> String:
	match state.phase:
		BattleState.Phase.WON:
			return "Reactor held. Mission complete."
		BattleState.Phase.LOST:
			return "Reactor lost or squad destroyed."
		BattleState.Phase.ENEMY:
			return "Enemy turn resolving..."
	var sel: Unit = state.units.get(selected_id)
	if sel == null:
		return "Select a mech — click it or use the squad list. Then move (1 AP) and act (1 AP)."
	if pending_action == "" or pending_action == "move":
		return "%s selected. Click a blue tile to move, or choose an action." % sel.display_name()
	return "Aim %s — click a gold tile. Right-click / Esc to cancel." % MechActions.action_label(pending_action)

# ---------------------------------------------------------------- playback

func _play(events: Array) -> void:
	_busy = true
	if overlay != null:
		overlay.clear_all()
	for ev: Dictionary in events:
		await _play_one(ev)
	_busy = false

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _play_one(ev: Dictionary) -> void:
	match ev["t"]:
		"move":
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null:
				await uv.tween_path(ev["path"])
		"charge_move":
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null:
				await uv.tween_to(ev["to"], 0.20)
		"attack":
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null:
				await uv.lunge_at(ev["target"])
		"push":
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null and ev["from"] != ev["to"]:
				await uv.tween_to(ev["to"], 0.12)
		"damage":
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null:
				uv.flash_damage()
				uv.refresh()
			_floater(ev["pos"], "-%d" % ev["amount"])
			await _wait(0.12)
		"reactor_damage":
			if is_instance_valid(reactor_view):
				reactor_view.flash()
				reactor_view.refresh()
			_floater(ev["pos"], "-%d" % ev["amount"])
			await _wait(0.16)
		"death":
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null:
				unit_views.erase(ev["id"])
				await uv.die()
		"spawn":
			var u: Unit = state.units.get(ev["id"])
			if u != null and not unit_views.has(u.id):
				_add_unit_view(u)
				var uv: UnitView = unit_views[u.id]
				uv.modulate.a = 0.0
				create_tween().tween_property(uv, "modulate:a", 1.0, 0.18)
				await _wait(0.08)
		"spear_throw":
			await _spear_fly(ev["from"], ev["to"])
			_spawn_object_at(ev["to"])
		"spear_retrieve":
			_despawn_object_at(ev["from"])
			await _wait(0.05)
		"shield_deploy":
			_spawn_object_at(ev["pos"])
			await _wait(0.08)
		"shield_retrieve":
			_despawn_object_at(ev["from"])
			await _wait(0.05)
		"cannon":
			overlay.set_fill("fx", ev["cells"], LINE_COL)
			await _wait(0.16)
			overlay.clear_all()
		"telegraph_new":
			overlay.set_outline("fx", ev["cells"], TELE_EDGE)
			await _wait(0.18)
			overlay.clear_all()
		"telegraph_resolve", "mortar_resolve":
			overlay.set_fill("fx", ev["cells"], Color(1.0, 0.35, 0.20, 0.55))
			await _wait(0.22)
			overlay.clear_all()
		"wall_destroyed":
			grid_view.queue_redraw()
			await _wait(0.05)
		_:
			pass

func _floater(cell: Vector2i, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.position = GridView.cell_to_world(cell) + Vector2(-8, -12)
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 28, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(l.queue_free)

func _spear_fly(from: Vector2i, to: Vector2i) -> void:
	var s := Line2D.new()
	s.points = PackedVector2Array([Vector2(-16, 11), Vector2(16, -11)])
	s.width = 4.0
	s.default_color = Color(0.8, 0.9, 1.0)
	s.position = GridView.cell_to_world(from)
	add_child(s)
	var tw := create_tween()
	tw.tween_property(s, "position", GridView.cell_to_world(to), 0.22)
	await tw.finished
	s.queue_free()

func _spawn_object_at(cell: Vector2i) -> void:
	var o: GridObject = state.object_at(cell)
	if o == null:
		return
	_add_object_view(o)

func _despawn_object_at(cell: Vector2i) -> void:
	for ov: GridObjectView in object_views.duplicate():
		if ov.obj != null and ov.obj.kind != GridObject.Kind.REACTOR and ov.obj.pos == cell:
			object_views.erase(ov)
			ov.queue_free()
