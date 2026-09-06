class_name Hud
extends CanvasLayer

## Battlefield HUD, laid out like a turn-based tactics game (XCOM / Into the
## Breach): a slim status strip on top, a thin squad rail on the right, a context
## dossier on the left (selected mech, or the enemy / reinforcement under the
## cursor), a card action bar across the bottom, and End Turn bottom-right.
## Holds no game state — battle.gd feeds it everything through refresh().

signal action_chosen(action_id: String)
signal mech_chosen(id: int)
signal end_turn_pressed
signal loadout_pressed
signal restart_pressed
signal mission_selected(id: String)

## Right limit for battlefield rendering (the squad rail starts here). Kept as a
## named constant because the camera framing and a projection test read it.
const PANEL_POS := Vector2(1820, 36)
const PANEL_SIZE := Vector2(96, 1008)

const VIEW := Vector2(1920, 1080)
const TOP_H := 56.0
const RAIL_W := 96.0
## Width of the bottom-left unit panel (stats + build + action cards).
const DOSSIER_W := 486.0

const ACCENT := Color(0.55, 0.80, 1.00)
const WARN := Color(1.00, 0.55, 0.82)
const GOOD := Color(0.55, 0.90, 0.62)
const DIM := Color(1, 1, 1, 0.55)

const FRAME_COL := {
	Unit.Kind.LANCER: Color(0.30, 0.55, 1.00),
	Unit.Kind.BULWARK: Color(0.32, 0.80, 0.42),
	Unit.Kind.GRAPPLER: Color(0.95, 0.62, 0.24),
}
const STATE_COL := {
	Unit.DamageState.NORMAL: Color(0.55, 0.90, 0.62),
	Unit.DamageState.DAMAGED: Color(0.95, 0.80, 0.35),
	Unit.DamageState.CRITICAL: Color(0.98, 0.55, 0.25),
	Unit.DamageState.DISABLED: Color(0.85, 0.30, 0.30),
}

var _state: BattleState

# top strip
var _turn_label: Label
var _phase_label: Label
var _obj_label: Label
var _reactor_bar: _Bar
var _reactor_num: Label
var _opt_label: Label
var _inbound_label: Label

var _rail: VBoxContainer
## Bottom-left panel: the selected unit's stats + build (with effect text). Also
## shows a hovered enemy's / reinforcement's intent.
var _unit_panel: PanelContainer
var _unit_body: VBoxContainer
## Bottom-centre tray: the selected unit's action cards.
var _action_tray: PanelContainer
var _action_bar: HBoxContainer
var _hint_label: Label
var _end_btn: Button
var _end_sub: Label
var _mission_pick: OptionButton

var _banner: PanelContainer
var _banner_label: Label
var _banner_summary: Label

var _card_normal: StyleBoxFlat
var _card_active: StyleBoxFlat
var _card_dim: StyleBoxFlat

func setup(state: BattleState) -> void:
	_state = state
	_card_normal = _box(Color(0.14, 0.16, 0.20), Color(0.30, 0.33, 0.40), 1)
	_card_active = _box(Color(0.18, 0.28, 0.40), ACCENT, 2)
	_card_dim = _box(Color(0.10, 0.11, 0.13), Color(0.18, 0.19, 0.22), 1)
	_build_top()
	_build_rail()
	_build_unit_panel()
	_build_action_bar()
	_build_controls()
	_build_banner()

# ---------------------------------------------------------------- build

func _panel(pos: Vector2, size: Vector2, bg := Color(0.06, 0.07, 0.10, 0.92)) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	p.size = size
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = Color(1, 1, 1, 0.09)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	for m: String in ["left", "right", "top", "bottom"]:
		s.set("content_margin_" + m, 12)
	p.add_theme_stylebox_override("panel", s)
	add_child(p)
	return p

func _build_top() -> void:
	var bar := _panel(Vector2.ZERO, Vector2(VIEW.x, TOP_H), Color(0.05, 0.06, 0.09, 0.95))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	bar.add_child(row)

	_turn_label = _mk(row, "", 20)
	_phase_label = _mk(row, "", 14)
	_phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_vsep())

	_obj_label = _mk(row, "", 13)
	_obj_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_vsep())

	_mk(row, "REACTOR", 11).modulate = DIM
	_reactor_bar = _Bar.new()
	_reactor_bar.custom_minimum_size = Vector2(170, 16)
	_reactor_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_reactor_bar)
	_reactor_num = _mk(row, "", 12)
	_reactor_num.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	_opt_label = _mk(row, "", 12)
	_opt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grow)

	_inbound_label = _mk(row, "", 13)
	_inbound_label.add_theme_color_override("font_color", WARN)
	_inbound_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# dev mission picker, tucked at the far right
	_mission_pick = OptionButton.new()
	_mission_pick.flat = true
	for id: String in Mission.ids():
		_mission_pick.add_item(Mission.display_name(id))
	_mission_pick.select(Mission.ids().find(_state.data.id))
	_mission_pick.item_selected.connect(func(i: int) -> void: mission_selected.emit(Mission.ids()[i]))
	row.add_child(_mission_pick)

func _build_rail() -> void:
	var p := _panel(Vector2(VIEW.x - RAIL_W - 12, TOP_H + 14), Vector2(RAIL_W, 4))
	p.size_flags_vertical = 0
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 8)
	p.add_child(_rail)

func _build_unit_panel() -> void:
	_unit_panel = _panel(Vector2.ZERO, Vector2(DOSSIER_W, 4))
	# pin to the bottom-left corner; auto-height grows the panel upward
	_unit_panel.anchor_left = 0.0
	_unit_panel.anchor_right = 0.0
	_unit_panel.anchor_top = 1.0
	_unit_panel.anchor_bottom = 1.0
	_unit_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_unit_panel.offset_left = 24.0
	_unit_panel.offset_right = 24.0 + DOSSIER_W
	_unit_panel.offset_top = -26.0
	_unit_panel.offset_bottom = -26.0
	_unit_body = VBoxContainer.new()
	_unit_body.add_theme_constant_override("separation", 6)
	_unit_body.custom_minimum_size.x = DOSSIER_W - 24
	_unit_panel.add_child(_unit_body)

## Selected unit's action cards, floating centred just above the bottom edge.
func _build_action_bar() -> void:
	_action_tray = PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.10, 0.92)
	s.border_color = Color(1, 1, 1, 0.09)
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	for m: String in ["left", "right", "top", "bottom"]:
		s.set("content_margin_" + m, 10)
	_action_tray.add_theme_stylebox_override("panel", s)
	add_child(_action_tray)
	# centred on x, pinned above the bottom edge, auto-sized both ways
	_action_tray.anchor_left = 0.5
	_action_tray.anchor_right = 0.5
	_action_tray.anchor_top = 1.0
	_action_tray.anchor_bottom = 1.0
	_action_tray.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_action_tray.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_action_tray.offset_left = 0.0
	_action_tray.offset_right = 0.0
	_action_tray.offset_top = -50.0
	_action_tray.offset_bottom = -50.0
	_action_bar = HBoxContainer.new()
	_action_bar.add_theme_constant_override("separation", 8)
	_action_tray.add_child(_action_bar)

## A viewport-width-centred label pinned N px above the bottom edge.
func _bottom_label(size: int, col: Color, off_top: float, off_bottom: float, half_w: float) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.modulate = col
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.anchor_top = 1.0
	l.anchor_bottom = 1.0
	l.offset_left = -half_w
	l.offset_right = half_w
	l.offset_top = off_top
	l.offset_bottom = off_bottom
	return l

func _build_controls() -> void:
	_hint_label = _bottom_label(12, Color(1, 1, 1, 0.82), -46.0, -28.0, 700.0)

	var cam := _bottom_label(11, Color(1, 1, 1, 0.32), -26.0, -8.0, 400.0)
	cam.text = "scroll — zoom   ·   middle-drag — pan   ·   Home — recentre"

	# bottom-right: End Turn + nav
	var br := _panel(Vector2(VIEW.x - 300, VIEW.y - 132), Vector2(284, 116))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	br.add_child(col)
	_end_btn = Button.new()
	_end_btn.custom_minimum_size = Vector2(0, 46)
	_end_btn.add_theme_font_size_override("font_size", 17)
	_end_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	col.add_child(_end_btn)
	_end_sub = _mk(col, "", 11)
	_end_sub.modulate = DIM
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	col.add_child(nav)
	for title: String in ["Restart", "Loadout"]:
		var b := Button.new()
		b.text = title
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nav.add_child(b)
		if title == "Restart":
			b.pressed.connect(func() -> void: restart_pressed.emit())
		else:
			b.pressed.connect(func() -> void: loadout_pressed.emit())

func _build_banner() -> void:
	_banner = PanelContainer.new()
	_banner.position = Vector2((VIEW.x - 520) * 0.5, 360)
	_banner.size = Vector2(520, 210)
	_banner.visible = false
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.06, 0.07, 0.10, 0.97)
	s.border_color = ACCENT
	s.set_border_width_all(2)
	s.set_corner_radius_all(8)
	for m: String in ["left", "right", "top", "bottom"]:
		s.set("content_margin_" + m, 20)
	_banner.add_theme_stylebox_override("panel", s)
	add_child(_banner)
	var bb := VBoxContainer.new()
	bb.add_theme_constant_override("separation", 10)
	_banner.add_child(bb)
	_banner_label = _mk(bb, "", 30)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_summary = _mk(bb, "", 13)
	_banner_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_summary.modulate = Color(1, 1, 1, 0.8)
	var r := Button.new()
	r.text = "Restart Mission"
	r.custom_minimum_size = Vector2(0, 38)
	r.pressed.connect(func() -> void: restart_pressed.emit())
	bb.add_child(r)
	var b := Button.new()
	b.text = "Return to Loadout"
	b.pressed.connect(func() -> void: loadout_pressed.emit())
	bb.add_child(b)

# ---------------------------------------------------------------- refresh

func refresh(selected_id: int, pending_action: String, hint: String,
		inspect_id: int, inspect_spawn: Dictionary = {}) -> void:
	var d: MissionData = _state.data
	var phase_names := ["PLAYER PHASE", "ENEMY PHASE", "VICTORY", "DEFEAT"]
	var phase_cols := [ACCENT, WARN, GOOD, Color(0.95, 0.5, 0.45)]
	_turn_label.text = "TURN %d / %d" % [mini(_state.turn_number, d.turn_limit), d.turn_limit]
	_phase_label.text = phase_names[_state.phase]
	_phase_label.add_theme_color_override("font_color", phase_cols[_state.phase])
	_obj_label.text = d.objective_primary
	_reactor_bar.set_values(_state.reactor.hp, _state.reactor.max_hp, Color(0.62, 0.40, 0.90))
	_reactor_num.text = "%d/%d" % [maxi(_state.reactor.hp, 0), _state.reactor.max_hp]
	if d.objective_optional != "":
		var ok: bool = _state.optional_objective_met()
		_opt_label.text = ("✓ " if ok else "✗ ") + d.objective_optional
		_opt_label.add_theme_color_override("font_color", GOOD if ok else Color(0.95, 0.55, 0.5))
		_opt_label.visible = true
	else:
		_opt_label.visible = false
	_inbound_label.text = _inbound_summary()
	_inbound_label.visible = _inbound_label.text != ""

	_rebuild_rail(selected_id)
	_rebuild_unit_panel(selected_id, pending_action, inspect_id, inspect_spawn)
	_rebuild_actions(selected_id, pending_action)
	_refresh_end_turn()
	_hint_label.text = hint

func _refresh_end_turn() -> void:
	var playing := _state.phase == BattleState.Phase.PLAYER
	_end_btn.disabled = not playing
	var unspent := 0
	for m: Unit in _state.player_mechs():
		if m.is_alive() and m.ap > 0:
			unspent += 1
	if not playing:
		_end_btn.text = "END TURN"
		_end_sub.text = ""
	elif unspent > 0:
		_end_btn.text = "END TURN  ↵"
		_end_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
		_end_sub.text = "%d mech still has AP" % unspent if unspent == 1 else "%d mechs still have AP" % unspent
	else:
		_end_btn.text = "END TURN  ✓"
		_end_btn.add_theme_color_override("font_color", GOOD)
		_end_sub.text = "all mechs spent"

# --- squad rail --------------------------------------------------

func _rebuild_rail(selected_id: int) -> void:
	for c: Node in _rail.get_children():
		c.queue_free()
	for mech: Unit in _state.player_mechs():
		_rail.add_child(_squad_tile(mech, mech.id == selected_id))

func _squad_tile(mech: Unit, selected: bool) -> Control:
	var col: Color = FRAME_COL.get(mech.kind, Color.GRAY)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(RAIL_W - 24, 74)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var alive := mech.is_alive()
	var border: Color = Color.WHITE if selected else (col if alive else Color(0.4, 0.4, 0.45))
	var s := _box(Color(col.r, col.g, col.b, 0.16 if alive else 0.06), border, 2 if selected else 1)
	card.add_theme_stylebox_override("panel", s)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	card.add_child(box)
	var name_l := _mk(box, mech.display_name().substr(0, 3).to_upper(), 13)
	name_l.add_theme_color_override("font_color", col if alive else Color(0.6, 0.6, 0.65))
	if not alive:
		_mk(box, "DOWN", 10).add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	else:
		var hp := _Bar.new()
		hp.custom_minimum_size = Vector2(0, 9)
		hp.set_values(mech.hp, mech.max_hp, Color(0.35, 0.80, 0.40))
		box.add_child(hp)
		var s2 := mech.damage_state()
		if s2 != Unit.DamageState.NORMAL:
			_mk(box, mech.damage_label(), 9).add_theme_color_override("font_color", STATE_COL.get(s2, Color.WHITE))
		_mk(box, "◆".repeat(mech.ap) + "◇".repeat(maxi(mech.max_ap - mech.ap, 0)), 12) \
			.add_theme_color_override("font_color", ACCENT)
	_ignore_mouse(box)
	if alive:
		var id := mech.id
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				mech_chosen.emit(id))
	return card

# --- unit panel (bottom-left): stats + build + actions -------

func _rebuild_unit_panel(selected_id: int, pending_action: String, inspect_id: int, inspect_spawn: Dictionary) -> void:
	for c: Node in _unit_body.get_children():
		c.queue_free()
	var sel: Unit = _state.units.get(selected_id)
	var enemy: Unit = _state.units.get(inspect_id)
	if not inspect_spawn.is_empty():
		_head("INCOMING  ·  " + _kind_name(inspect_spawn["kind"]).to_upper(), WARN)
		_build_spawn_detail(inspect_spawn)
	elif enemy != null and not enemy.is_player() and enemy.is_alive():
		_head("ENEMY  ·  " + enemy.display_name().to_upper(), Color(0.95, 0.5, 0.45))
		_enemy_block(enemy)
	elif sel != null and sel.is_player() and sel.is_alive() and _state.phase == BattleState.Phase.PLAYER:
		_head(sel.display_name().to_upper(), FRAME_COL.get(sel.kind, Color.WHITE))
		_mech_block(sel)
	else:
		_head("NO SELECTION", DIM)
		_mk(_unit_body, "Click a mech or its rail tile. Hover an enemy or ◤ marker to read its intent.", 12).modulate = Color(1, 1, 1, 0.5)

func _head(text: String, col: Color) -> void:
	var l := _mk(_unit_body, text, 15)
	l.add_theme_color_override("font_color", col)
	_unit_body.add_child(HSeparator.new())

func _mech_block(sel: Unit) -> void:
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", 6)
	_unit_body.add_child(chips)
	_chip(chips, SquadLoadout.category(sel.kind), ACCENT)
	var st := sel.damage_state()
	_chip(chips, sel.damage_label(), STATE_COL.get(st, Color.WHITE))

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	_unit_body.add_child(hp_row)
	var hp := _Bar.new()
	hp.custom_minimum_size = Vector2(180, 18)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp.set_values(sel.hp, sel.max_hp, Color(0.35, 0.80, 0.40))
	hp_row.add_child(hp)
	_mk(hp_row, "HP %d/%d" % [sel.hp, sel.max_hp], 13)

	var stat_row := HBoxContainer.new()
	stat_row.add_theme_constant_override("separation", 16)
	_unit_body.add_child(stat_row)
	_mk(stat_row, "AP " + "◆".repeat(sel.ap) + "◇".repeat(maxi(sel.max_ap - sel.ap, 0)) + " %d/%d" % [sel.ap, sel.max_ap], 15) \
		.add_theme_color_override("font_color", ACCENT)
	_mk(stat_row, "MOVE %d" % sel.movement(), 15)

	_mk(_unit_body, _cat_note(sel.kind), 11).modulate = Color(1, 1, 1, 0.6)

	var status := _status_chips(sel)
	if not status.is_empty():
		var wrap := HFlowContainer.new()
		wrap.add_theme_constant_override("h_separation", 6)
		wrap.add_theme_constant_override("v_separation", 4)
		_unit_body.add_child(wrap)
		for pair: Array in status:
			_chip(wrap, pair[0], pair[1])

	_unit_body.add_child(HSeparator.new())
	_loadout_row("PRIMARY", MechActions.action_label(SquadLoadout.primary(sel.kind)),
		SquadLoadout.DESCRIPTIONS.get(SquadLoadout.primary(sel.kind), ""), Color(1, 1, 1, 0.92), false)
	_loadout_row("SECONDARY", SquadLoadout.label(sel.secondary()),
		SquadLoadout.DESCRIPTIONS.get(sel.secondary(), ""), ACCENT, false)
	for slot: int in 2:
		var sid: String = sel.systems[slot]
		var impaired := slot == sel.impaired_slot
		_loadout_row("SYSTEM %d" % (slot + 1), SquadLoadout.label(sid),
			SquadLoadout.DESCRIPTIONS.get(sid, ""),
			Color(0.95, 0.45, 0.40) if impaired else GOOD, impaired)
	_loadout_row("PILOT", SquadLoadout.label(sel.pilot_id),
		SquadLoadout.DESCRIPTIONS.get(sel.pilot_id, ""), Color(0.82, 0.68, 1.0), false)

func _cat_note(kind: int) -> String:
	match SquadLoadout.category(kind):
		"HEAVY": return "HEAVY — shrugs off 1 tile of incoming enemy force"
		"LIGHT": return "LIGHT — identity is mobility; no systemic modifier"
	return "MEDIUM — neutral baseline"

## key + equipped name (+ IMPAIRED tag) + wrapped effect text. Empty slots
## collapse to one dim line.
func _loadout_row(key: String, item: String, desc: String, name_col: Color, impaired: bool) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	_unit_body.add_child(row)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	row.add_child(head)
	var k := _mk(head, key, 10)
	k.custom_minimum_size.x = 74
	k.modulate = DIM
	if item == "None":
		_mk(head, "— empty —", 12).modulate = Color(1, 1, 1, 0.38)
		return
	_mk(head, item, 13).add_theme_color_override("font_color", name_col)
	if impaired:
		_mk(head, "IMPAIRED", 10).add_theme_color_override("font_color", Color(0.95, 0.40, 0.40))
	if desc != "":
		var d := _mk(row, desc, 11)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size.x = DOSSIER_W - 44
		d.modulate = Color(1, 1, 1, 0.4 if impaired else 0.72)

func _status_chips(sel: Unit) -> Array:
	var out: Array = []
	if sel.push_bonus() > 0: out.append(["PUSH +%d" % sel.push_bonus(), GOOD])
	if sel.braced: out.append(["BRACED", ACCENT])
	if sel.has_system("vector_thrusters"): out.append(["THRUSTERS " + ("USED" if sel.thrusters_used else "READY"), DIM if sel.thrusters_used else GOOD])
	if sel.has_system("emergency_winch"): out.append(["WINCH " + ("USED" if sel.winch_used else "READY"), DIM if sel.winch_used else GOOD])
	if sel.has_system("targeting_suite"): out.append(["TARGETING SUITE", ACCENT])
	if sel.pilot_id == "ace": out.append(["ACE %d/3 · %s" % [sel.moved_this_turn, "USED" if sel.ace_used else "READY"], DIM if sel.ace_used else GOOD])
	if sel.pilot_id == "brawler": out.append(["BRAWLER " + ("USED" if sel.brawler_used else "READY"), DIM if sel.brawler_used else GOOD])
	if sel.pilot_id == "rescuer": out.append(["RESCUER " + ("USED" if sel.rescuer_used else "READY"), DIM if sel.rescuer_used else GOOD])
	if sel.pilot_id == "engineer": out.append(["ENGINEER " + ("USED" if sel.engineer_used else "READY"), DIM if sel.engineer_used else GOOD])
	return out

func _enemy_block(enemy: Unit) -> void:
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 10)
	_unit_body.add_child(hp_row)
	var hp := _Bar.new()
	hp.custom_minimum_size = Vector2(190, 18)
	hp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp.set_values(enemy.hp, enemy.max_hp, Color(0.85, 0.35, 0.30))
	hp_row.add_child(hp)
	_mk(hp_row, "HP %d/%d" % [enemy.hp, enemy.max_hp], 13)
	_mk(_unit_body, "NEXT ACTION", 11).modulate = DIM
	for line: String in _enemy_intent_lines(enemy):
		_mk(_unit_body, line, 13)

func _chip(parent: Node, text: String, col: Color) -> void:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(col.r, col.g, col.b, 0.16)
	s.border_color = Color(col.r, col.g, col.b, 0.7)
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 7
	s.content_margin_right = 7
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	parent.add_child(p)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", col.lightened(0.3))
	p.add_child(l)

# --- action cards (bottom-centre tray) ---------------------

func _rebuild_actions(selected_id: int, pending_action: String) -> void:
	for c: Node in _action_bar.get_children():
		c.queue_free()
	var sel: Unit = _state.units.get(selected_id)
	var live := sel != null and sel.is_player() and sel.is_alive() and _state.phase == BattleState.Phase.PLAYER
	_action_tray.visible = live
	if not live:
		return
	_action_card(_action_bar, "move", "MOVE", "M", "1 AP",
		"Up to %d tiles" % sel.movement(), pending_action, sel.ap >= 1)
	var idx := 1
	for act: String in MechActions.available_actions(_state, sel):
		var free: bool = MechActions.is_free(act)
		_action_card(_action_bar, act, MechActions.action_label(act).to_upper(), str(idx),
			"FREE" if free else "1 AP", _ability_stat_line(act),
			pending_action, free or sel.ap >= 1)
		idx += 1

func _action_card(parent: Node, act: String, title: String, hotkey: String, cost: String,
		stat_line: String, pending_action: String, enabled: bool) -> void:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(158, 0)
	card.add_theme_stylebox_override("panel",
		_card_active if pending_action == act else (_card_normal if enabled else _card_dim))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	card.add_child(col)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 5)
	col.add_child(r1)
	_mk(r1, "[%s]" % hotkey, 12).add_theme_color_override("font_color", ACCENT if enabled else Color(1, 1, 1, 0.3))
	_mk(r1, title, 13)
	var grow := Control.new()
	grow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(grow)
	_mk(r1, cost, 10).add_theme_color_override("font_color", GOOD if cost == "FREE" else Color(1, 0.88, 0.5))
	if stat_line != "":
		var st := _mk(col, stat_line, 10)
		st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		st.modulate = Color(1, 1, 1, 0.78)
	if not enabled:
		card.modulate = Color(1, 1, 1, 0.5)
	parent.add_child(card)
	_ignore_mouse(col)
	var a := act
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			action_chosen.emit(a))

# --- reused detail text --------------------------------------

func _ability_stat_line(act: String) -> String:
	match act:
		"brace": return "Self · immune to enemy force until next turn"
		"anchor_shot": return "Empty cardinal tile, range 3 · blocks forced moves"
		"tow_cable": return "Allied mech in cardinal range 3 · safe pull 1–2"
		"emergency_winch": return "Adjacent allied mech → safe tile 1 away · once/mission"
		"engineer_repair": return "Repair impaired system, else heal one step · once/mission"
	var parts: Array[String] = []
	var rng := MechActions.action_range(act)
	if rng == 1:
		parts.append("Melee")
	elif rng > 1:
		parts.append("Range %d" % rng)
	var dmg := MechActions.action_damage(act)
	if dmg > 0:
		parts.append("Dmg %d" % dmg)
	var c := MechActions.action_collision(act)
	if c > 0:
		parts.append("Slam %d" % c)
	var push := MechActions.action_push(act)
	if push > 0:
		parts.append("Push %d" % push)
	elif push == -1:
		parts.append("Reel")
	return "  ·  ".join(parts)

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
	return "◤ INBOUND:  " + " · ".join(parts)

func _build_spawn_detail(sp: Dictionary) -> void:
	var cell := Vector2i(sp["cell"])
	_mk(_unit_body, "Enters at column %d, row %d" % [cell.x, cell.y], 13)
	var dir: Vector2i = sp["edge_dir"]
	var compass := {Vector2i(1, 0): "west edge, heading east", Vector2i(-1, 0): "east edge, heading west",
		Vector2i(0, 1): "north edge, heading south", Vector2i(0, -1): "south edge, heading north"}
	if compass.has(dir):
		_mk(_unit_body, "From the " + compass[dir], 13).modulate = Color(1, 1, 1, 0.8)
	_mk(_unit_body, "Arrives: end of the next enemy phase", 13).modulate = Color(1, 1, 1, 0.8)
	_mk(_unit_body, "THEN, the phase after:", 11).modulate = DIM
	for line: String in _spawn_first_action_lines(sp["kind"]):
		_mk(_unit_body, line, 13)
	_mk(_unit_body, "Reposition now — you have a full turn before it acts.", 12).modulate = Color(1, 0.8, 0.5)

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
		lines.append("%s   →  column %d, row %d" % [verb, p.dest.x, p.dest.y])
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
	_banner_label.add_theme_color_override("font_color", GOOD if won else Color(0.95, 0.5, 0.45))
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

# ---------------------------------------------------------------- widgets

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

func _mk(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

func _vsep() -> VSeparator:
	var v := VSeparator.new()
	return v

func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c: Node in n.get_children():
		_ignore_mouse(c)

# ---------------------------------------------------------------- mini bar

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

static func build_summary(unit: Unit) -> String:
	var systems: Array[String] = []
	for slot: int in 2:
		var label := SquadLoadout.label(unit.systems[slot])
		if slot == unit.impaired_slot:
			label += " [IMPAIRED]"
		systems.append(label)
	var status: Array[String] = []
	if unit.push_bonus() > 0: status.append("Push / max distance +%d" % unit.push_bonus())
	if unit.braced: status.append("BRACED")
	if unit.has_system("vector_thrusters"): status.append("Thrusters " + ("used" if unit.thrusters_used else "ready"))
	if unit.has_system("emergency_winch"): status.append("Winch " + ("used" if unit.winch_used else "ready"))
	if unit.pilot_id == "ace": status.append("Ace %d/3 moved / %s" % [unit.moved_this_turn, "used" if unit.ace_used else "ready"])
	if unit.pilot_id == "brawler": status.append("Brawler " + ("used" if unit.brawler_used else "ready"))
	if unit.pilot_id == "rescuer": status.append("Rescuer " + ("used" if unit.rescuer_used else "ready"))
	if unit.pilot_id == "engineer": status.append("Engineer " + ("used" if unit.engineer_used else "ready"))
	return "%s / %s / %s\n%s / %s\nPilot: %s  %s" % [SquadLoadout.category(unit.kind), unit.damage_label(), SquadLoadout.label(unit.secondary()), systems[0], systems[1], SquadLoadout.label(unit.pilot_id), " / ".join(status)]
