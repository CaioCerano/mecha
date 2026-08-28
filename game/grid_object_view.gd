class_name GridObjectView
extends Node2D

## The reactor (purple, with an HP label), the thrown spear lying on the
## ground, and a deployed shield acting as terrain.

const CELL: int = GridView.CELL

var obj: GridObject
var _label: Label

func setup(o: GridObject) -> void:
	obj = o
	position = GridView.cell_to_world(o.pos)
	if o.kind == GridObject.Kind.REACTOR:
		_label = Label.new()
		_label.add_theme_font_size_override("font_size", 14)
		_label.add_theme_color_override("font_color", Color.WHITE)
		_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_label.add_theme_constant_override("outline_size", 4)
		_label.position = Vector2(-CELL * 0.5, -CELL * 0.5 - 16)
		_label.size = Vector2(CELL, 16)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_label)
	refresh()

func refresh() -> void:
	if _label != null:
		_label.text = "R %d/%d" % [maxi(obj.hp, 0), obj.max_hp]
	queue_redraw()

func flash() -> void:
	modulate = Color(1.7, 0.6, 0.6)
	var tw: Tween = create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.3)

func _draw() -> void:
	var h: float = CELL * 0.5
	match obj.kind:
		GridObject.Kind.REACTOR:
			var pts := PackedVector2Array([
				Vector2(0, -h * 0.8), Vector2(h * 0.8, 0), Vector2(0, h * 0.8), Vector2(-h * 0.8, 0),
			])
			draw_colored_polygon(pts, Color(0.62, 0.28, 0.85))
			draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.85, 0.6, 1.0), 2.0)
		GridObject.Kind.THROWN_SPEAR:
			draw_line(Vector2(-h * 0.7, h * 0.5), Vector2(h * 0.7, -h * 0.5), Color(0.75, 0.85, 1.0), 4.0)
			draw_circle(Vector2(h * 0.7, -h * 0.5), 3.0, Color(0.9, 0.95, 1.0))
		GridObject.Kind.DEPLOYED_SHIELD:
			draw_rect(Rect2(Vector2(-h * 0.8, -h * 0.8), Vector2(h * 1.6, h * 1.6)), Color(0.24, 0.62, 0.34))
			draw_arc(Vector2.ZERO, h * 0.55, 0.0, TAU, 20, Color(0.7, 1.0, 0.8), 3.0)
