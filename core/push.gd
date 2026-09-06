class_name Push
extends RefCounted

## Into the Breach style knockback -- the ONE shared displacement resolver.
## Thrust, Bash, Throw, Grapple, and any future forced movement all route
## through here, so walls, barrels, pits, edges and unit-slams behave
## identically everywhere. `trace()` is the pure prediction; `resolve()`
## mutates and is what execution runs.

class Result:
	extends RefCounted
	var start: Vector2i
	var final_pos: Vector2i
	var moved: bool = false
	var collided_with: String = "none"   # none | edge | wall | object | unit
	var blocker_pos: Vector2i = Vector2i(-1, -1)
	var hazard: String = ""              # "" | "pit"  -- the moved unit fell in
	## [{ "id": int (unit) or -1, "pos": Vector2i, "amount": int, "is_reactor": bool }]
	var collision_damage: Array = []

## Pure: where does a unit at `from` end up if shoved `dist` cells along `dir`,
## and what stops it? A pit is a terminal cell -- the unit slides in and stops.
static func trace(state, from: Vector2i, dir: Vector2i, dist: int, source_id: int = -1, willing: bool = false) -> Dictionary:
	var victim: Unit = state.unit_at(from)
	var source: Unit = state.units.get(source_id)
	if victim != null and not willing:
		if victim.braced and source != null and source.team != victim.team:
			dist = 0
		else:
			dist = maxi(0, dist - int(victim.kind == Unit.Kind.BULWARK) - int(victim.has_system("stabilizers")))
	var pos: Vector2i = from
	for i: int in range(dist):
		var nxt: Vector2i = pos + dir
		if not state.grid.in_bounds(nxt):
			return {"final": pos, "collided": "edge", "blocker": nxt, "hazard": ""}
		if state.grid.is_wall(nxt):
			return {"final": pos, "collided": "wall", "blocker": nxt, "hazard": ""}
		var obj: GridObject = state.object_at(nxt)
		if obj != null and obj.is_hazard():
			return {"final": nxt, "collided": "hazard", "blocker": nxt, "hazard": "pit"}
		if obj != null and obj.blocks_forced_move():
			return {"final": pos, "collided": "object", "blocker": nxt, "hazard": ""}
		var other: Unit = state.unit_at(nxt)
		if other != null:
			return {"final": pos, "collided": "unit", "blocker": nxt, "hazard": ""}
		pos = nxt
	return {"final": pos, "collided": "none", "blocker": Vector2i(-1, -1), "hazard": ""}

## Resolve a push: move the unit, then apply the shared consequences --
##  - pit hazard      -> PIT_DAMAGE (destroys), no collision damage
##  - unit / wall / edge / object -> `collision_dmg` to the pushed unit (and to
##    a slammed unit); a slammed destructible object also takes `collision_dmg`
##    (which can detonate a barrel, resolved by BattleState.damage_object).
## `source_id` is whoever initiated the shove (for telemetry attribution).
static func resolve(state, unit: Unit, dir: Vector2i, dist: int, collision_dmg: int, source_id: int = -1, willing: bool = false) -> Result:
	var res := Result.new()
	res.start = unit.pos
	var t: Dictionary = trace(state, unit.pos, dir, dist, source_id, willing)
	var source: Unit = state.units.get(source_id)
	if not willing and dist > 0:
		if unit.has_system("stabilizers"):
			BuildEffects.proc(state, unit, "system", "stabilizers")
		if unit.kind == Unit.Kind.BULWARK:
			BuildEffects.proc(state, unit, "category", "heavy")
		if unit.braced and source != null and source.team != unit.team:
			BuildEffects.proc(state, unit, "secondary", "brace_block")
	if t["collided"] not in ["none", "hazard"] and collision_dmg > 0 and source != null and source.pilot_id == "brawler" and not source.brawler_used:
		collision_dmg += 1
		source.brawler_used = true
		BuildEffects.proc(state, source, "pilot", "brawler")
	state.events.append({"t": "displacement", "id": unit.id, "from": unit.pos, "to": t["final"], "dir": dir,
		"collided": t["collided"], "blocker": t["blocker"], "collision": collision_dmg if t["collided"] not in ["none", "hazard"] else 0})
	res.final_pos = t["final"]
	res.collided_with = t["collided"]
	res.blocker_pos = t["blocker"]
	res.hazard = t["hazard"]
	res.moved = res.final_pos != res.start

	if res.moved:
		state.move_unit(unit, res.final_pos)

	if res.hazard == "pit":
		state.damage_unit(unit, Mission.PIT_DAMAGE, "pit", source_id)
		res.collision_damage.append({"id": unit.id, "pos": unit.pos, "amount": Mission.PIT_DAMAGE, "is_reactor": false})
		return res

	if res.collided_with == "none":
		return res

	if collision_dmg > 0 and unit.is_alive():
		state.damage_unit(unit, collision_dmg, "collision", source_id)
		res.collision_damage.append({"id": unit.id, "pos": unit.pos, "amount": collision_dmg, "is_reactor": false})

	if res.collided_with == "unit" and collision_dmg > 0:
		var other: Unit = state.unit_at(res.blocker_pos)
		if other != null and other.is_alive():
			state.damage_unit(other, collision_dmg, "collision", source_id)
			res.collision_damage.append({"id": other.id, "pos": other.pos, "amount": collision_dmg, "is_reactor": false})

	if res.collided_with == "object" and collision_dmg > 0:
		var obj: GridObject = state.object_at(res.blocker_pos)
		if obj != null and obj.is_destructible():
			state.damage_object(obj, collision_dmg, source_id)   # may detonate

	return res
