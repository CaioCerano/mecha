class_name EnemyAi
extends RefCounted

## Fully deterministic, no RNG. Every enemy's objective is the reactor.
## Grunt: walk to the reactor and hit it (or a mech in the way). Charger and
## enemy-artillery alternate a telegraph turn and a resolve turn.

const CHARGER_RANGE: int = 6
const ENEMY_ARTILLERY_RANGE: int = 5

static func act(state: BattleState, u: Unit) -> void:
	match u.kind:
		Unit.Kind.GRUNT:
			_grunt(state, u)
		Unit.Kind.CHARGER:
			if u.charge_state == Unit.ChargeState.READY:
				_charger_windup(state, u)
		Unit.Kind.ARTILLERY_ENEMY:
			if u.charge_state == Unit.ChargeState.READY:
				_enemy_artillery_windup(state, u)

# ------------------------------------------------------------------- grunt

static func _grunt(state: BattleState, u: Unit) -> void:
	if not _adjacent(u.pos, state.reactor.pos):
		_step_toward(state, u, state.reactor.pos)
	if _adjacent(u.pos, state.reactor.pos):
		state.events.append({"t": "attack", "id": u.id, "target": state.reactor.pos})
		state.damage_reactor(Mission.GRUNT_MELEE_DMG)
		return
	var mech: Unit = _adjacent_mech(state, u)
	if mech != null:
		state.events.append({"t": "attack", "id": u.id, "target": mech.pos})
		state.damage_unit(mech, Mission.GRUNT_MELEE_DMG)

# ------------------------------------------------------------------- charger

static func _charger_windup(state: BattleState, u: Unit) -> void:
	# The charger stays put on its windup turn -- the telegraph is a full-turn
	# warning from a known position. It only moves when it actually charges.
	var dir: Vector2i = _charge_dir(u.pos, state.reactor.pos)
	var cells: Array[Vector2i] = state.line_attack(u.pos, dir, CHARGER_RANGE)["cells"]
	state.telegraphs.append(Telegraph.charge(u.id, cells, dir, Mission.CHARGER_DMG, state.turn_number + 1))
	u.charge_state = Unit.ChargeState.WINDING
	state.events.append({"t": "telegraph_new", "kind": "charge", "cells": cells})

static func _charge_dir(from: Vector2i, goal: Vector2i) -> Vector2i:
	if from.y == goal.y and from.x != goal.x:
		return Vector2i(signi(goal.x - from.x), 0)
	if from.x == goal.x and from.y != goal.y:
		return Vector2i(0, signi(goal.y - from.y))
	# Not aligned: charge along the dominant axis toward the reactor.
	if absi(goal.x - from.x) >= absi(goal.y - from.y) and goal.x != from.x:
		return Vector2i(signi(goal.x - from.x), 0)
	return Vector2i(0, signi(goal.y - from.y))

# -------------------------------------------------------------- enemy artillery

static func _enemy_artillery_windup(state: BattleState, u: Unit) -> void:
	if Grid.manhattan(u.pos, state.reactor.pos) > ENEMY_ARTILLERY_RANGE:
		_step_toward(state, u, state.reactor.pos)
		if Grid.manhattan(u.pos, state.reactor.pos) > ENEMY_ARTILLERY_RANGE:
			return
	var cells: Array[Vector2i] = state.grid.plus_area(state.reactor.pos)
	state.telegraphs.append(Telegraph.aoe(u.id, cells, Mission.ENEMY_ARTILLERY_DMG, state.turn_number + 1))
	u.charge_state = Unit.ChargeState.WINDING
	state.events.append({"t": "telegraph_new", "kind": "aoe", "cells": cells})

# ------------------------------------------------------------------- movement

static func _step_toward(state: BattleState, u: Unit, goal: Vector2i) -> void:
	var blocked: Dictionary[Vector2i, bool] = state.blocked_for_move()
	var path: Array[Vector2i] = state.grid.find_path(u.pos, goal, blocked)
	if not path.is_empty() and path[path.size() - 1] == goal:
		path.remove_at(path.size() - 1)   # stop adjacent to the reactor, don't enter it
	if path.is_empty():
		_greedy_step(state, u, goal, blocked)
		return
	if path.size() > u.move_range:
		path = path.slice(0, u.move_range)
	if path.is_empty():
		return
	var dest: Vector2i = path[path.size() - 1]
	state.move_unit(u, dest)
	state.events.append({"t": "move", "id": u.id, "path": path})

static func _greedy_step(state: BattleState, u: Unit, goal: Vector2i, blocked: Dictionary[Vector2i, bool]) -> void:
	var best: Vector2i = u.pos
	var best_d: int = Grid.manhattan(u.pos, goal)
	for dir: Vector2i in Grid.DIRS:
		var c: Vector2i = u.pos + dir
		if not state.grid.in_bounds(c) or state.grid.is_wall(c) or blocked.get(c, false):
			continue
		var d: int = Grid.manhattan(c, goal)
		if d < best_d:
			best_d = d
			best = c
	if best != u.pos:
		state.move_unit(u, best)
		state.events.append({"t": "move", "id": u.id, "path": [best] as Array[Vector2i]})

# ------------------------------------------------------------------- helpers

static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return Grid.manhattan(a, b) == 1

static func _adjacent_mech(state: BattleState, u: Unit) -> Unit:
	for dir: Vector2i in Grid.DIRS:
		var other: Unit = state.unit_at(u.pos + dir)
		if other != null and other.is_player():
			return other
	return null
