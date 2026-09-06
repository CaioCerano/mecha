class_name LoadoutScreen
extends Control

## Pre-mission squad customization. One mech fills the screen at a time; the
## roster strip switches between them. Every option lists its full effect inline
## (Into the Breach style) so builds can be compared before committing.

signal deploy_requested

const SLOTS: Array[Dictionary] = [
	{"field": "secondary_id", "slot": -1, "title": "SECONDARY"},
	{"field": "systems", "slot": 0, "title": "SYSTEM 1"},
	{"field": "systems", "slot": 1, "title": "SYSTEM 2"},
	{"field": "pilot_id", "slot": -1, "title": "PILOT"},
]

const ACCENT := Color(0.55, 0.80, 1.00)
const BG := Color(0.075, 0.095, 0.13)
const CARD := Color(0.12, 0.15, 0.20)
const CARD_ON := Color(0.17, 0.26, 0.36)
const CARD_OFF := Color(0.10, 0.11, 0.13)

var loadout: SquadLoadout = SquadLoadout.new()
var mission_id: String = Mission.REACTOR_BREACH
var active_kind: int = Unit.Kind.LANCER

## One entry per slot of the *active* mech. Rebuilt on every roster switch.
## Kept as a flat list (not per-frame) because only one mech shows at a time.
var selectors: Array[Dictionary] = []

var _roster: Dictionary = {}          # kind -> Button
var _config_host: Control             # holds the per-mech column, rebuilt on switch
var _error: Label
var _deploy: Button

func _ready() -> void:
	# Parented under a Node2D (GameFlow), so anchors have no Control rect to
	# resolve against. Track the viewport size explicitly instead.
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	# --- header: title + mission picker -------------------------------
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	_label(header, "SQUAD LOADOUT", 30)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(gap)
	_label(header, "MISSION", 13).modulate = Color(1, 1, 1, 0.55)
	var missions := OptionButton.new()
	missions.custom_minimum_size.x = 320
	for id: String in Mission.ids():
		missions.add_item(Mission.display_name(id))
	missions.select(Mission.ids().find(mission_id))
	missions.item_selected.connect(func(index: int) -> void: mission_id = Mission.ids()[index])
	header.add_child(missions)

	_label(root, "Pick a frame, then tune its secondary, two Systems and a Pilot. Every option shows what it does. Frame, category and primary are fixed.", 14, true).modulate = Color(1, 1, 1, 0.7)

	# --- roster strip ------------------------------------------------
	var roster := HBoxContainer.new()
	roster.add_theme_constant_override("separation", 10)
	root.add_child(roster)
	for kind: int in SquadLoadout.FRAMES:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(220, 44)
		b.add_theme_font_size_override("font_size", 16)
		roster.add_child(b)
		_roster[kind] = b
		b.pressed.connect(func() -> void:
			active_kind = kind
			_rebuild_config())

	root.add_child(HSeparator.new())

	# --- per-mech config (rebuilt on roster switch) -----------------
	_config_host = VBoxContainer.new()
	_config_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_config_host)

	# --- footer: errors + actions ---------------------------------
	root.add_child(HSeparator.new())
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	_error = _label(footer, "", 13, true)
	_error.modulate = Color(1, 0.6, 0.4)
	_error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var baseline := Button.new()
	baseline.text = "Reset to baseline"
	baseline.custom_minimum_size = Vector2(180, 46)
	baseline.pressed.connect(func() -> void:
		loadout.mechs = SquadLoadout.new().mechs
		_rebuild_config())
	footer.add_child(baseline)
	_deploy = Button.new()
	_deploy.text = "DEPLOY"
	_deploy.custom_minimum_size = Vector2(280, 46)
	_deploy.add_theme_font_size_override("font_size", 18)
	_deploy.pressed.connect(_try_deploy)
	footer.add_child(_deploy)

	_rebuild_config()

func _fit_viewport() -> void:
	# Equal anchors so the explicit size below is not overridden by layout.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		_try_deploy()
		get_viewport().set_input_as_handled()

func _try_deploy() -> void:
	if loadout.validation_errors().is_empty():
		deploy_requested.emit()

# ---------------------------------------------------------------- config

func _rebuild_config() -> void:
	for kind: int in SquadLoadout.FRAMES:
		var b: Button = _roster[kind]
		b.text = "%s  ·  %s" % [Unit.new_of(kind).display_name().to_upper(), SquadLoadout.category(kind)]
		b.button_pressed = kind == active_kind
	for child: Node in _config_host.get_children():
		child.queue_free()
	selectors.clear()

	var kind := active_kind
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_config_host.add_child(body)

	body.add_child(_identity_panel(kind))

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 14)
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(slots)
	for spec: Dictionary in SLOTS:
		var field := String(spec["field"])
		var options: Array = SquadLoadout.SECONDARIES[kind] if field == "secondary_id" \
			else (SquadLoadout.SYSTEMS if field == "systems" else SquadLoadout.PILOTS)
		slots.add_child(_slot_column(kind, field, int(spec["slot"]), options, String(spec["title"])))

	_refresh_selectors()

func _identity_panel(kind: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 320
	panel.add_theme_stylebox_override("panel", _stylebox(CARD, Color(0.25, 0.28, 0.34)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var u := Unit.new_of(kind)
	_label(box, u.display_name().to_upper(), 26)
	_label(box, SquadLoadout.category(kind), 15).modulate = ACCENT
	var stats: Dictionary = Mission.unit_stats(kind)
	_label(box, "HP %d      MOVE %d" % [stats.hp, stats.move], 16)
	box.add_child(HSeparator.new())
	_label(box, "CATEGORY", 11).modulate = Color(1, 1, 1, 0.5)
	_label(box, _category_effect(kind), 13, true).modulate = Color(1, 1, 1, 0.85)
	box.add_child(HSeparator.new())
	_label(box, "FIXED PRIMARY", 11).modulate = Color(1, 1, 1, 0.5)
	_label(box, MechActions.action_label(SquadLoadout.primary(kind)), 18)
	var pd: String = SquadLoadout.DESCRIPTIONS.get(SquadLoadout.primary(kind), "")
	if pd != "":
		_label(box, pd, 12, true).modulate = Color(1, 1, 1, 0.75)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	return panel

func _category_effect(kind: int) -> String:
	match SquadLoadout.category(kind):
		"LIGHT": return "No systemic modifier. Identity is its mobility."
		"HEAVY": return "Incoming enemy forced movement −1 tile (min 0). Willing ally moves are exempt."
	return "Neutral baseline."

func _slot_column(kind: int, field: String, slot: int, options: Array, title: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(col, title, 12).modulate = Color(1, 1, 1, 0.55)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var rows: Array[Dictionary] = []
	for id: String in options:
		var card := PanelContainer.new()
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 2)
		card.add_child(inner)
		var name_l := _label(inner, SquadLoadout.label(id), 14)
		var desc_l := _label(inner, SquadLoadout.DESCRIPTIONS.get(id, ""), 11, true)
		desc_l.modulate = Color(1, 1, 1, 0.8)
		var reason_l := _label(inner, "", 11, true)
		reason_l.modulate = Color(1, 0.6, 0.45)
		reason_l.visible = false
		list.add_child(card)
		var chosen := id
		card.gui_input.connect(func(e: InputEvent) -> void:
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_pick(kind, field, slot, chosen))
		rows.append({"id": id, "card": card, "name": name_l, "reason": reason_l})

	selectors.append({
		"kind": kind, "field": field, "slot": slot, "options": options, "rows": rows,
		"selected_id": "", "disabled_ids": [] as Array[String],
	})
	return col

func _pick(kind: int, field: String, slot: int, id: String) -> void:
	if id in _disabled_for(kind, field, slot):
		return
	if slot >= 0:
		loadout.mechs[kind][field][slot] = id
	else:
		loadout.mechs[kind][field] = id
	_refresh_selectors()

## Which option ids can't be taken in this slot right now, with no side effects.
func _disabled_for(kind: int, field: String, slot: int) -> Array[String]:
	var out: Array[String] = []
	if field == "systems":
		var other: String = loadout.mechs[kind].systems[1 - slot]
		if other != "":
			out.append(other)
	elif field == "pilot_id":
		for k: int in SquadLoadout.FRAMES:
			if k != kind and loadout.mechs[k].pilot_id != "":
				out.append(loadout.mechs[k].pilot_id)
	return out

func _refresh_selectors() -> void:
	for entry: Dictionary in selectors:
		var kind := int(entry["kind"])
		var field := String(entry["field"])
		var slot := int(entry["slot"])
		var sel := String(loadout.mechs[kind][field][slot] if slot >= 0 else loadout.mechs[kind][field])
		var disabled: Array[String] = _disabled_for(kind, field, slot)
		entry.selected_id = sel
		entry.disabled_ids = disabled
		for row: Dictionary in entry["rows"]:
			var id := String(row["id"])
			var is_sel: bool = id == sel
			var is_off: bool = id in disabled
			row.card.add_theme_stylebox_override("panel",
				_stylebox(CARD_ON if is_sel else (CARD_OFF if is_off else CARD),
					ACCENT if is_sel else Color(0.22, 0.24, 0.30), 2 if is_sel else 1))
			row.card.modulate = Color(1, 1, 1, 0.5) if is_off else Color(1, 1, 1, 1)
			var taken_by_pilot: bool = String(entry.field) == "pilot_id" and is_off
			row.reason.visible = is_off
			row.reason.text = "Assigned to another mech" if taken_by_pilot else ("Already in the other slot" if is_off else "")
	var errors := loadout.validation_errors()
	_error.text = "  ".join(errors)
	_deploy.disabled = not errors.is_empty()

# ---------------------------------------------------------------- helpers

func _stylebox(bg: Color, border: Color, bw: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(4)
	for m: String in ["left", "right", "top", "bottom"]:
		s.set("content_margin_" + m, 10)
	return s

## wrap defaults off: an autowrapping label next to an expanding sibling in an
## HBox collapses to zero width and prints one glyph per line.
func _label(parent: Node, text: String, size: int, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label
