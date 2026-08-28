class_name Push
extends RefCounted

## Into the Breach style knockback. A pushed unit slides until something
## stops it; whatever it hits (and the unit itself) takes collision damage.

class Result:
	extends RefCounted
	var start: Vector2i
	var final_pos: Vector2i
	var moved: bool = false
	var collided_with: String = "none"   # none | edge | wall | object | unit
	var blocker_pos: Vector2i = Vector2i(-1, -1)
	## [{ "id": int (unit) or -1, "pos": Vector2i, "amount": int, "is_reactor": bool }]
	var collision_damage: Array = []

## Pure: where does a unit at `from` end up if pushed `dist` cells along
## `dir`, and what (if anything) blocks it? Does not mutate.
static func trace(state, from: Vector2i, dir: Vector2i, dist: int) -> Dictionary:
	var pos: Vector2i = from
	for i: int in range(dist):
		var nxt: Vector2i = pos + dir
		if not state.grid.in_bounds(nxt):
			return {"final": pos, "collided": "edge", "blocker": nxt}
		if state.grid.is_wall(nxt):
			return {"final": pos, "collided": "wall", "blocker": nxt}
		var obj: GridObject = state.object_at(nxt)
		if obj != null and obj.blocks_move():
			return {"final": pos, "collided": "object", "blocker": nxt}
		var other: Unit = state.unit_at(nxt)
		if other != null:
			return {"final": pos, "collided": "unit", "blocker": nxt}
		pos = nxt
	return {"final": pos, "collided": "none", "blocker": Vector2i(-1, -1)}

## Resolve a push: move the unit, apply collision damage to it and to any
## unit it slammed into. Mutates state. `collision_dmg` is the extra damage
## dealt on a hard stop (wall / object / unit / edge).
static func resolve(state, unit: Unit, dir: Vector2i, dist: int, collision_dmg: int) -> Result:
	var res := Result.new()
	res.start = unit.pos
	var t: Dictionary = trace(state, unit.pos, dir, dist)
	res.final_pos = t["final"]
	res.collided_with = t["collided"]
	res.blocker_pos = t["blocker"]
	res.moved = res.final_pos != res.start

	if res.moved:
		state.move_unit(unit, res.final_pos)

	if res.collided_with == "none":
		return res

	# The pushed unit always takes collision damage on a hard stop.
	if collision_dmg > 0 and unit.is_alive():
		state.damage_unit(unit, collision_dmg)
		res.collision_damage.append({"id": unit.id, "pos": unit.pos, "amount": collision_dmg, "is_reactor": false})

	# Slamming into another unit hurts that unit too.
	if res.collided_with == "unit" and collision_dmg > 0:
		var other: Unit = state.unit_at(res.blocker_pos)
		if other != null and other.is_alive():
			state.damage_unit(other, collision_dmg)
			res.collision_damage.append({"id": other.id, "pos": other.pos, "amount": collision_dmg, "is_reactor": false})

	return res
