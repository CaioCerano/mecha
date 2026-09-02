class_name GridObjectView
extends Node2D

## The reactor (purple diamond + compact HP bar), the thrown spear lying on
## the ground, and a deployed shield acting as terrain.

const CELL: int = GridView.CELL

var obj: GridObject
var hovered: bool = false

func setup(o: GridObject) -> void:
	obj = o
	position = GridView.cell_to_world(o.pos)
	refresh()

func refresh() -> void:
	queue_redraw()

func set_hovered(value: bool) -> void:
	if hovered == value:
		return
	hovered = value
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
			_draw_reactor_hp(h)
		GridObject.Kind.THROWN_SPEAR:
			draw_line(Vector2(-h * 0.7, h * 0.5), Vector2(h * 0.7, -h * 0.5), Color(0.75, 0.85, 1.0), 4.0)
			draw_circle(Vector2(h * 0.7, -h * 0.5), 3.0, Color(0.9, 0.95, 1.0))
		GridObject.Kind.DEPLOYED_SHIELD:
			draw_rect(Rect2(Vector2(-h * 0.8, -h * 0.8), Vector2(h * 1.6, h * 1.6)), Color(0.24, 0.62, 0.34))
			draw_arc(Vector2.ZERO, h * 0.55, 0.0, TAU, 20, Color(0.7, 1.0, 0.8), 3.0)
		GridObject.Kind.PIT:
			# an unmistakable hole: black well + hazard-striped rim
			draw_rect(Rect2(Vector2(-h * 0.94, -h * 0.94), Vector2(h * 1.88, h * 1.88)), Color(0.02, 0.02, 0.04))
			draw_circle(Vector2.ZERO, h * 0.62, Color(0.06, 0.06, 0.09))
			for k: int in range(8):
				var a0: float = TAU * k / 8.0
				var a1: float = a0 + TAU / 16.0
				var col: Color = Color(0.85, 0.65, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.1)
				draw_arc(Vector2.ZERO, h * 0.82, a0, a1, 6, col, 4.0)
		GridObject.Kind.EXPLOSIVE:
			# a barrel: read as interactive / destructible
			draw_rect(Rect2(Vector2(-h * 0.52, -h * 0.66), Vector2(h * 1.04, h * 1.32)), Color(0.78, 0.42, 0.14))
			draw_rect(Rect2(Vector2(-h * 0.52, -h * 0.66), Vector2(h * 1.04, h * 1.32)), Color(0.95, 0.75, 0.3), false, 2.0)
			draw_line(Vector2(-h * 0.52, -h * 0.16), Vector2(h * 0.52, -h * 0.16), Color(0.95, 0.75, 0.3), 2.0)
			draw_line(Vector2(-h * 0.52, h * 0.16), Vector2(h * 0.52, h * 0.16), Color(0.95, 0.75, 0.3), 2.0)
			draw_circle(Vector2(0, -h * 0.1), h * 0.16, Color(1.0, 0.35, 0.1))

func _draw_reactor_hp(h: float) -> void:
	var w: float = h * 1.7
	var bh: float = 6.0
	var tl := Vector2(-w * 0.5, -h - 16.0)
	var ratio: float = clampf(float(maxi(obj.hp, 0)) / float(maxi(obj.max_hp, 1)), 0.0, 1.0)
	draw_rect(Rect2(tl - Vector2(1, 1), Vector2(w + 2, bh + 2)), Color(0, 0, 0, 0.8))
	draw_rect(Rect2(tl, Vector2(w, bh)), Color(0.20, 0.20, 0.24))
	var fill := Color(0.62, 0.40, 0.90)
	if ratio <= 0.34:
		fill = Color(0.90, 0.30, 0.25)
	elif ratio <= 0.67:
		fill = Color(0.90, 0.70, 0.35)
	draw_rect(Rect2(tl, Vector2(w * ratio, bh)), fill)
	for k: int in range(1, obj.max_hp):
		var x: float = tl.x + w * (float(k) / obj.max_hp)
		draw_line(Vector2(x, tl.y), Vector2(x, tl.y + bh), Color(0, 0, 0, 0.5), 1.0)
	if hovered:
		var font := ThemeDB.fallback_font
		var txt: String = "%d/%d" % [maxi(obj.hp, 0), obj.max_hp]
		var tw: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, Vector2(-tw * 0.5, tl.y - 5.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
