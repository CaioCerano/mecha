class_name UnitView
extends Node2D

## One mech or enemy: a colored shape sized by kind, an HP label, a selection
## ring, and small tween helpers for move / lunge / push / damage / death.

const R: float = GridView.CELL * 0.34

const COLORS: Dictionary = {
	Unit.Kind.SPEAR: Color(0.30, 0.55, 1.00),
	Unit.Kind.SHIELD: Color(0.32, 0.80, 0.42),
	Unit.Kind.ARTILLERY: Color(0.96, 0.84, 0.24),
	Unit.Kind.GRUNT: Color(0.90, 0.30, 0.30),
	Unit.Kind.CHARGER: Color(0.78, 0.18, 0.22),
	Unit.Kind.ARTILLERY_ENEMY: Color(0.95, 0.45, 0.20),
}

var unit: Unit
var selected: bool = false
var _label: Label

func setup(u: Unit) -> void:
	unit = u
	position = GridView.cell_to_world(u.pos)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(-R, -R - 16)
	_label.size = Vector2(R * 2, 16)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	refresh()

func refresh() -> void:
	visible = unit.is_alive()
	_label.text = "%d" % unit.hp
	queue_redraw()

func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()

func _draw() -> void:
	if unit == null:
		return
	var col: Color = COLORS.get(unit.kind, Color.MAGENTA)
	if selected:
		draw_arc(Vector2.ZERO, R + 6.0, 0.0, TAU, 32, Color.WHITE, 3.0, true)

	if unit.is_player():
		draw_circle(Vector2.ZERO, R, col)
		if unit.kind == Unit.Kind.SPEAR and unit.has_spear:
			draw_line(Vector2(-R * 0.2, -R * 1.3), Vector2(R * 0.2, R * 1.3), Color(0.85, 0.9, 1.0), 3.0)
		if unit.kind == Unit.Kind.SHIELD and not unit.shield_deployed:
			draw_arc(Vector2.ZERO, R + 3.0, PI * 0.15, PI * 0.85, 16, Color(0.7, 1.0, 0.8), 3.0)
	else:
		var pts: PackedVector2Array
		if unit.kind == Unit.Kind.CHARGER:
			pts = PackedVector2Array([Vector2(-R, -R), Vector2(R, 0), Vector2(-R, R)])
		else:
			pts = PackedVector2Array([Vector2(0, -R), Vector2(R, R), Vector2(-R, R)])
		draw_colored_polygon(pts, col)

# ---------------------------------------------------------------- animations

func tween_path(path: Array, per_step: float = 0.09) -> void:
	var tw: Tween = create_tween()
	for c: Vector2i in path:
		tw.tween_property(self, "position", GridView.cell_to_world(c), per_step)
	await tw.finished

func tween_to(cell: Vector2i, dur: float = 0.14) -> void:
	var tw: Tween = create_tween()
	tw.tween_property(self, "position", GridView.cell_to_world(cell), dur)
	await tw.finished

func lunge_at(cell: Vector2i) -> void:
	var home: Vector2 = GridView.cell_to_world(unit.pos)
	var toward: Vector2 = GridView.cell_to_world(cell)
	var tw: Tween = create_tween()
	tw.tween_property(self, "position", home.lerp(toward, 0.4), 0.07)
	tw.tween_property(self, "position", home, 0.1)
	await tw.finished

func flash_damage() -> void:
	modulate = Color(1.6, 0.5, 0.5)
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.3)

func die() -> void:
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_property(self, "scale", Vector2(0.3, 0.3), 0.25)
	await tw.finished
	queue_free()
