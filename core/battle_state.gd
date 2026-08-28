class_name BattleState
extends RefCounted

## The whole rules engine for the one mission. Pure logic, no Node, headless
## testable. `events` accumulates view-facing hints (moves, damage, deaths,
## telegraphs...) that the battle scene drains with take_events() and plays
## back as tweens.

enum Phase { PLAYER, ENEMY, WON, LOST }

var grid: Grid
var units: Dictionary[int, Unit] = {}
var occupancy: Dictionary[Vector2i, int] = {}      # cell -> unit id (spec: kept separate)
var objects: Dictionary[Vector2i, GridObject] = {} # cell -> spear / shield / reactor
var telegraphs: Array[Telegraph] = []
## Player mortars in flight: [{ "cells": Array[Vector2i], "damage": int, "resolve_on_turn": int }]
var pending_mortars: Array = []

var reactor: GridObject
var turn_number: int = 1
var turns_survived: int = 0
var phase: Phase = Phase.PLAYER

var events: Array = []
var _next_id: int = 1
var _spawn_index: int = 0

# ----------------------------------------------------------------- construction

func _init() -> void:
	grid = Grid.new(Mission.GRID_W, Mission.GRID_H, Mission.walls())
	reactor = GridObject.make_reactor(Mission.REACTOR_POS, Mission.REACTOR_HP)
	objects[reactor.pos] = reactor
	var starts: Dictionary = Mission.mech_starts()
	for kind: Unit.Kind in [Unit.Kind.SPEAR, Unit.Kind.SHIELD, Unit.Kind.ARTILLERY]:
		_spawn_unit(kind, Unit.Team.PLAYER, starts[kind])
	for m: Unit in player_mechs():
		m.ap = m.max_ap

func _spawn_unit(kind: Unit.Kind, team: Unit.Team, pos: Vector2i) -> Unit:
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.team = team
	u.kind = kind
	u.pos = pos
	var stats: Dictionary = Mission.unit_stats(kind)
	u.hp = stats["hp"]
	u.max_hp = stats["hp"]
	u.move_range = stats["move"]
	units[u.id] = u
	occupancy[pos] = u.id
	return u

# ----------------------------------------------------------------- queries

func unit_at(pos: Vector2i) -> Unit:
	var id: int = occupancy.get(pos, -1)
	if id == -1:
		return null
	var u: Unit = units.get(id)
	return u if u != null and u.is_alive() else null

func object_at(pos: Vector2i) -> GridObject:
	return objects.get(pos)

func player_mechs() -> Array[Unit]:
	var out: Array[Unit] = []
	for id: int in _sorted_ids():
		var u: Unit = units[id]
		if u.is_player():
			out.append(u)
	return out

func living_enemies() -> Array[Unit]:
	var out: Array[Unit] = []
	for id: int in _sorted_ids():
		var u: Unit = units[id]
		if not u.is_player() and u.is_alive():
			out.append(u)
	return out

func _sorted_ids() -> Array:
	var ids: Array = units.keys()
	ids.sort()
	return ids

## Cells a unit may not enter: living units + move-blocking objects.
func blocked_for_move() -> Dictionary[Vector2i, bool]:
	var out: Dictionary[Vector2i, bool] = {}
	for id: int in units:
		var u: Unit = units[id]
		if u.is_alive():
			out[u.pos] = true
	for pos: Vector2i in objects:
		if objects[pos].blocks_move():
			out[pos] = true
	return out

func reachable_for(unit: Unit) -> Dictionary[Vector2i, int]:
	return grid.reachable(unit.pos, unit.move_range, blocked_for_move())

## Trace a straight cardinal attack from `from` along `dir`, up to `max_len`.
## Returns { cells, hit_unit, hit_reactor, hit_pos, blocked_by_wall }.
## Stops at the first wall / shield / unit / reactor.
func line_attack(from: Vector2i, dir: Vector2i, max_len: int) -> Dictionary:
	var cells: Array[Vector2i] = []
	var cell: Vector2i = from
	for i: int in range(max_len):
		cell += dir
		if not grid.in_bounds(cell):
			return {"cells": cells, "hit_unit": null, "hit_reactor": false, "hit_pos": Vector2i(-1, -1), "blocked_by_wall": false}
		if grid.is_wall(cell):
			return {"cells": cells, "hit_unit": null, "hit_reactor": false, "hit_pos": Vector2i(-1, -1), "blocked_by_wall": true}
		var obj: GridObject = object_at(cell)
		if obj != null and obj.kind == GridObject.Kind.REACTOR:
			cells.append(cell)
			return {"cells": cells, "hit_unit": null, "hit_reactor": true, "hit_pos": cell, "blocked_by_wall": false}
		if obj != null and obj.blocks_line():
			return {"cells": cells, "hit_unit": null, "hit_reactor": false, "hit_pos": Vector2i(-1, -1), "blocked_by_wall": false}
		var u: Unit = unit_at(cell)
		if u != null:
			cells.append(cell)
			return {"cells": cells, "hit_unit": u, "hit_reactor": false, "hit_pos": cell, "blocked_by_wall": false}
		cells.append(cell)
	return {"cells": cells, "hit_unit": null, "hit_reactor": false, "hit_pos": Vector2i(-1, -1), "blocked_by_wall": false}

# ----------------------------------------------------------------- mutation

## Low-level teleport: keeps occupancy in sync. Emits no event.
func move_unit(unit: Unit, dest: Vector2i) -> void:
	if occupancy.get(unit.pos, -1) == unit.id:
		occupancy.erase(unit.pos)
	unit.pos = dest
	occupancy[dest] = unit.id

func damage_unit(unit: Unit, amount: int) -> int:
	if not unit.is_alive():
		return 0
	var final: int = amount
	# Shield mech keeps a -1 damage bonus while its shield is stowed.
	if unit.kind == Unit.Kind.SHIELD and not unit.shield_deployed:
		final = maxi(1, amount - 1)
	final = mini(final, unit.hp)
	unit.hp -= final
	events.append({"t": "damage", "id": unit.id, "pos": unit.pos, "amount": final, "hp": unit.hp})
	if not unit.is_alive():
		if occupancy.get(unit.pos, -1) == unit.id:
			occupancy.erase(unit.pos)
		events.append({"t": "death", "id": unit.id, "pos": unit.pos})
	return final

func damage_reactor(amount: int) -> void:
	if reactor.hp <= 0:
		return
	var final: int = mini(amount, reactor.hp)
	reactor.hp -= final
	events.append({"t": "reactor_damage", "pos": reactor.pos, "amount": final, "hp": reactor.hp})

func place_object(obj: GridObject) -> void:
	objects[obj.pos] = obj

func remove_object_at(pos: Vector2i) -> GridObject:
	var obj: GridObject = objects.get(pos)
	if obj != null:
		objects.erase(pos)
	return obj

func destroy_wall(pos: Vector2i) -> void:
	if grid.is_wall(pos):
		grid.set_wall(pos, false)
		events.append({"t": "wall_destroyed", "pos": pos})

func take_events() -> Array:
	var out: Array = events
	events = []
	return out

# ----------------------------------------------------------------- player API

func player_move(unit: Unit, dest: Vector2i) -> bool:
	if phase != Phase.PLAYER or not unit.is_alive() or unit.ap < 1:
		return false
	if not reachable_for(unit).has(dest):
		return false
	var path: Array[Vector2i] = grid.find_path(unit.pos, dest, blocked_for_move())
	if path.is_empty():
		return false
	move_unit(unit, dest)
	events.append({"t": "move", "id": unit.id, "path": path})
	unit.ap -= 1
	return true

func player_action(unit: Unit, action_id: String, target_cell: Vector2i) -> bool:
	if phase != Phase.PLAYER or not unit.is_alive():
		return false
	var free: bool = MechActions.is_free(action_id)
	if not free and unit.ap < 1:
		return false
	if not action_id in MechActions.available_actions(self, unit):
		return false
	if not ActionPreview.build(self, unit, action_id, target_cell).valid:
		return false
	MechActions.execute(self, unit, action_id, target_cell)
	if not free:
		unit.ap -= 1
	_check_end()
	return true

func end_player_turn() -> void:
	if phase != Phase.PLAYER:
		return
	phase = Phase.ENEMY
	events.append({"t": "phase", "phase": phase})
	_run_enemy_turn()

# ----------------------------------------------------------------- enemy turn

func _run_enemy_turn() -> void:
	_spawn_for_turn(turn_number)

	var due: Array[Telegraph] = []
	for tg: Telegraph in telegraphs:
		if tg.resolve_on_turn == turn_number:
			due.append(tg)
	for tg: Telegraph in due:
		_resolve_telegraph(tg)
		telegraphs.erase(tg)
	if _check_end():
		return

	for id: int in _sorted_ids():
		var u: Unit = units[id]
		if u.is_player() or not u.is_alive():
			continue
		EnemyAi.act(self, u)
		if _check_end():
			return

	turns_survived += 1
	if _check_end():
		return
	turn_number += 1
	phase = Phase.PLAYER
	events.append({"t": "phase", "phase": phase})
	_start_player_turn()

func _start_player_turn() -> void:
	for m: Unit in player_mechs():
		if m.is_alive():
			m.ap = m.max_ap
	_resolve_pending_mortars()
	_check_end()

func _resolve_pending_mortars() -> void:
	var still_pending: Array = []
	for pm: Dictionary in pending_mortars:
		if pm["resolve_on_turn"] != turn_number:
			still_pending.append(pm)
			continue
		var cells: Array = pm["cells"]
		for c: Vector2i in cells:
			destroy_wall(c)
			var u: Unit = unit_at(c)
			if u != null:
				damage_unit(u, pm["damage"])
			if reactor.pos == c:
				damage_reactor(pm["damage"])
		events.append({"t": "mortar_resolve", "cells": cells})
	pending_mortars = still_pending

func _spawn_for_turn(turn: int) -> void:
	var schedule: Dictionary = Mission.spawn_schedule()
	if not schedule.has(turn):
		return
	var points: Array[Vector2i] = Mission.spawn_points()
	for kind: Unit.Kind in schedule[turn]:
		var anchor: Vector2i = points[_spawn_index % points.size()]
		_spawn_index += 1
		var cell: Vector2i = _nearest_free_cell(anchor)
		if cell == Vector2i(-1, -1):
			continue
		var u: Unit = _spawn_unit(kind, Unit.Team.ENEMY, cell)
		events.append({"t": "spawn", "id": u.id, "pos": cell, "kind": kind})

func _nearest_free_cell(anchor: Vector2i) -> Vector2i:
	var blocked: Dictionary[Vector2i, bool] = blocked_for_move()
	var seen: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = [anchor]
	seen[anchor] = true
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if grid.in_bounds(c) and not grid.is_wall(c) and not blocked.get(c, false):
			return c
		for dir: Vector2i in Grid.DIRS:
			var n: Vector2i = c + dir
			if not seen.get(n, false) and grid.in_bounds(n):
				seen[n] = true
				frontier.append(n)
	return Vector2i(-1, -1)

func _resolve_telegraph(tg: Telegraph) -> void:
	var owner: Unit = units.get(tg.owner_id)
	if tg.kind == Telegraph.Kind.CHARGE_LINE:
		if owner == null or not owner.is_alive():
			return
		var la: Dictionary = line_attack(owner.pos, tg.charge_dir, EnemyAi.CHARGER_RANGE)
		var travelled: Array[Vector2i] = la["cells"]
		var dest: Vector2i = owner.pos
		for c: Vector2i in travelled:
			if unit_at(c) == null and (object_at(c) == null or not object_at(c).blocks_move()):
				dest = c
		if dest != owner.pos:
			move_unit(owner, dest)
			events.append({"t": "charge_move", "id": owner.id, "to": dest})
		if la["hit_unit"] != null:
			damage_unit(la["hit_unit"], tg.damage)
		elif la["hit_reactor"]:
			damage_reactor(tg.damage)
		owner.charge_state = Unit.ChargeState.READY
		events.append({"t": "telegraph_resolve", "kind": "charge", "cells": travelled})
	else:
		for c: Vector2i in tg.cells:
			var u: Unit = unit_at(c)
			if u != null:
				damage_unit(u, tg.damage)
			if reactor.pos == c:
				damage_reactor(tg.damage)
		if owner != null:
			owner.charge_state = Unit.ChargeState.READY
		events.append({"t": "telegraph_resolve", "kind": "aoe", "cells": tg.cells})

# ----------------------------------------------------------------- end game

func _check_end() -> bool:
	if phase == Phase.WON or phase == Phase.LOST:
		return true
	if reactor.hp <= 0:
		_end_game(false)
		return true
	var any_mech_alive: bool = false
	for m: Unit in player_mechs():
		if m.is_alive():
			any_mech_alive = true
			break
	if not any_mech_alive:
		_end_game(false)
		return true
	if turns_survived >= Mission.SURVIVE_TURNS:
		_end_game(true)
		return true
	return false

func _end_game(won: bool) -> void:
	phase = Phase.WON if won else Phase.LOST
	events.append({"t": "game_over", "won": won})
