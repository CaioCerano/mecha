class_name AnnotationLayer
extends Node2D

## Draws the "what will happen" layer on top of the terrain and cell tints:
## forced-movement arrows, on-grid damage numbers, and small state badges
## (collision / lethal / interrupt / safe). Pure presentation — battle.gd
## feeds it geometry it got from ActionPreview / Intent; it computes nothing.



## name -> { points:PackedVector2Array (world), color:Color, faded:bool, thin:bool }
var _arrows: Dictionary = {}
## name -> Array[{ cell:Vector2i, text:String, color:Color, big:bool }]
var _labels: Dictionary = {}
## name -> Array[{ cell:Vector2i, kind:String }]  kind: collision|lethal|interrupt|safe
var _badges: Dictionary = {}
## name -> Array[{ cell:Vector2i, unit_kind:int }]  faded enemy silhouettes
var _sils: Dictionary = {}

func clear_all() -> void:
	_arrows.clear()
	_labels.clear()
	_badges.clear()
	_sils.clear()
	queue_redraw()

func set_arrow(layer: String, cells: Array, color: Color, faded: bool = false, thin: bool = false) -> void:
	if cells.size() < 2:
		_arrows.erase(layer)
		queue_redraw()
		return
	var pts := PackedVector2Array()
	for c: Vector2i in cells:
		pts.append(GridView.cell_to_world(c))
	_arrows[layer] = {"points": pts, "color": color, "faded": faded, "thin": thin}
	queue_redraw()

func set_labels(layer: String, entries: Array) -> void:
	_labels[layer] = entries
	queue_redraw()

func set_badges(layer: String, entries: Array) -> void:
	_badges[layer] = entries
	queue_redraw()

func set_silhouettes(layer: String, entries: Array) -> void:
	_sils[layer] = entries
	queue_redraw()

# ----------------------------------------------------------------- drawing

func _draw() -> void:
	for name: String in _sils:
		for e: Dictionary in _sils[name]:
			_draw_silhouette(GridView.cell_to_world(e["cell"]), e["unit_kind"])
	for name: String in _arrows:
		var a: Dictionary = _arrows[name]
		_draw_arrow(a["points"], a["color"], a["faded"], a.get("thin", false))
	for name: String in _badges:
		for e: Dictionary in _badges[name]:
			_draw_badge(GridView.cell_to_world(e["cell"]), e["kind"])
	var font := ThemeDB.fallback_font
	for name: String in _labels:
		for e: Dictionary in _labels[name]:
			_draw_label(font, GridView.cell_to_world(e["cell"]) + e.get("offset", Vector2.ZERO), e["text"], e["color"], e.get("big", false))

func _draw_arrow(pts: PackedVector2Array, color: Color, faded: bool, thin: bool = false) -> void:
	var col := color
	if faded:
		col.a *= 0.35
	var w: float = 4.0
	if thin:
		w = 2.0
	elif faded:
		w = 3.0
	for i: int in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, w, true)
	for i: int in range(1, pts.size() - 1):
		draw_circle(pts[i], 3.0 if thin else 4.0, col)
	var tip: Vector2 = pts[pts.size() - 1]
	var dir: Vector2 = (tip - pts[pts.size() - 2]).normalized()
	if dir == Vector2.ZERO:
		return
	var hl: float = 10.0 if thin else 15.0
	var hw: float = 6.0 if thin else 9.0
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * hl + dir.orthogonal() * hw,
		tip - dir * hl - dir.orthogonal() * hw]), col)

func _draw_label(font: Font, center: Vector2, text: String, color: Color, big: bool) -> void:
	var size: int = 20 if big else 16
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var pos: Vector2 = center + Vector2(-w * 0.5, size * 0.5 - 2)
	# cheap outline
	for o: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(font, pos + o * 2.0, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _draw_badge(center: Vector2, kind: String) -> void:
	var at: Vector2 = center + Vector2(GridView.HALF_WIDTH * 0.62, -GridView.HALF_HEIGHT * 0.6)
	var r: float = 11.0
	match kind:
		"collision":
			var c := Color(1.0, 0.55, 0.15)
			for k: int in range(8):
				var ang: float = TAU * k / 8.0
				draw_line(at, at + Vector2(cos(ang), sin(ang)) * (r + 3.0), c, 3.0)
		"lethal":
			draw_circle(at, r, Color(0.85, 0.10, 0.10))
			draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), Color.WHITE, 2.5)
			draw_line(at + Vector2(-5, 5), at + Vector2(5, -5), Color.WHITE, 2.5)
		"interrupt":
			draw_arc(at, r, 0.0, TAU, 20, Color(1.0, 0.85, 0.2), 3.0)
			draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), Color(1.0, 0.85, 0.2), 3.0)
		"safe":
			draw_circle(at, r, Color(0.20, 0.75, 0.35, 0.9))
			draw_line(at + Vector2(-5, 0), at + Vector2(-1, 5), Color.WHITE, 2.5)
			draw_line(at + Vector2(-1, 5), at + Vector2(6, -5), Color.WHITE, 2.5)

## Faded "what's coming" shape, matching UnitView's enemy shapes.
func _draw_silhouette(center: Vector2, unit_kind: int) -> void:
	center.y -= UnitView.R
	var rr: float = UnitView.R
	var col := Color(0.90, 0.30, 0.30, 0.35)
	var pts: PackedVector2Array
	if unit_kind == Unit.Kind.CHARGER:
		pts = PackedVector2Array([center + Vector2(-rr, -rr), center + Vector2(rr, 0), center + Vector2(-rr, rr)])
	elif unit_kind == Unit.Kind.INTERCEPTOR:
		pts = PackedVector2Array([center + Vector2(0, -rr), center + Vector2(rr, 0),
			center + Vector2(0, rr), center + Vector2(-rr, 0)])
	else:
		pts = PackedVector2Array([center + Vector2(0, -rr), center + Vector2(rr, rr), center + Vector2(-rr, rr)])
	draw_colored_polygon(pts, col)
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1.0, 0.5, 0.5, 0.7), 2.0)
