class_name GridView
extends Node2D

## Presentation only. The 32x32 RGBA asset has a 32x16 top face and
## 16 pixels of decorative sides. Pixel stair steps straddle the ideal edge.
const TILE: Texture2D = preload("res://assets/tile.png")
const ART_SCALE: float = 2.0
const TILE_WIDTH: float = 32.0 * ART_SCALE
const TILE_HEIGHT: float = 16.0 * ART_SCALE
const HALF_WIDTH: float = TILE_WIDTH * 0.5
const HALF_HEIGHT: float = TILE_HEIGHT * 0.5
const TEXTURE_ANCHOR := Vector2(16, 8) * ART_SCALE
const ORIGIN := Vector2(424, 220)
const INVALID_CELL := Vector2i(-1, -1)

var _state: BattleState

static func cell_to_world(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2((c.x - c.y) * HALF_WIDTH, (c.x + c.y) * HALF_HEIGHT)

## Half-open logical cells: shared edges belong to the greater coordinate.
## At the outer rim, the last in-board diamond owns its closed boundary.
static func world_to_cell(p: Vector2, size: Vector2i = Vector2i(12, 12)) -> Vector2i:
	var q := p - ORIGIN
	var gx: float = (q.x / HALF_WIDTH + q.y / HALF_HEIGHT) * 0.5
	var gy: float = (q.y / HALF_HEIGHT - q.x / HALF_WIDTH) * 0.5
	if gx < -0.5 or gy < -0.5 or gx > size.x - 0.5 or gy > size.y - 0.5:
		return INVALID_CELL
	return Vector2i(mini(floori(gx + 0.5), size.x - 1), mini(floori(gy + 0.5), size.y - 1))

static func diamond(center: Vector2 = Vector2.ZERO, inset: float = 1.0) -> PackedVector2Array:
	return PackedVector2Array([center + Vector2(0, -HALF_HEIGHT) * inset,
		center + Vector2(HALF_WIDTH, 0) * inset, center + Vector2(0, HALF_HEIGHT) * inset,
		center + Vector2(-HALF_WIDTH, 0) * inset])

static func cell_polygon(c: Vector2i) -> PackedVector2Array:
	return diamond(cell_to_world(c))

static func cell_contains_point(c: Vector2i, p: Vector2) -> bool:
	var q := (p - cell_to_world(c)).abs()
	return q.x / HALF_WIDTH + q.y / HALF_HEIGHT <= 1.0

## Includes decorative sides; these are not selectable surface area.
static func board_visual_bounds(size: Vector2i = Vector2i(12, 12)) -> Rect2:
	return Rect2(ORIGIN + Vector2(-size.y * HALF_WIDTH, -HALF_HEIGHT),
		Vector2((size.x + size.y) * HALF_WIDTH, (size.x + size.y) * HALF_HEIGHT + 16 * ART_SCALE))

static func visual_depth(point: Vector2) -> int:
	return 100 + roundi(point.y * 2.0)

func setup(state: BattleState) -> void:
	_state = state
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for c: Vector2i in state.grid.wall_cells():
		var wall := WallView.new()
		wall.position = cell_to_world(c)
		wall.z_index = visual_depth(wall.position)
		wall.cell = c
		wall.state = state
		add_child(wall)
	queue_redraw()

func _draw() -> void:
	if _state == null:
		return
	# Painter order also prevents the asset's sides covering a nearer top face.
	for depth: int in range(_state.grid.width + _state.grid.height - 1):
		for x: int in range(_state.grid.width):
			var c := Vector2i(x, depth - x)
			if not _state.grid.in_bounds(c):
				continue
			var center := cell_to_world(c)
			draw_texture_rect(TILE, Rect2(center - TEXTURE_ANCHOR, TILE.get_size() * ART_SCALE), false, Color(0.78, 0.78, 0.78))

class WallView extends Node2D:
	var cell: Vector2i
	var state: BattleState

	func _process(_delta: float) -> void:
		visible = state.grid.is_wall(cell)

	func _draw() -> void:
		var base := GridView.diamond(Vector2.ZERO, 0.88)
		var top := GridView.diamond(Vector2(0, -10), 0.88)
		draw_colored_polygon(PackedVector2Array([top[1], top[2], top[3], base[3], base[2], base[1]]), Color(0.12, 0.17, 0.23))
		draw_colored_polygon(top, Color(0.30, 0.37, 0.44))
		draw_polyline(top + PackedVector2Array([top[0]]), Color(0.55, 0.63, 0.68), 1.5)
