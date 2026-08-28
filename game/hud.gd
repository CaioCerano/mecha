class_name Hud
extends CanvasLayer

## Minimal UI: turn / phase, reactor HP, a row per mech (HP + AP pips), the
## action buttons for the selected mech, an End Turn button, a hint line, and
## the win/loss banner. Emits intent up to battle.gd; holds no game state.

signal action_chosen(action_id: String)
signal mech_chosen(id: int)
signal end_turn_pressed
signal restart_pressed

var _state: BattleState
var _turn_label: Label
var _hint_label: Label
var _mech_box: VBoxContainer
var _action_box: VBoxContainer
var _end_btn: Button
var _banner: PanelContainer
var _banner_label: Label

func setup(state: BattleState) -> void:
	_state = state
	_build()

func _build() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(590, 16)
	panel.size = Vector2(674, 688)
	add_child(panel)

	var pad := MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(pad)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	pad.add_child(root)

	_turn_label = _mk_label(root, "", 22)
	_hint_label = _mk_label(root, "", 14)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	root.add_child(HSeparator.new())
	_mk_label(root, "SQUAD", 13)
	_mech_box = VBoxContainer.new()
	_mech_box.add_theme_constant_override("separation", 6)
	root.add_child(_mech_box)

	root.add_child(HSeparator.new())
	_mk_label(root, "ACTIONS", 13)
	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 4)
	root.add_child(_action_box)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(spacer)

	_end_btn = Button.new()
	_end_btn.text = "End Turn"
	_end_btn.custom_minimum_size = Vector2(0, 44)
	_end_btn.pressed.connect(func() -> void: end_turn_pressed.emit())
	root.add_child(_end_btn)

	_banner = PanelContainer.new()
	_banner.position = Vector2(150, 290)
	_banner.size = Vector2(420, 140)
	_banner.visible = false
	add_child(_banner)
	var bb := VBoxContainer.new()
	bb.add_theme_constant_override("separation", 12)
	_banner.add_child(bb)
	_banner_label = _mk_label(bb, "", 28)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var restart := Button.new()
	restart.text = "Restart Mission"
	restart.pressed.connect(func() -> void: restart_pressed.emit())
	bb.add_child(restart)

func _mk_label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l

# ---------------------------------------------------------------- refresh

func refresh(selected_id: int, pending_action: String, hint: String) -> void:
	var phase_name: String = ["YOUR TURN", "ENEMY TURN", "VICTORY", "DEFEAT"][_state.phase]
	_turn_label.text = "Turn %d / %d   —   %s" % [
		mini(_state.turn_number, Mission.SURVIVE_TURNS), Mission.SURVIVE_TURNS, phase_name]
	_hint_label.text = hint

	for child: Node in _mech_box.get_children():
		child.queue_free()
	for mech: Unit in _state.player_mechs():
		var row := Button.new()
		row.toggle_mode = true
		row.button_pressed = mech.id == selected_id
		row.disabled = not mech.is_alive()
		var ap_pips: String = "•".repeat(mech.ap) + "◦".repeat(maxi(mech.max_ap - mech.ap, 0))
		if mech.is_alive():
			row.text = "%s    HP %d/%d    AP %s" % [mech.display_name(), mech.hp, mech.max_hp, ap_pips]
		else:
			row.text = "%s    — destroyed —" % mech.display_name()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var id: int = mech.id
		row.pressed.connect(func() -> void: mech_chosen.emit(id))
		_mech_box.add_child(row)

	for child: Node in _action_box.get_children():
		child.queue_free()
	var sel: Unit = _state.units.get(selected_id)
	if sel != null and sel.is_player() and sel.is_alive() and _state.phase == BattleState.Phase.PLAYER:
		var move_btn := Button.new()
		move_btn.text = "Move  (1 AP)" if pending_action != "move" else "▶ Move  (1 AP)"
		move_btn.disabled = sel.ap < 1
		move_btn.pressed.connect(func() -> void: action_chosen.emit("move"))
		_action_box.add_child(move_btn)
		for act: String in MechActions.available_actions(_state, sel):
			var b := Button.new()
			var free: bool = MechActions.is_free(act)
			b.text = "%s  (%s)" % [MechActions.action_label(act), "free" if free else "1 AP"]
			if pending_action == act:
				b.text = "▶ " + b.text
			b.disabled = not free and sel.ap < 1
			var a: String = act
			b.pressed.connect(func() -> void: action_chosen.emit(a))
			_action_box.add_child(b)

	_end_btn.disabled = _state.phase != BattleState.Phase.PLAYER

func show_banner(won: bool) -> void:
	_banner_label.text = "REACTOR HELD" if won else "MISSION FAILED"
	_banner.visible = true
