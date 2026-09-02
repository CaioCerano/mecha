class_name GridView
extends Node2D

## Draws the terrain: a flat 12x12 checkerboard with dark wall tiles. Also the
## single source of truth for grid<->pixel conversion (all view nodes use it).

const CELL: int = 64
const ORIGIN: Vector2 = Vector2(40, 36)

const FLOOR_A: Color = Color(0.20, 0.22, 0.28)
const FLOOR_B: Color = Color(0.24, 0.26, 0.32)
const WALL: Color = Color(0.10, 0.11, 0.14)
const GRIDLINE: Color = Color(0, 0, 0, 0.25)

var _state: BattleState

static func cell_to_world(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2(c.x * CELL + CELL / 2.0, c.y * CELL + CELL / 2.0)

static func world_to_cell(p: Vector2) -> Vector2i:
	var local: Vector2 = p - ORIGIN
	return Vector2i(floori(local.x / float(CELL)), floori(local.y / float(CELL)))

func setup(state: BattleState) -> void:
	_state = state
	queue_redraw()

func _draw() -> void:
	if _state == null:
		return
	for y: int in range(_state.grid.height):
		for x: int in range(_state.grid.width):
			var c := Vector2i(x, y)
			var r := Rect2(ORIGIN + Vector2(x * CELL, y * CELL), Vector2(CELL, CELL))
			var col: Color = WALL if _state.grid.is_wall(c) else (FLOOR_A if (x + y) % 2 == 0 else FLOOR_B)
			draw_rect(r, col)
			draw_rect(r, GRIDLINE, false, 1.0)
