class_name Battle
extends Node2D

## Wires input -> BattleState -> animated playback. Owns the state and all the
## view nodes; holds only selection/targeting UI state itself.

const REACH_COL: Color = Color(0.35, 0.60, 1.00, 0.20)
const REACH_SPENT_COL: Color = Color(0.55, 0.57, 0.62, 0.12)
const PATH_COL: Color = Color(0.50, 0.78, 1.00, 0.45)
const TARGET_COL: Color = Color(1.00, 0.82, 0.25, 0.85)     # valid target: gold outline
const TARGET_HOT_COL: Color = Color(1.00, 0.85, 0.30, 0.28) # hovered target: gold fill
const LINE_COL: Color = Color(1.00, 0.55, 0.20, 0.35)
const AOE_COL: Color = Color(1.00, 0.35, 0.20, 0.30)
const PUSH_COL: Color = Color(1.00, 1.00, 1.00, 0.95)       # forced-movement arrows
const LAND_COL: Color = Color(0.55, 0.75, 1.00, 0.95)
const DMG_COL: Color = Color(1.00, 0.50, 0.45)
const TELE_FILL: Color = Color(1.00, 0.20, 0.20, 0.20)
const TELE_EDGE: Color = Color(1.00, 0.35, 0.35, 0.90)
const TELE_FADE: Color = Color(1.00, 0.35, 0.35, 0.28)
const SPAWN_FILL: Color = Color(1.00, 0.45, 0.80, 0.16)
const SPAWN_EDGE: Color = Color(1.00, 0.45, 0.80, 0.95)
const FF_COL: Color = Color(1.00, 0.15, 0.15, 1.0)
const AFFECT_COL: Color = Color(1, 1, 1, 0.9)
const BOOM_COL: Color = Color(1.00, 0.55, 0.15, 0.40)
const BOOM_EDGE: Color = Color(1.00, 0.70, 0.25, 0.95)
const GRAB_COL: Color = Color(0.55, 0.90, 1.00, 1.0)       # the grabbed focus (stage 2)
const DEST_COL: Color = Color(0.50, 0.80, 1.00, 0.95)      # a valid placement tile
const SLAM_COL: Color = Color(1.00, 0.45, 0.30, 0.95)      # a placement tile that slams

const NO_CELL: Vector2i = Vector2i(-9999, -9999)

var state: BattleState
var grid_view: GridView
var overlay: OverlayLayer
var annot: AnnotationLayer
var hud: Hud
var _units_root: Node2D
var _objects_root: Node2D
var unit_views: Dictionary[int, UnitView] = {}
var object_views: Array[GridObjectView] = []
var reactor_view: GridObjectView

## Which hand-designed mission to (re)start. Changed only by the HUD dev picker.
var mission_id: String = Mission.REACTOR_BREACH

var selected_id: int = -1
var pending_action: String = ""       # "" | "move" | an action id
var focus_cell: Vector2i = NO_CELL    # grapple/throw: the grabbed target (stage 2)
var hover_cell: Vector2i = Vector2i(-1, -1)
var _busy: bool = false

func _two_stage() -> bool:
	return pending_action == "grapple" or pending_action == "throw"

func _ready() -> void:
	_start_mission()

# ---------------------------------------------------------------- setup

func _start_mission() -> void:
	for node: Node in [grid_view, overlay, annot, _units_root, _objects_root, hud]:
		if is_instance_valid(node):
			node.queue_free()
	unit_views.clear()
	object_views.clear()
	reactor_view = null
	selected_id = -1
	pending_action = ""
	focus_cell = NO_CELL
	_busy = false

	state = BattleState.new(Mission.by_id(mission_id))

	grid_view = GridView.new()
	add_child(grid_view)
	grid_view.setup(state)

	overlay = OverlayLayer.new()
	add_child(overlay)

	_objects_root = Node2D.new()
	add_child(_objects_root)
	_units_root = Node2D.new()
	add_child(_units_root)

	annot = AnnotationLayer.new()
	add_child(annot)

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
	hud.mission_selected.connect(_on_mission_selected)

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
			hud.refresh(selected_id, pending_action, _hint(), _enemy_under_cursor(), _spawn_under_cursor())
		return
	if event.is_action_pressed("cancel_action"):
		if focus_cell != NO_CELL:
			focus_cell = NO_CELL         # step back from stage 2 to stage 1
			refresh()
		elif pending_action != "":
			pending_action = ""
			refresh()
		elif selected_id != -1:
			selected_id = -1
			refresh()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and state.phase == BattleState.Phase.PLAYER:
		if _handle_hotkey(event.keycode):
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state.phase == BattleState.Phase.PLAYER:
			_on_click(GridView.world_to_cell(event.position))

## 1-4 pick the Nth ability of the selected mech, M picks Move, Enter ends the
## turn. Returns true if the key was consumed.
func _handle_hotkey(keycode: int) -> bool:
	if keycode == KEY_ENTER or keycode == KEY_KP_ENTER:
		_on_end_turn()
		return true
	var sel: Unit = state.units.get(selected_id)
	if sel == null or not sel.is_alive():
		return false
	if keycode == KEY_M:
		_on_action_chosen("move")
		return true
	if keycode >= KEY_1 and keycode <= KEY_4:
		var acts: Array[String] = MechActions.available_actions(state, sel)
		var n: int = keycode - KEY_1
		if n < acts.size():
			_on_action_chosen(acts[n])
			return true
	return false

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
			elif _two_stage():
				_on_click_two_stage(sel, cell)
				return
			elif cell in ActionPreview.valid_targets(state, sel, pending_action):
				_do_action(sel, pending_action, cell)
				return
		pending_action = ""
		focus_cell = NO_CELL
		refresh()
		return

	var clicked: Unit = state.unit_at(cell)
	if clicked != null and clicked.is_player() and clicked.is_alive():
		selected_id = clicked.id
		refresh()
		return
	if sel != null and sel.is_alive() and cell in state.reachable_for(sel):
		if sel.ap < 1:
			return   # no AP — keep the mech selected, range stays visible (greyed)
		if state.player_move(sel, cell):
			_after_local_action()
			return
	selected_id = -1
	refresh()

## Grapple / Throw are two clicks: (1) grab a target, (2) choose where it goes.
func _on_click_two_stage(sel: Unit, cell: Vector2i) -> void:
	var focuses: Array[Vector2i] = ActionPreview.valid_targets(state, sel, pending_action)
	if focus_cell == NO_CELL:
		if cell in focuses:
			focus_cell = cell
			refresh()
		else:
			pending_action = ""
			refresh()
		return
	# stage 2
	if cell in _stage2_cells(sel):
		var grabbed: Vector2i = focus_cell
		focus_cell = NO_CELL
		_do_action_opts(sel, pending_action, grabbed, {"dest": cell})
		return
	if cell in focuses:
		focus_cell = cell           # grab a different target instead
		refresh()
		return
	focus_cell = NO_CELL            # clicked nothing useful -> back to stage 1
	refresh()

func _stage2_cells(sel: Unit) -> Array[Vector2i]:
	if pending_action == "grapple":
		return MechActions.grapple_dests(state, sel, focus_cell)
	if pending_action == "throw":
		var out: Array[Vector2i] = []
		for e: Dictionary in MechActions.throw_dests(state, sel, focus_cell):
			out.append(e["cell"])
		return out
	return []

# ---------------------------------------------------------------- hud signals

func _on_mission_selected(id: String) -> void:
	if id == mission_id:
		return
	mission_id = id
	_start_mission()

func _on_mech_chosen(id: int) -> void:
	if _busy:
		return
	selected_id = id
	pending_action = ""
	focus_cell = NO_CELL
	refresh()

func _on_action_chosen(action_id: String) -> void:
	if _busy:
		return
	pending_action = "" if pending_action == action_id else action_id
	focus_cell = NO_CELL
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
	await _do_action_opts(sel, action_id, cell, {})

func _do_action_opts(sel: Unit, action_id: String, cell: Vector2i, opts: Dictionary) -> void:
	pending_action = ""
	focus_cell = NO_CELL
	# telemetry: what this action would do to the board / enemy plans, from the
	# same preview the player just saw.
	_record_manipulation(sel, action_id, cell, opts)
	if not state.player_action(sel, action_id, cell, opts):
		refresh()
		return
	await _play(state.take_events())
	_after_resolve()

## Count "manipulation" effects (displaced enemies, repositioned allies, enemy
## intents interrupted / redirected) into telemetry, from the previewed outcome.
func _record_manipulation(sel: Unit, action_id: String, cell: Vector2i, opts: Dictionary) -> void:
	var p := ActionPreview.build(state, sel, action_id, cell, opts)
	if not p.valid:
		return
	var moves: Dictionary = {}
	for d: Dictionary in p.displacements:
		moves[d["id"]] = d["to"]
		var u: Unit = state.units.get(d["id"])
		if u == null or d["id"] == sel.id:
			continue
		if u.is_player():
			state.tel.bump("allies_repositioned")
		else:
			state.tel.bump("enemies_displaced")
	var removed: Dictionary = {}
	for h: Dictionary in p.hits:
		if h["lethal"]:
			var u2: Unit = state.units.get(h["id"])
			if u2 != null and not u2.is_player():
				removed[h["id"]] = true
	var blockers: Array[Vector2i] = []
	if action_id == "deploy_shield":
		blockers.append(cell)
	for ch: Intent.Change in Intent.project(state, moves, blockers, removed):
		if ch.interrupted:
			state.tel.bump("intents_interrupted")
		if ch.redirected:
			state.tel.bump("intents_redirected")

func _after_local_action() -> void:
	await _play(state.take_events())
	_after_resolve()

func _after_resolve() -> void:
	refresh()
	if state.phase == BattleState.Phase.WON:
		hud.show_banner(true)
		print(state.tel.summary_text(state))
	elif state.phase == BattleState.Phase.LOST:
		hud.show_banner(false)
		print(state.tel.summary_text(state))

# ---------------------------------------------------------------- rendering

func refresh() -> void:
	_update_overlays()
	for id: int in unit_views:
		var uv: UnitView = unit_views[id]
		uv.set_selected(id == selected_id)
		uv.refresh()
	if is_instance_valid(reactor_view):
		reactor_view.refresh()
	hud.refresh(selected_id, pending_action, _hint(), _enemy_under_cursor(), _spawn_under_cursor())

func _enemy_under_cursor() -> int:
	var u: Unit = state.unit_at(hover_cell)
	if u != null and not u.is_player() and u.is_alive():
		return u.id
	return -1

func _spawn_under_cursor() -> Dictionary:
	for sp: Dictionary in state.pending_spawns:
		if sp["cell"] == hover_cell:
			return sp
	return {}

func _update_overlays() -> void:
	if overlay == null:
		return
	overlay.clear_all()
	annot.clear_all()
	_update_hover_marks()

	# Enemy intent — planned attacks, reinforcements, and where the deterministic
	# movers (grunts / interceptors) will go — stays on the board through
	# everything the player does.
	_draw_telegraphs()
	_draw_spawn_telegraphs()
	if state.phase == BattleState.Phase.PLAYER:
		_draw_enemy_move_intents()

	if state.phase != BattleState.Phase.PLAYER:
		return
	var sel: Unit = state.units.get(selected_id)
	if sel == null or not sel.is_alive():
		return

	if pending_action == "" or pending_action == "move":
		var reach: Dictionary[Vector2i, int] = state.reachable_for(sel)
		if sel.ap < 1:
			# Out of AP: still show the footprint, greyed, so range stays readable
			# even though there's nothing left to spend.
			overlay.set_fill("reach", reach.keys(), REACH_SPENT_COL)
			return
		overlay.set_fill("reach", reach.keys(), REACH_COL)
		if reach.has(hover_cell):
			var path: Array[Vector2i] = state.grid.find_path(sel.pos, hover_cell, state.blocked_for_move())
			if not path.is_empty():
				overlay.set_fill("path", path, PATH_COL)
				annot.set_arrow("path", [sel.pos] + path, PATH_COL.lightened(0.2))
		return

	if _two_stage():
		_draw_two_stage(sel)
		return

	# --- ability targeting: distinct treatment from movement (gold outline) ---
	var targets: Array[Vector2i] = ActionPreview.valid_targets(state, sel, pending_action)
	overlay.set_outline("targets", targets, TARGET_COL)
	if not hover_cell in targets:
		return
	overlay.set_fill("target_hot", [hover_cell], TARGET_HOT_COL)

	var p := ActionPreview.build(state, sel, pending_action, hover_cell)
	if not p.valid:
		return
	_draw_ability_preview(sel, p)
	_draw_preview_intent(p)

## Everything a previewed action would do to enemy plans: fade rewritten
## charge lanes / walk routes, draw the projected ones + interrupt / redirect /
## safe / destroyed badges.
func _draw_preview_intent(p: ActionPreview.Preview) -> void:
	var moves: Dictionary = {}
	for d: Dictionary in p.displacements:
		moves[d["id"]] = d["to"]
	var removed: Dictionary = {}
	for h: Dictionary in p.hits:
		if h["lethal"]:
			var u: Unit = state.units.get(h["id"])
			if u != null and not u.is_player():
				removed[h["id"]] = true
	var blockers: Array[Vector2i] = []
	if pending_action == "deploy_shield" and hover_cell != Vector2i(-1, -1):
		blockers.append(hover_cell)
	var changes: Array = Intent.project(state, moves, blockers, removed)
	if changes.is_empty():
		return
	var faded: Dictionary = {}
	for ch: Intent.Change in changes:
		faded[ch.owner_id] = true
	_draw_telegraphs(faded)
	_draw_enemy_move_intents(faded)
	_draw_intent_changes(changes)

## Grapple / Throw: stage 1 highlights grabbable targets, stage 2 highlights
## every valid destination and previews the one under the cursor.
func _draw_two_stage(sel: Unit) -> void:
	var focuses: Array[Vector2i] = ActionPreview.valid_targets(state, sel, pending_action)
	if focus_cell == NO_CELL:
		overlay.set_outline("targets", focuses, TARGET_COL)
		if hover_cell in focuses:
			overlay.set_fill("target_hot", [hover_cell], TARGET_HOT_COL)
			_draw_stage2_dots(sel, hover_cell)
			var pd := ActionPreview.build(state, sel, pending_action, hover_cell)
			if pd.valid:
				_draw_ability_preview(sel, pd)
				_draw_preview_intent(pd)
		return
	# stage 2 — a target is grabbed
	var dim := Color(TARGET_COL.r, TARGET_COL.g, TARGET_COL.b, 0.28)
	overlay.set_outline("targets", focuses, dim)
	overlay.set_outline("grab", [focus_cell], GRAB_COL)
	_draw_stage2_dots(sel, focus_cell)
	if hover_cell in _stage2_cells(sel):
		var p := ActionPreview.build(state, sel, pending_action, focus_cell, {"dest": hover_cell})
		if p.valid:
			overlay.set_fill("dest_hot", [hover_cell], TARGET_HOT_COL)
			_draw_ability_preview(sel, p)
			_draw_preview_intent(p)
		else:
			# offered but unsafe (e.g. it would slam an ally) — flag it, no confirm
			overlay.set_fill("dest_bad", [hover_cell], Color(1.0, 0.2, 0.2, 0.30))
			annot.set_badges("bad", [{"cell": hover_cell, "kind": "interrupt"}])

func _draw_stage2_dots(sel: Unit, focus: Vector2i) -> void:
	if pending_action == "grapple":
		overlay.set_rings("g_dests", MechActions.grapple_dests(state, sel, focus), DEST_COL)
	elif pending_action == "throw":
		var clear_c: Array[Vector2i] = []
		var slam_c: Array[Vector2i] = []
		for e: Dictionary in MechActions.throw_dests(state, sel, focus):
			if e["slam"]:
				slam_c.append(e["cell"])
			else:
				clear_c.append(e["cell"])
		overlay.set_rings("t_dests", clear_c, DEST_COL)
		overlay.set_rings("t_slam", slam_c, SLAM_COL)

func _update_hover_marks() -> void:
	for id: int in unit_views:
		var uv: UnitView = unit_views[id]
		uv.set_hovered(uv.unit != null and uv.unit.pos == hover_cell and id != selected_id)
	if is_instance_valid(reactor_view):
		reactor_view.set_hovered(state.reactor.pos == hover_cell)

func _draw_telegraphs(faded: Dictionary = {}) -> void:
	var i: int = 0
	for tg: Telegraph in state.telegraphs:
		var fade: bool = faded.get(tg.owner_id, false)
		var edge: Color = TELE_FADE if fade else TELE_EDGE
		overlay.set_fill("tele_%d" % i, tg.cells, TELE_FADE if fade else TELE_FILL)
		overlay.set_outline("teleedge_%d" % i, tg.cells, edge)
		if tg.kind == Telegraph.Kind.CHARGE_LINE and not tg.cells.is_empty():
			var owner: Unit = state.units.get(tg.owner_id)
			var start: Vector2i = owner.pos if owner != null else tg.cells[0] - tg.charge_dir
			annot.set_arrow("tele_arrow_%d" % i, [start] + tg.cells, edge, fade)
			# does this charge run itself into a pit? show it before it happens.
			if owner != null and not fade:
				var oc: Dictionary = Intent.charge_outcome(state, owner.pos, tg.charge_dir, {}, [])
				if oc["pit"]:
					overlay.set_fill("tele_pit_%d" % i, [oc["stop"]], Color(1.0, 0.35, 0.35, 0.30))
					annot.set_badges("tele_pit_b_%d" % i, [
						{"cell": owner.pos, "kind": "lethal"}, {"cell": oc["stop"], "kind": "lethal"}])
					annot.set_labels("tele_pit_l_%d" % i, [
						{"cell": oc["stop"] - Vector2i(0, 1), "text": "→ PIT", "color": TELE_EDGE, "big": false}])
		elif tg.kind == Telegraph.Kind.AOE and not tg.cells.is_empty():
			overlay.set_rings("tele_ring_%d" % i, [tg.cells[0]], edge)
		i += 1

func _draw_spawn_telegraphs() -> void:
	var i: int = 0
	var sils: Array = []
	var labels: Array = []
	for sp: Dictionary in state.pending_spawns:
		var cell: Vector2i = sp["cell"]
		var edge: Vector2i = sp["edge_dir"]
		overlay.set_fill("spawn_%d" % i, [cell], SPAWN_FILL)
		overlay.set_outline("spawnedge_%d" % i, [cell], SPAWN_EDGE)
		if edge != Vector2i.ZERO:
			annot.set_arrow("spawn_arrow_%d" % i, [cell - edge, cell, cell + edge], SPAWN_EDGE)
		sils.append({"cell": cell, "unit_kind": sp["kind"]})
		labels.append({"cell": cell - Vector2i(0, 1), "text": "INCOMING", "color": SPAWN_EDGE, "big": false})
		i += 1
	if not sils.is_empty():
		annot.set_silhouettes("spawn_sils", sils)
		annot.set_labels("spawn_lbls", labels)

## Grunt / Interceptor movement intent -- the BOTTOM of the visual hierarchy.
##  - non-hovered: shaft is faint, DESTINATION and TARGET stay readable
##  - hovered enemy: full-strength path + target
##  - affected by the active preview (`faded`): nearly invisible; the projected
##    version is drawn brightly by _draw_intent_changes instead
func _draw_enemy_move_intents(faded: Dictionary = {}) -> void:
	var hov: int = _enemy_under_cursor()
	var i: int = 0
	for u: Unit in state.living_enemies():
		if not EnemyAi.plans_movement(u.kind):
			continue
		if _has_telegraph_owner(u.id):
			continue
		var p: EnemyAi.EnemyPlan = EnemyAi.plan_for(state, u)
		var hovered: bool = u.id == hov
		var dim: bool = faded.get(u.id, false)
		var shaft_a: float = 0.10 if dim else (0.90 if hovered else 0.26)
		var dest_a: float = 0.14 if dim else (1.0 if hovered else 0.55)
		var tgt_a: float = 0.16 if dim else (1.0 if hovered else 0.75)
		if p.path.size() >= 1:
			annot.set_arrow("emi_%d" % i, _plan_arrow(p), Color(1.0, 0.55, 0.55, shaft_a), dim, not hovered)
		overlay.set_outline("emid_%d" % i, [p.dest], Color(1.0, 0.6, 0.6, dest_a))
		if p.will_attack:
			overlay.set_outline("emit_%d" % i, [p.target_cell], Color(1.0, 0.32, 0.32, tgt_a))
		i += 1

func _plan_arrow(p: EnemyAi.EnemyPlan) -> Array:
	var out: Array = [p.from]
	out.append_array(p.path)
	if p.will_attack and (out.is_empty() or out[out.size() - 1] != p.target_cell):
		out.append(p.target_cell)
	return out

func _has_telegraph_owner(owner_id: int) -> bool:
	for tg: Telegraph in state.telegraphs:
		if tg.owner_id == owner_id:
			return true
	return false

func _draw_intent_changes(changes: Array) -> void:
	var ci: int = 0
	for ch: Intent.Change in changes:
		if not ch.projected_path.is_empty():
			var col := Color(1.0, 0.85, 0.25)
			annot.set_arrow("proj_%d" % ci, ch.projected_path, col, false, ch.kind != "charge")
			overlay.set_outline("proj_%d" % ci, [ch.projected_dest] if ch.projected_dest.x >= 0 else ch.projected_path, Color(1.0, 0.85, 0.25, 0.8))
		var badges: Array = []
		var owner: Unit = state.units.get(ch.owner_id)
		if ch.destroyed and owner != null:
			badges.append({"cell": owner.pos, "kind": "lethal"})
			if ch.kind == "charge" and ch.projected_dest.x >= 0:
				badges.append({"cell": ch.projected_dest, "kind": "lethal"})
				annot.set_labels("proj_pit_%d" % ci, [
					{"cell": ch.projected_dest - Vector2i(0, 1), "text": "→ PIT", "color": Color(1.0, 0.85, 0.25), "big": false}])
		elif ch.interrupted and owner != null:
			badges.append({"cell": owner.pos, "kind": "interrupt"})
		if ch.interrupted and ch.safe_cell.x >= 0:
			badges.append({"cell": ch.safe_cell, "kind": "safe"})
		if ch.redirected and ch.newly_threatened_cell.x >= 0:
			badges.append({"cell": ch.newly_threatened_cell, "kind": "collision"})
		if not badges.is_empty():
			annot.set_badges("intent_%d" % ci, badges)
		ci += 1

func _draw_ability_preview(sel: Unit, p: ActionPreview.Preview) -> void:
	if not p.line_cells.is_empty():
		overlay.set_fill("line", p.line_cells, LINE_COL)
	if not p.aoe_cells.is_empty():
		overlay.set_fill("aoe", p.aoe_cells, AOE_COL)
	if not p.explosion_cells.is_empty():
		overlay.set_fill("boom", p.explosion_cells, BOOM_COL)
		overlay.set_outline("boomedge", p.explosion_cells, BOOM_EDGE)
	if p.spear_landing.x >= 0:
		overlay.set_rings("land", [p.spear_landing], LAND_COL)

	# forced movement: an arrow from each moved unit's cell to where it ends up
	var arrow_i: int = 0
	var badges: Array = []
	for d: Dictionary in p.displacements:
		var from: Vector2i = d["from"]
		var to: Vector2i = d["to"]
		if from != to:
			var chain: Array = [from, to]
			if d["id"] == p.mover_id:
				chain = [sel.pos, to]   # grapple-to-anchor: show the mech travelling
			annot.set_arrow("disp_%d" % arrow_i, chain, PUSH_COL)
			arrow_i += 1
		if d["collided"] == "hazard":
			badges.append({"cell": to, "kind": "lethal"})
		elif d["collided"] != "none" and int(d["collision_amount"]) > 0:
			badges.append({"cell": to, "kind": "collision"})
	if not badges.is_empty():
		annot.set_badges("collide", badges)

	# damage numbers + lethal marks, straight on the grid
	var labels: Array = []
	var lethal: Array = []
	for h: Dictionary in p.hits:
		if h["amount"] >= 100:
			labels.append({"cell": h["cell"], "text": "OUT", "color": Color(1, 0.4, 0.35), "big": true})
		else:
			labels.append({"cell": h["cell"], "text": "-%d" % h["amount"], "color": DMG_COL, "big": true})
		if h["lethal"]:
			lethal.append({"cell": h["cell"], "kind": "lethal"})
	if p.hits_reactor:
		overlay.set_outline("ff", [state.reactor.pos], FF_COL)
		labels.append({"cell": state.reactor.pos, "text": "-%d" % p.reactor_damage, "color": DMG_COL, "big": true})
	if not labels.is_empty():
		annot.set_labels("dmg", labels)
	if not lethal.is_empty():
		annot.set_badges("lethal", lethal)

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
		if sel.ap < 1:
			return "%s is out of AP (range shown greyed). Pick another mech or End Turn." % sel.display_name()
		return "%s selected. Click a blue tile to move, or choose an action." % sel.display_name()
	if _two_stage():
		if focus_cell == NO_CELL:
			if pending_action == "grapple":
				return "Grapple — click a gold target (enemy, ally, wall or reactor) to grab it."
			return "Throw — click a unit next to the Grappler to grab it."
		if pending_action == "grapple":
			return "Grabbed. Click a blue tile to set the pull distance. Right-click to re-grab."
		return "Grabbed. Click a blue tile to place, or a red tile to slam. Right-click to re-grab."
	return "Aim %s — click a gold tile. Right-click / Esc to cancel." % MechActions.action_label(pending_action)

# ---------------------------------------------------------------- playback

func _play(events: Array) -> void:
	_busy = true
	if overlay != null:
		overlay.clear_all()
	if annot != null:
		annot.clear_all()
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
		"grapple_pull":
			await _tether(ev["from"], ev["to"])
			var uv: UnitView = unit_views.get(ev["target_id"])
			if uv != null and ev["from"] != ev["to"]:
				await uv.tween_to(ev["to"], 0.14)
		"grapple_self":
			await _tether(ev["from"], ev["to"])
			var uv: UnitView = unit_views.get(ev["id"])
			if uv != null and ev["from"] != ev["to"]:
				await uv.tween_to(ev["to"], 0.14)
		"throw_unit":
			var uv: UnitView = unit_views.get(ev["victim_id"])
			if uv != null and ev["from"] != ev["to"]:
				await uv.tween_to(ev["to"], 0.14)
		"telegraph_new":
			overlay.set_outline("fx", ev["cells"], TELE_EDGE)
			await _wait(0.18)
			overlay.clear_all()
		"spawn_telegraph":
			overlay.set_outline("fx", [ev["cell"]], SPAWN_EDGE)
			overlay.set_fill("fx2", [ev["cell"]], SPAWN_FILL)
			await _wait(0.16)
			overlay.clear_all()
		"telegraph_resolve":
			overlay.set_fill("fx", ev["cells"], Color(1.0, 0.35, 0.20, 0.55))
			await _wait(0.22)
			overlay.clear_all()
		"wall_destroyed":
			grid_view.queue_redraw()
			await _wait(0.05)
		"object_damage":
			for ov: GridObjectView in object_views:
				if is_instance_valid(ov) and ov.obj != null and ov.obj.pos == ev["pos"]:
					ov.flash()
					ov.refresh()
			await _wait(0.08)
		"object_destroyed":
			_despawn_object_at(ev["pos"])
			await _wait(0.05)
		"explosion":
			overlay.set_fill("boom", ev["cells"], BOOM_COL)
			overlay.set_outline("boomedge", ev["cells"], BOOM_EDGE)
			for c: Vector2i in ev["cells"]:
				_floater(c, "BOOM")
			await _wait(0.3)
			overlay.clear_all()
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

func _tether(from: Vector2i, to: Vector2i) -> void:
	var t := Line2D.new()
	t.points = PackedVector2Array([GridView.cell_to_world(from), GridView.cell_to_world(to)])
	t.width = 3.0
	t.default_color = Color(1.0, 0.85, 0.55, 0.9)
	add_child(t)
	await _wait(0.12)
	var tw := create_tween()
	tw.tween_property(t, "modulate:a", 0.0, 0.12)
	await tw.finished
	t.queue_free()

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
