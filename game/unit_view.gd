class_name UnitView
extends Node2D

## One mech or enemy: a colored shape sized by kind, a compact HP bar, AP pips
## (mechs), a selection ring, and small tween helpers for move / lunge / push /
## damage / death. Exact HP is drawn only while the unit is selected or hovered
## — combat should read from the bars, not from numbers.

const R: float = GridView.TILE_HEIGHT * 0.40

const COLORS: Dictionary = {
	Unit.Kind.LANCER: Color(0.30, 0.55, 1.00),
	Unit.Kind.BULWARK: Color(0.32, 0.80, 0.42),
	Unit.Kind.GRAPPLER: Color(0.95, 0.62, 0.24),
	Unit.Kind.GRUNT: Color(0.90, 0.30, 0.30),
	Unit.Kind.CHARGER: Color(0.78, 0.18, 0.22),
	Unit.Kind.ARTILLERY_ENEMY: Color(0.95, 0.45, 0.20),
	Unit.Kind.INTERCEPTOR: Color(0.95, 0.25, 0.55),
}

var unit: Unit
var selected: bool = false
var hovered: bool = false

func setup(u: Unit) -> void:
	unit = u
	position = GridView.cell_to_world(u.pos)
	refresh()

func refresh() -> void:
	visible = unit.is_alive()
	queue_redraw()

func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()

func set_hovered(value: bool) -> void:
	if hovered == value:
		return
	hovered = value
	queue_redraw()

func _process(_delta: float) -> void:
	z_index = GridView.visual_depth(position)

func _draw() -> void:
	if unit == null:
		return
	draw_set_transform(Vector2(0, -R))
	var col: Color = COLORS.get(unit.kind, Color.MAGENTA)

	if selected:
		draw_arc(Vector2.ZERO, R + 7.0, 0.0, TAU, 40, Color.WHITE, 3.0, true)
	elif hovered:
		draw_arc(Vector2.ZERO, R + 7.0, 0.0, TAU, 40, Color(1, 1, 1, 0.4), 2.0, true)

	if unit.is_player():
		draw_circle(Vector2.ZERO, R, col)
		if unit.kind == Unit.Kind.LANCER and unit.has_spear:
			draw_line(Vector2(-R * 0.2, -R * 1.3), Vector2(R * 0.2, R * 1.3), Color(0.85, 0.9, 1.0), 3.0)
		if unit.kind == Unit.Kind.BULWARK and not unit.shield_deployed:
			draw_arc(Vector2.ZERO, R + 3.0, PI * 0.15, PI * 0.85, 16, Color(0.7, 1.0, 0.8), 3.0)
		if unit.kind == Unit.Kind.GRAPPLER:
			draw_arc(Vector2.ZERO, R * 0.55, PI * 0.25, PI * 1.75, 20, Color(1.0, 0.9, 0.75), 3.0)
	else:
		var pts: PackedVector2Array
		if unit.kind == Unit.Kind.CHARGER:
			pts = PackedVector2Array([Vector2(-R, -R), Vector2(R, 0), Vector2(-R, R)])
		elif unit.kind == Unit.Kind.INTERCEPTOR:
			pts = PackedVector2Array([Vector2(0, -R), Vector2(R, 0), Vector2(0, R), Vector2(-R, 0)])
		else:
			pts = PackedVector2Array([Vector2(0, -R), Vector2(R, R), Vector2(-R, R)])
		draw_colored_polygon(pts, col)
		if unit.kind == Unit.Kind.INTERCEPTOR:
			draw_arc(Vector2.ZERO, R * 0.42, 0.0, TAU, 16, Color(1, 1, 1, 0.7), 2.0)

	if unit.braced:
		draw_arc(Vector2.ZERO, R + 4, 0, TAU, 24, Color(0.4, 1, 1), 3)
	_draw_hp_bar()
	if unit.is_player():
		_draw_ap_pips()
	if selected or hovered:
		_draw_hp_number()

func _draw_hp_bar() -> void:
	var w: float = R * 2.0
	var h: float = 5.0
	var top_left := Vector2(-w * 0.5, -R - 13.0)
	var ratio: float = clampf(float(unit.hp) / float(maxi(unit.max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(top_left - Vector2(1, 1), Vector2(w + 2, h + 2)), Color(0, 0, 0, 0.75))
	draw_rect(Rect2(top_left, Vector2(w, h)), Color(0.20, 0.20, 0.24))
	var fill: Color = Color(0.35, 0.80, 0.40) if unit.is_player() else Color(0.85, 0.35, 0.30)
	if ratio <= 0.34:
		fill = Color(0.90, 0.30, 0.25)
	elif ratio <= 0.67 and unit.is_player():
		fill = Color(0.90, 0.75, 0.30)
	draw_rect(Rect2(top_left, Vector2(w * ratio, h)), fill)
	# segment ticks so you can read exact HP at a glance
	if unit.max_hp > 1 and unit.max_hp <= 12:
		for k: int in range(1, unit.max_hp):
			var x: float = top_left.x + w * (float(k) / unit.max_hp)
			draw_line(Vector2(x, top_left.y), Vector2(x, top_left.y + h), Color(0, 0, 0, 0.55), 1.0)

func _draw_ap_pips() -> void:
	var n: int = unit.max_ap
	if n <= 0:
		return
	var gap: float = 12.0
	var start_x: float = -gap * (n - 1) * 0.5
	var y: float = R + 5.0
	for k: int in range(n):
		var c := Vector2(start_x + k * gap, y)
		var filled: bool = k < unit.ap
		var d: float = 4.5
		var diamond := PackedVector2Array([
			c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
		if filled:
			draw_colored_polygon(diamond, Color(0.55, 0.85, 1.0))
		else:
			draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(0.45, 0.5, 0.6), 1.5)

func _draw_hp_number() -> void:
	var font := ThemeDB.fallback_font
	var txt: String = "%d/%d" % [maxi(unit.hp, 0), unit.max_hp]
	var sz: int = 13
	var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var pos := Vector2(-tw * 0.5, -R - 20.0)
	for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(font, pos + o * 1.5, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, 0.9))
	draw_string(font, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color.WHITE)

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
