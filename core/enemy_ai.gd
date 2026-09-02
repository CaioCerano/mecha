class_name EnemyAi
extends RefCounted

## Fully deterministic, no RNG.
##  - Grunt / enemy-artillery / Interceptor MOVE via one shared pure planner.
##  - plan_grunt / plan_interceptor return an EnemyPlan describing the whole
##    upcoming action (path, destination, target, damage). Execution applies the
##    plan; the intent UI and Intent.project() render the SAME plan, optionally
##    against a hypothetical board -- so prediction == execution by construction.
##  - Charger / enemy-artillery keep their telegraph state machine.

const CHARGER_RANGE: int = 6
const ENEMY_ARTILLERY_RANGE: int = 5

## Everything the player needs to know about one enemy's next action.
class EnemyPlan:
	extends RefCounted
	var owner_id: int
	var from: Vector2i
	var path: Array[Vector2i] = []      # cells walked, after `from`; [] if it doesn't move
	var dest: Vector2i                  # where it ends up
	var will_attack: bool = false
	var target_kind: String = "none"   # "reactor" | "mech" | "none"
	var target_id: int = -1            # unit id when target_kind == "mech"
	var target_cell: Vector2i = Vector2i(-1, -1)
	var damage: int = 0
	var attack_type: String = "none"  # "melee" | "none"
	var destroyed: bool = false        # the hypothetical action wipes this enemy -> no intent

# ------------------------------------------------------------------- dispatch

static func act(state: BattleState, u: Unit) -> void:
	match u.kind:
		Unit.Kind.GRUNT:
			_apply_plan(state, u, plan_grunt(state, u))
		Unit.Kind.INTERCEPTOR:
			_apply_plan(state, u, plan_interceptor(state, u))
		Unit.Kind.CHARGER:
			if u.charge_state == Unit.ChargeState.READY:
				_charger_windup(state, u)
		Unit.Kind.ARTILLERY_ENEMY:
			if u.charge_state == Unit.ChargeState.READY:
				_enemy_artillery_windup(state, u)

## Deterministic movers only.
static func plans_movement(kind: Unit.Kind) -> bool:
	return kind == Unit.Kind.GRUNT or kind == Unit.Kind.INTERCEPTOR

static func plan_for(state: BattleState, u: Unit, hypo: Dictionary = {}) -> EnemyPlan:
	if u.kind == Unit.Kind.INTERCEPTOR:
		return plan_interceptor(state, u, hypo)
	return plan_grunt(state, u, hypo)

# ------------------------------------------------------------------- grunt

## Grunt: advance on the reactor and melee it; if it can't reach the reactor and
## fetches up next to a mech, hit the mech instead.
static func plan_grunt(state: BattleState, u: Unit, hypo: Dictionary = {}) -> EnemyPlan:
	var p := EnemyPlan.new()
	p.owner_id = u.id
	p.from = _pos(state, hypo, u.id)
	p.dest = p.from
	if _removed(hypo, u.id):
		p.destroyed = true
		return p
	var blocked: Dictionary[Vector2i, bool] = _blocked(state, hypo)
	if not _adjacent(p.from, state.reactor.pos):
		var mv: Dictionary = plan_move(state, p.from, state.reactor.pos, blocked, u.move_range, true)
		p.path = mv["path"]
		p.dest = mv["dest"]
	if _adjacent(p.dest, state.reactor.pos):
		_set_attack(p, "reactor", -1, state.reactor.pos, Mission.GRUNT_MELEE_DMG)
	else:
		var mid: int = _adjacent_mech_id(state, hypo, p.dest)
		if mid != -1:
			_set_attack(p, "mech", mid, _pos(state, hypo, mid), Mission.GRUNT_MELEE_DMG)
	return p

# ------------------------------------------------------------------- interceptor

## Interceptor: ignores the reactor. Picks the mech that is closest by PATH
## length (lowest unit id breaks ties), pursues it, and melees it if adjacent
## after moving.
static func plan_interceptor(state: BattleState, u: Unit, hypo: Dictionary = {}) -> EnemyPlan:
	var p := EnemyPlan.new()
	p.owner_id = u.id
	p.from = _pos(state, hypo, u.id)
	p.dest = p.from
	if _removed(hypo, u.id):
		p.destroyed = true
		return p
	var blocked: Dictionary[Vector2i, bool] = _blocked(state, hypo)
	var tid: int = _pick_mech_target(state, hypo, p.from, blocked)
	if tid == -1:
		return p   # no mechs left -> idle (game already lost)
	var tpos: Vector2i = _pos(state, hypo, tid)
	if not _adjacent(p.from, tpos):
		var mv: Dictionary = plan_move(state, p.from, tpos, blocked, u.move_range, true)
		p.path = mv["path"]
		p.dest = mv["dest"]
	if _adjacent(p.dest, tpos):
		_set_attack(p, "mech", tid, tpos, Mission.INTERCEPTOR_DMG)
	else:
		p.target_id = tid   # still "pursuing" this mech even if it can't reach yet
	return p

## Closest reachable mech by path length; deterministic tie-break = lowest id.
static func _pick_mech_target(state: BattleState, hypo: Dictionary, from: Vector2i,
		blocked: Dictionary[Vector2i, bool]) -> int:
	var best_id: int = -1
	var best_len: int = 1 << 30
	for m: Unit in state.player_mechs():   # already sorted ascending by id
		if not m.is_alive() or _removed(hypo, m.id):
			continue
		var mpos: Vector2i = _pos(state, hypo, m.id)
		var path: Array[Vector2i] = state.grid.find_path(from, mpos, blocked)
		var plen: int
		if not path.is_empty():
			plen = path.size()
		else:
			plen = 100000 + Grid.manhattan(from, mpos)   # unreachable: ranked last, still deterministic
		if plen < best_len:
			best_len = plen
			best_id = m.id
	return best_id

# ------------------------------------------------------------------- shared movement

## Pure. Walk from `from` toward `goal` at most `move_range` steps, avoiding
## `blocked` (units + solid terrain) and walls. `stop_adjacent` trims the goal
## cell (used when the goal is the reactor / a mech you attack from beside).
## Falls back to a single greedy cardinal step if A* finds no route.
static func plan_move(state: BattleState, from: Vector2i, goal: Vector2i,
		blocked: Dictionary[Vector2i, bool], move_range: int, stop_adjacent: bool) -> Dictionary:
	var path: Array[Vector2i] = state.grid.find_path(from, goal, blocked)
	if stop_adjacent and not path.is_empty() and path[path.size() - 1] == goal:
		path = path.slice(0, path.size() - 1)
	if path.is_empty():
		var best: Vector2i = from
		var best_d: int = Grid.manhattan(from, goal)
		for dir: Vector2i in Grid.DIRS:
			var c: Vector2i = from + dir
			if not state.grid.in_bounds(c) or state.grid.is_wall(c) or blocked.get(c, false):
				continue
			var d: int = Grid.manhattan(c, goal)
			if d < best_d:
				best_d = d
				best = c
		if best != from:
			return {"path": [best] as Array[Vector2i], "dest": best}
		return {"path": [] as Array[Vector2i], "dest": from}
	if path.size() > move_range:
		path = path.slice(0, move_range)
	if path.is_empty():
		return {"path": [] as Array[Vector2i], "dest": from}
	return {"path": path, "dest": path[path.size() - 1]}

static func _apply_plan(state: BattleState, u: Unit, p: EnemyPlan) -> void:
	if not p.path.is_empty():
		state.move_unit(u, p.dest)
		state.events.append({"t": "move", "id": u.id, "path": p.path})
	if p.will_attack:
		state.events.append({"t": "attack", "id": u.id, "target": p.target_cell})
		if p.target_kind == "reactor":
			state.damage_reactor(p.damage, "melee")
		elif p.target_kind == "mech":
			var m: Unit = state.units.get(p.target_id)
			if m != null and m.is_alive():
				state.damage_unit(m, p.damage, "melee", u.id)

# ------------------------------------------------------------------- charger

static func _charger_windup(state: BattleState, u: Unit) -> void:
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
	if absi(goal.x - from.x) >= absi(goal.y - from.y) and goal.x != from.x:
		return Vector2i(signi(goal.x - from.x), 0)
	return Vector2i(0, signi(goal.y - from.y))

# -------------------------------------------------------------- enemy artillery

static func _enemy_artillery_windup(state: BattleState, u: Unit) -> void:
	if Grid.manhattan(u.pos, state.reactor.pos) > ENEMY_ARTILLERY_RANGE:
		var mv: Dictionary = plan_move(state, u.pos, state.reactor.pos, state.blocked_for_move(), u.move_range, true)
		if not mv["path"].is_empty():
			state.move_unit(u, mv["dest"])
			state.events.append({"t": "move", "id": u.id, "path": mv["path"]})
		if Grid.manhattan(u.pos, state.reactor.pos) > ENEMY_ARTILLERY_RANGE:
			return
	var cells: Array[Vector2i] = state.grid.plus_area(state.reactor.pos)
	state.telegraphs.append(Telegraph.aoe(u.id, cells, Mission.ENEMY_ARTILLERY_DMG, state.turn_number + 1))
	u.charge_state = Unit.ChargeState.WINDING
	state.events.append({"t": "telegraph_new", "kind": "aoe", "cells": cells})

# ------------------------------------------------------------------- hypo helpers

static func _set_attack(p: EnemyPlan, kind: String, tid: int, cell: Vector2i, dmg: int) -> void:
	p.will_attack = true
	p.target_kind = kind
	p.target_id = tid
	p.target_cell = cell
	p.damage = dmg
	p.attack_type = "melee"

static func _removed(hypo: Dictionary, id: int) -> bool:
	return hypo.get("removed", {}).get(id, false)

## Where unit `id` is, honouring a hypothetical move.
static func _pos(state: BattleState, hypo: Dictionary, id: int) -> Vector2i:
	var moves: Dictionary = hypo.get("moves", {})
	if moves.has(id):
		return moves[id]
	var u: Unit = state.units.get(id)
	return u.pos if u != null else Vector2i(-1, -1)

## Move-blocked cells for pathfinding under a hypothetical board.
static func _blocked(state: BattleState, hypo: Dictionary) -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	var moves: Dictionary = hypo.get("moves", {})
	var removed: Dictionary = hypo.get("removed", {})
	for id: int in state.units:
		var u: Unit = state.units[id]
		if not u.is_alive() or removed.get(id, false):
			continue
		out[moves.get(id, u.pos)] = true
	for pos: Vector2i in state.objects:
		if state.objects[pos].blocks_move():
			out[pos] = true
	for c: Vector2i in hypo.get("blockers", []):
		out[c] = true
	return out

## First adjacent player mech to `cell` (DIRS order), honouring the hypothetical.
static func _adjacent_mech_id(state: BattleState, hypo: Dictionary, cell: Vector2i) -> int:
	for dir: Vector2i in Grid.DIRS:
		var id: int = _unit_id_at(state, hypo, cell + dir)
		if id != -1:
			var u: Unit = state.units.get(id)
			if u != null and u.is_player():
				return id
	return -1

static func _unit_id_at(state: BattleState, hypo: Dictionary, cell: Vector2i) -> int:
	var moves: Dictionary = hypo.get("moves", {})
	var removed: Dictionary = hypo.get("removed", {})
	for id: int in moves:
		if moves[id] == cell and not removed.get(id, false):
			return id
	var here: int = state.occupancy.get(cell, -1)
	if here == -1 or removed.get(here, false):
		return -1
	if moves.has(here) and moves[here] != cell:
		return -1
	var u: Unit = state.units.get(here)
	return here if u != null and u.is_alive() else -1

static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return Grid.manhattan(a, b) == 1
