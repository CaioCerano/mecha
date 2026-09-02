class_name Hud
extends CanvasLayer

## Sidebar. Priority order, top to bottom: mission status, selected-mech state
## (HP + AP + abilities) OR hovered-enemy intent, then the End Turn button.
## Holds no game state — battle.gd hands it everything through refresh().

signal action_chosen(action_id: String)
signal mech_chosen(id: int)
signal end_turn_pressed
signal restart_pressed
signal mission_selected(id: String)

const PANEL_POS := Vector2(836, 36)
const PANEL_SIZE := Vector2(408, 828)

var _state: BattleState
var _phase_label: Label
var _turn_label: Label
var _obj_main: Label
var _obj_opt: Label
var _reactor_bar: _Bar
var _inbound_label: Label
var _hint_label: Label
var _mech_box: VBoxContainer
var _panel_title: Label
var _detail_box: VBoxContainer
var _end_btn: Button
var _mission_pick: OptionButton
var _banner: PanelContainer
var _banner_label: Label
var _banner_summary: Label

var _card_normal: StyleBoxFlat
var _card_active: StyleBoxFlat
var _card_dim: StyleBoxFlat

func setup(state: BattleState) -> void:
	_state = state
	_make_styleboxes()
	_build()

# ----------------------------------------------------------------- build

func _make_styleboxes() -> void:
	_card_normal = _box(Color(0.15, 0.16, 0.19), Color(0.30, 0.31, 0.36), 1)
	_card_active = _box(Color(0.19, 0.24, 0.33), Color(0.55, 0.80, 1.00), 2)
	_card_dim = _box(Color(0.12, 0.12, 0.14), Color(0.20, 0.20, 0.23), 1)

func _box(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(4)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = PANEL_POS
	panel.size = PANEL_SIZE
	add_child(panel)

	var pad := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(pad)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	pad.add_child(root)

	# --- dev mission picker (not a campaign -- just switch the hand-built slice) --
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	root.add_child(mrow)
	_mk_label(mrow, "MISSION", 11).modulate = Color(1, 1, 1, 0.55)
	_mission_pick = OptionButton.new()
	_mission_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sel_idx := 0
	for i: int in Mission.catalog().size():
		var entry: Dictionary = Mission.catalog()[i]
		_mission_pick.add_item(entry["name"], i)
		if entry["id"] == _state.data.id:
			sel_idx = i
	_mission_pick.select(sel_idx)
	_mission_pick.item_selected.connect(func(idx: int) -> void:
		mission_selected.emit(Mission.ids()[idx]))
	mrow.add_child(_mission_pick)

	root.add_child(_hsep())

	# --- mission status -------------------------------------------------
	var head := HBoxContainer.new()
	root.add_child(head)
	_turn_label = _mk_label(head, "", 18)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_phase_label = _mk_label(head, "", 15)

	_mk_label(root, "OBJECTIVE", 11).modulate = Color(1, 1, 1, 0.55)
	_obj_main = _mk_label(root, "", 14)
	_obj_main.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_opt = _mk_label(root, "", 13)
	_obj_opt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_obj_opt.modulate = Color(1, 1, 1, 0.7)

	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 8)
	root.add_child(rr)
	_mk_label(rr, "REACTOR", 11).modulate = Color(1, 1, 1, 0.55)
	_reactor_bar = _Bar.new()
	_reactor_bar.custom_minimum_size = Vector2(150, 14)
	_reactor_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(_reactor_bar)

	_inbound_label = _mk_label(root, "", 13)
	_inbound_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inbound_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.82))

	root.add_child(_hsep())

	# --- squad roster: fixed position, always shown -------------------
	_mk_label(root, "SQUAD", 11).modulate = Color(1, 1, 1, 0.55)
	_mech_box = VBoxContainer.new()
	_mech_box.add_theme_constant_override("separation", 5)
	root.add_child(_mech_box)

	root.add_child(_hsep())

	# --- selected mech / hovered enemy detail ------------------------
	# Below the squad on purpose: it grows and shrinks a lot, and the spacer
	# under it absorbs the change, so the roster above never shifts.
	_panel_title = _mk_label(root, "—", 11)
	_panel_title.modulate = Color(1, 1, 1, 0.55)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 6)
	root.add_child(_detail_box)

	_hint_label = _mk_label(root, "", 12)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.modulate = Color(1, 1, 1, 0.7)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	_end_btn = Button.new()
	_end_btn.text = "End Turn  (⏎)"
	_end_btn.custom_minimum_size = Vector2(0, 42)
	_end_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	root.add_child(_end_btn)

	_banner = PanelContainer.new()
	_banner.position = Vector2(180, 320)
	_banner.size = Vector2(480, 200)
	_banner.visible = false
	add_child(_banner)
	var bb := VBoxContainer.new()
	bb.add_theme_constant_override("separation", 10)
	_banner.add_child(bb)
	_banner_label = _mk_label(bb, "", 28)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_summary = _mk_label(bb, "", 13)
	_banner_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_summary.modulate = Color(1, 1, 1, 0.8)
	var restart := Button.new()
	restart.text = "Restart Mission"
	restart.custom_minimum_size = Vector2(0, 38)
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	bb.add_child(restart)

func _mk_label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func _hsep() -> HSeparator:
	return HSeparator.new()

## Let clicks fall through inner content to the card PanelContainer behind it,
## whose gui_input we listen on.
func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in n.get_children():
		_ignore_mouse(c)

# ----------------------------------------------------------------- refresh

func refresh(selected_id: int, pending_action: String, hint: String,
		inspect_id: int, inspect_spawn: Dictionary = {}) -> void:
	var d: MissionData = _state.data
	var phase_names := ["PLAYER PHASE", "ENEMY PHASE", "VICTORY", "DEFEAT"]
	_phase_label.text = phase_names[_state.phase]
	_turn_label.text = "TURN %d / %d" % [mini(_state.turn_number, d.turn_limit), d.turn_limit]
	_obj_main.text = "PRIMARY   " + d.objective_primary
	_obj_opt.visible = d.objective_optional != ""
	if d.objective_optional != "":
		var ok: bool = _state.optional_objective_met()
		_obj_opt.text = "OPTIONAL   %s   [%s]" % [d.objective_optional, "on track" if ok else "FAILED"]
		_obj_opt.modulate = Color(0.6, 0.9, 0.7) if ok else Color(0.95, 0.55, 0.5)
	_reactor_bar.set_values(_state.reactor.hp, _state.reactor.max_hp, Color(0.62, 0.40, 0.90))
	_inbound_label.text = _inbound_summary()
	_inbound_label.visible = _inbound_label.text != ""
	_hint_label.text = hint
	_end_btn.disabled = _state.phase != BattleState.Phase.PLAYER

	_rebuild_squad(selected_id)

	for c: Node in _detail_box.get_children():
		c.queue_free()
	var sel: Unit = _state.units.get(selected_id)
	var enemy: Unit = _state.units.get(inspect_id)
	if not inspect_spawn.is_empty():
		_panel_title.text = "INCOMING  ·  " + _kind_name(inspect_spawn["kind"]).to_upper()
		_build_spawn_detail(inspect_spawn)
	elif enemy != null and not enemy.is_player() and enemy.is_alive():
		_panel_title.text = "ENEMY  ·  " + enemy.display_name().to_upper()
		_build_enemy_detail(enemy)
	elif sel != null and sel.is_player() and sel.is_alive() and _state.phase == BattleState.Phase.PLAYER:
		_panel_title.text = sel.display_name().to_upper()
		_build_mech_detail(sel, pending_action)
	else:
		_panel_title.text = "—"
		_mk_label(_detail_box, "Select a mech, or hover an enemy / incoming marker.", 12).modulate = Color(1, 1, 1, 0.5)

# --- reinforcements -----------------------------------------------

func _inbound_summary() -> String:
	if _state.pending_spawns.is_empty():
		return ""
	var counts: Dictionary = {}
	for sp: Dictionary in _state.pending_spawns:
		var k: String = _kind_name(sp["kind"])
		counts[k] = counts.get(k, 0) + 1
	var parts: Array[String] = []
	for k: String in counts:
		parts.append("%d× %s" % [counts[k], k] if counts[k] > 1 else k)
	return "◤ INBOUND next enemy phase:  " + ", ".join(parts)

func _build_spawn_detail(sp: Dictionary) -> void:
	var col := Vector2i(sp["cell"]).x
	var row := Vector2i(sp["cell"]).y
	_mk_label(_detail_box, "Enters at column %d, row %d" % [col, row], 13)
	var d: Vector2i = sp["edge_dir"]
	var compass := {Vector2i(1, 0): "west edge, heading east", Vector2i(-1, 0): "east edge, heading west",
		Vector2i(0, 1): "north edge, heading south", Vector2i(0, -1): "south edge, heading north"}
	if compass.has(d):
		_mk_label(_detail_box, "From the " + compass[d], 13).modulate = Color(1, 1, 1, 0.8)
	_mk_label(_detail_box, "Arrives: end of the next enemy phase", 13).modulate = Color(1, 1, 1, 0.8)
	_mk_label(_detail_box, "THEN, the phase after:", 11).modulate = Color(1, 1, 1, 0.55)
	for line: String in _spawn_first_action_lines(sp["kind"]):
		_mk_label(_detail_box, line, 13)
	_mk_label(_detail_box, "Reposition now — you have a full turn before it acts.", 12).modulate = Color(1, 0.8, 0.5)

func _spawn_first_action_lines(kind: int) -> Array:
	match kind:
		Unit.Kind.GRUNT:
			return ["Advances on the reactor  ·  melee Dmg %d" % Mission.GRUNT_MELEE_DMG]
		Unit.Kind.CHARGER:
			return ["Lines up a charge (telegraphed), dashes it the turn after  ·  Dmg %d" % Mission.CHARGER_DMG]
		Unit.Kind.ARTILLERY_ENEMY:
			return ["Moves toward the reactor, then telegraphs a strike  ·  Dmg %d" % Mission.ENEMY_ARTILLERY_DMG]
		Unit.Kind.INTERCEPTOR:
			return ["Hunts your mechs — ignores the reactor  ·  melee Dmg %d" % Mission.INTERCEPTOR_DMG]
	return ["—"]

func _kind_name(kind: int) -> String:
	match kind:
		Unit.Kind.GRUNT: return "Grunt"
		Unit.Kind.CHARGER: return "Charger"
		Unit.Kind.ARTILLERY_ENEMY: return "Enemy Artillery"
		Unit.Kind.INTERCEPTOR: return "Interceptor"
	return "Enemy"

# --- squad ---------------------------------------------------------

func _rebuild_squad(selected_id: int) -> void:
	for child: Node in _mech_box.get_children():
		child.queue_free()
	for mech: Unit in _state.player_mechs():
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",
			_card_active if mech.id == selected_id else (_card_dim if not mech.is_alive() else _card_normal))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		card.add_child(row)

		var name_l := _mk_label(row, mech.display_name(), 14)
		name_l.custom_minimum_size = Vector2(78, 0)
		if not mech.is_alive():
			name_l.text = mech.display_name()
			_mk_label(row, "destroyed", 12).modulate = Color(1, 0.5, 0.5, 0.7)
		else:
			var bar := _Bar.new()
			bar.custom_minimum_size = Vector2(96, 12)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			bar.set_values(mech.hp, mech.max_hp, Color(0.35, 0.80, 0.40))
			row.add_child(bar)
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sp)
			_mk_label(row, _ap_pips(mech), 15).add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))

		_mech_box.add_child(card)
		_ignore_mouse(row)
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		if mech.is_alive():
			var id: int = mech.id
			card.gui_input.connect(func(e: InputEvent) -> void:
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					mech_chosen.emit(id))

func _ap_pips(mech: Unit) -> String:
	return "◆ ".repeat(mech.ap) + "◇ ".repeat(maxi(mech.max_ap - mech.ap, 0)) + " %d/%d" % [mech.ap, mech.max_ap]

# --- selected mech detail ----------------------------------------

func _build_mech_detail(sel: Unit, pending_action: String) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_detail_box.add_child(top)
	var hp := _Bar.new()
	hp.custom_minimum_size = Vector2(150, 16)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp.set_values(sel.hp, sel.max_hp, Color(0.35, 0.80, 0.40))
	top.add_child(hp)
	_mk_label(top, "HP %d/%d" % [sel.hp, sel.max_hp], 13)

	var apl := _mk_label(_detail_box, "AP   " + _ap_pips(sel), 17)
	apl.add_theme_color_override("font_color", Color(0.65, 0.88, 1.0))

	# ability cards: [M] Move, then [1..] abilities
	_ability_card("move", "MOVE", "M", "1 AP",
		"Reposition up to %d tiles" % sel.move_range, [], pending_action, sel.ap >= 1)
	var idx := 1
	for act: String in MechActions.available_actions(_state, sel):
		var free: bool = MechActions.is_free(act)
		_ability_card(act, MechActions.action_label(act).to_upper(), str(idx),
			"FREE" if free else "1 AP", _ability_stat_line(act), MechActions.action_tags(act),
			pending_action, free or sel.ap >= 1)
		idx += 1

func _ability_stat_line(act: String) -> String:
	var parts: Array[String] = []
	var rng := MechActions.action_range(act)
	if rng == 1:
		parts.append("Melee")
	elif rng > 1:
		parts.append("Range %d" % rng)
	var dmg := MechActions.action_damage(act)
	if dmg > 0:
		parts.append("Dmg %d" % dmg)
	var col := MechActions.action_collision(act)
	if col > 0:
		parts.append("Slam %d" % col)
	var push := MechActions.action_push(act)
	if push > 0:
		parts.append("Push %d" % push)
	elif push == -1:
		parts.append("Reel")
	return "  ·  ".join(parts)

func _ability_card(act: String, name: String, hotkey: String, cost: String,
		stat_line: String, tags: Array, pending_action: String, enabled: bool) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",
		_card_active if pending_action == act else (_card_normal if enabled else _card_dim))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	card.add_child(col)

	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 6)
	col.add_child(r1)
	var key := _mk_label(r1, "[%s]" % hotkey, 13)
	key.modulate = Color(0.6, 0.85, 1.0) if enabled else Color(1, 1, 1, 0.35)
	_mk_label(r1, name, 14)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(sp)
	_mk_label(r1, cost, 12).modulate = Color(1, 0.9, 0.5) if cost != "FREE" else Color(0.6, 1.0, 0.7)

	if stat_line != "":
		_mk_label(col, stat_line, 12).modulate = Color(1, 1, 1, 0.85)
	if not tags.is_empty():
		_mk_label(col, " · ".join(tags), 11).modulate = Color(1, 1, 1, 0.5)

	if not enabled:
		card.modulate = Color(1, 1, 1, 0.55)
	_detail_box.add_child(card)
	_ignore_mouse(col)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var a := act
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			action_chosen.emit(a))

# --- enemy intent detail ---------------------------------------

func _build_enemy_detail(enemy: Unit) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	_detail_box.add_child(top)
	var hp := _Bar.new()
	hp.custom_minimum_size = Vector2(150, 16)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp.set_values(enemy.hp, enemy.max_hp, Color(0.85, 0.35, 0.30))
	top.add_child(hp)
	_mk_label(top, "HP %d/%d" % [enemy.hp, enemy.max_hp], 13)

	_mk_label(_detail_box, "NEXT ACTION", 11).modulate = Color(1, 1, 1, 0.55)
	for line: String in _enemy_intent_lines(enemy):
		_mk_label(_detail_box, line, 13)

func _enemy_intent_lines(enemy: Unit) -> Array:
	var tg: Telegraph = null
	for t: Telegraph in _state.telegraphs:
		if t.owner_id == enemy.id:
			tg = t
			break
	if tg != null and tg.kind == Telegraph.Kind.CHARGE_LINE:
		var hit := "open ground"
		if not tg.cells.is_empty():
			var last: Vector2i = tg.cells[tg.cells.size() - 1]
			var u: Unit = _state.unit_at(last)
			if u != null:
				hit = u.display_name()
			elif _state.reactor.pos == last:
				hit = "the reactor"
		return ["Charge  ·  Dmg %d" % tg.damage, "Lane target: %s" % hit,
			"Interrupted if it's pushed off this lane or blocked"]
	if tg != null and tg.kind == Telegraph.Kind.AOE:
		return ["Artillery strike  ·  Dmg %d" % tg.damage, "Area centred on the reactor",
			"Move clear — the blast is locked in"]
	if EnemyAi.plans_movement(enemy.kind):
		var p: EnemyAi.EnemyPlan = EnemyAi.plan_for(_state, enemy)
		var lines: Array = []
		var verb: String = "Advance" if enemy.kind == Unit.Kind.GRUNT else "Pursue"
		if p.will_attack:
			verb += " + Melee"
		var dest: Vector2i = p.dest
		lines.append("%s   →  column %d, row %d" % [verb, dest.x, dest.y])
		if p.will_attack:
			var who: String = "the reactor"
			if p.target_kind == "mech":
				var m: Unit = _state.units.get(p.target_id)
				who = m.display_name() if m != null else "a mech"
			lines.append("Target: %s  ·  Dmg %d" % [who, p.damage])
		elif enemy.kind == Unit.Kind.INTERCEPTOR and p.target_id != -1:
			var m2: Unit = _state.units.get(p.target_id)
			lines.append("Closing on %s" % (m2.display_name() if m2 != null else "a mech"))
		else:
			lines.append("No attack in reach this turn")
		return lines
	match enemy.kind:
		Unit.Kind.CHARGER:
			return ["Line up a charge", "Will telegraph a lane, then dash it next turn"]
		Unit.Kind.ARTILLERY_ENEMY:
			return ["Move into range", "Will telegraph a strike on the reactor"]
	return ["—"]

func show_banner(won: bool) -> void:
	_banner_label.text = "REACTOR HELD" if won else "MISSION FAILED"
	var alive := 0
	for m: Unit in _state.player_mechs():
		if m.is_alive():
			alive += 1
	var opt := ""
	if _state.data.objective_optional != "":
		opt = "  ·  Optional: %s" % ("met" if _state.optional_objective_met() else "failed")
	_banner_summary.text = "Turn %d / %d   ·   Reactor %d / %d   ·   Mechs %d / 3%s" % [
		mini(_state.turn_number, _state.data.turn_limit), _state.data.turn_limit,
		maxi(_state.reactor.hp, 0), _state.reactor.max_hp, alive, opt]
	_banner.visible = true

# ----------------------------------------------------------------- mini bar widget

class _Bar:
	extends Control
	var _cur: int = 0
	var _max: int = 1
	var _col: Color = Color.GREEN

	func set_values(cur: int, mx: int, col: Color) -> void:
		_cur = cur
		_max = maxi(mx, 1)
		_col = col
		queue_redraw()

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(Vector2(1, 1), s - Vector2(2, 2)), Color(0.18, 0.18, 0.22))
		var ratio: float = clampf(float(_cur) / float(_max), 0.0, 1.0)
		var fill := _col
		if ratio <= 0.34:
			fill = Color(0.90, 0.30, 0.25)
		elif ratio <= 0.67:
			fill = fill.lerp(Color(0.95, 0.75, 0.30), 0.6)
		draw_rect(Rect2(Vector2(1, 1), Vector2((s.x - 2) * ratio, s.y - 2)), fill)
		if _max <= 14:
			for k: int in range(1, _max):
				var x: float = 1 + (s.x - 2) * (float(k) / _max)
				draw_line(Vector2(x, 1), Vector2(x, s.y - 1), Color(0, 0, 0, 0.5), 1.0)
		var font := ThemeDB.fallback_font
		var txt := "%d/%d" % [maxi(_cur, 0), _max]
		var tsz := 11
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, tsz).x
		draw_string(font, Vector2((s.x - tw) * 0.5, s.y * 0.5 + tsz * 0.4), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, tsz, Color(1, 1, 1, 0.9))
