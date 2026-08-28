class_name Grid
extends RefCounted

## Pure grid geometry: bounds, walls, BFS reachability, pathfinding, and
## straight-line traces. Knows nothing about units — callers pass in the set
## of cells that are blocked by units/objects for movement or line attacks.

const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var width: int
var height: int
var _walls: Dictionary[Vector2i, bool] = {}

func _init(p_width: int, p_height: int, p_walls: Array[Vector2i] = []) -> void:
	width = p_width
	height = p_height
	for w: Vector2i in p_walls:
		_walls[w] = true

func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height

func is_wall(pos: Vector2i) -> bool:
	return _walls.get(pos, false)

func set_wall(pos: Vector2i, value: bool) -> void:
	if value:
		_walls[pos] = true
	else:
		_walls.erase(pos)

func wall_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for pos: Vector2i in _walls:
		out.append(pos)
	return out

## BFS flood fill from `start`, at most `max_steps` orthogonal steps, never
## entering a wall or a cell in `blocked`. Returns cell -> step count
## (excludes `start`).
func reachable(start: Vector2i, max_steps: int, blocked: Dictionary[Vector2i, bool]) -> Dictionary[Vector2i, int]:
	var out: Dictionary[Vector2i, int] = {}
	var frontier: Array[Vector2i] = [start]
	var dist: Dictionary[Vector2i, int] = {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var d: int = dist[current]
		if d >= max_steps:
			continue
		for dir: Vector2i in DIRS:
			var nxt: Vector2i = current + dir
			if dist.has(nxt):
				continue
			if not in_bounds(nxt) or is_wall(nxt) or blocked.get(nxt, false):
				continue
			dist[nxt] = d + 1
			out[nxt] = d + 1
			frontier.append(nxt)
	return out

## Shortest orthogonal path from `start` to `goal` avoiding walls and
## `blocked` (the goal cell itself is allowed to be blocked — useful for
## "step adjacent to the target"). Returns the list of cells after `start`
## up to and including `goal`, or [] if unreachable.
func find_path(start: Vector2i, goal: Vector2i, blocked: Dictionary[Vector2i, bool]) -> Array[Vector2i]:
	if start == goal:
		return []
	var came_from: Dictionary[Vector2i, Vector2i] = {start: start}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == goal:
			return _reconstruct(came_from, start, goal)
		for dir: Vector2i in DIRS:
			var nxt: Vector2i = current + dir
			if came_from.has(nxt):
				continue
			if not in_bounds(nxt) or is_wall(nxt):
				continue
			if nxt != goal and blocked.get(nxt, false):
				continue
			came_from[nxt] = current
			frontier.append(nxt)
	return []

func _reconstruct(came_from: Dictionary[Vector2i, Vector2i], start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var node: Vector2i = goal
	while node != start:
		path.append(node)
		node = came_from[node]
	path.reverse()
	return path

## Cells in a straight cardinal line starting one step from `origin` in
## `dir`, up to `length` cells, clipped to the board. Does not stop at walls.
func line_cells(origin: Vector2i, dir: Vector2i, length: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cell: Vector2i = origin
	for i: int in range(length):
		cell += dir
		if not in_bounds(cell):
			break
		out.append(cell)
	return out

## The plus-shaped area (center + 4 orthogonal neighbours), clipped to board.
func plus_area(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if in_bounds(center):
		out.append(center)
	for dir: Vector2i in DIRS:
		var c: Vector2i = center + dir
		if in_bounds(c):
			out.append(c)
	return out

static func cardinal_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta: Vector2i = to - from
	if delta.x != 0 and delta.y == 0:
		return Vector2i(signi(delta.x), 0)
	if delta.y != 0 and delta.x == 0:
		return Vector2i(0, signi(delta.y))
	return Vector2i.ZERO

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
