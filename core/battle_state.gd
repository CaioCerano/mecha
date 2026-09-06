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
## Reinforcements announced but not yet on the board. Each:
##   { kind: Unit.Kind, cell: Vector2i, edge_dir: Vector2i, arrive_on_turn: int }
## Announced at the start of a player phase, they physically enter on the very
## next enemy phase and only act the enemy phase after that -- so the player
## always gets a full phase to reposition. No damage from a unit that wasn't
## already visible (as a real unit or a spawn telegraph) last player phase.
var pending_spawns: Array = []

var reactor: GridObject
var loadout: SquadLoadout
var data: MissionData
var tel: Telemetry
var turn_number: int = 1
var turns_survived: int = 0
var phase: Phase = Phase.PLAYER

var events: Array = []
var _next_id: int = 1
var _spawn_index: int = 0

# ----------------------------------------------------------------- construction

func _init(mission_data: MissionData = null, squad_loadout: SquadLoadout = null) -> void:
	loadout = squad_loadout.copy() if squad_loadout != null else SquadLoadout.new()
	if not loadout.validation_errors().is_empty():
		push_error("Invalid squad loadout: " + str(loadout.validation_errors()))
		return
	data = mission_data if mission_data != null else Mission.reactor_breach()
	tel = Telemetry.new()
	grid = Grid.new(data.grid_w, data.grid_h, data.walls)
	reactor = GridObject.make_reactor(data.reactor_pos, data.reactor_hp)
	objects[reactor.pos] = reactor
	for p: Vector2i in data.pits:
		objects[p] = GridObject.make_pit(p)
	for p: Vector2i in data.barrels:
		objects[p] = GridObject.make_explosive(p, Mission.EXPLOSIVE_HP)
	for kind: Unit.Kind in [Unit.Kind.LANCER, Unit.Kind.BULWARK, Unit.Kind.GRAPPLER]:
		if data.mech_starts.has(kind):
			_spawn_unit(kind, Unit.Team.PLAYER, data.mech_starts[kind])
	for m: Unit in player_mechs():
		m.ap = m.max_ap
	# Wave 1 (initial_enemies) is on the board from the opening turn so the first
	# player turn is a real tactical decision. Later waves are telegraphed.
	for e: Dictionary in data.initial_enemies:
		_spawn_unit(e["kind"], Unit.Team.ENEMY, e["cell"])
	events.clear()

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
	if team == Unit.Team.PLAYER and loadout.mechs.has(kind):
		var build: Dictionary = loadout.mechs[kind]
		u.secondary_id = build["secondary_id"]
		u.systems.assign(build["systems"])
		u.pilot_id = build["pilot_id"]
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
	return grid.reachable(unit.pos, unit.movement(), blocked_for_move())

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
			# an explosive stops the line and can be hit at that cell
			cells.append(cell)
			return {"cells": cells, "hit_unit": null, "hit_reactor": false, "hit_pos": cell,
				"blocked_by_wall": false, "hit_object": obj}
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

func damage_unit(unit: Unit, amount: int, cause: String = "hit", by_id: int = -1) -> int:
	if not unit.is_alive():
		return 0
	if cause == "collision" and unit.has_system("shock_absorbers"):
		BuildEffects.proc(self, unit, "system", "shock_absorbers")
	var potential: int = unit.mitigate(amount, cause)
	var final: int = mini(potential, unit.hp)
	var old_condition := unit.damage_state()
	unit.hp -= final
	BuildEffects.update_damage(self, unit, old_condition)
	tel.note_damage(self, unit.id, final, cause, by_id)
	events.append({"t": "damage", "id": unit.id, "pos": unit.pos, "amount": final, "potential": potential, "hp": unit.hp, "cause": cause})
	if not unit.is_alive():
		if occupancy.get(unit.pos, -1) == unit.id:
			occupancy.erase(unit.pos)
		tel.note_death(self, unit, cause, by_id)
		events.append({"t": "death", "id": unit.id, "pos": unit.pos, "kind": unit.kind, "cause": cause})
	return final

func damage_reactor(amount: int, cause: String = "hit") -> void:
	if reactor.hp <= 0:
		return
	var final: int = mini(amount, reactor.hp)
	reactor.hp -= final
	tel.bump("reactor_damage_taken", final)
	events.append({"t": "reactor_damage", "pos": reactor.pos, "amount": final, "hp": reactor.hp, "cause": cause})

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

## Damage a destructible object (explosive barrel). Reaching 0 HP detonates it,
## which is resolved immediately (iterative chain, no recursion). `by_id` is
## whoever caused the hit, threaded to the blast for telemetry attribution.
func damage_object(obj: GridObject, amount: int, by_id: int = -1) -> void:
	if obj == null or not obj.is_destructible() or obj.hp <= 0:
		return
	obj.hp -= amount
	events.append({"t": "object_damage", "pos": obj.pos, "amount": amount, "hp": maxi(obj.hp, 0)})
	if obj.hp <= 0:
		detonate([obj.pos], by_id)

## Explode every barrel in `initial`, apply the plus-shaped blast, and chain
## into any barrel the blast destroys. Deterministic breadth-first drain.
func detonate(initial: Array[Vector2i], by_id: int = -1) -> void:
	var queue: Array[Vector2i] = initial.duplicate()
	var done: Dictionary[Vector2i, bool] = {}
	var blast_all: Dictionary[Vector2i, bool] = {}
	while not queue.is_empty():
		var center: Vector2i = queue.pop_front()
		if done.get(center, false):
			continue
		var e: GridObject = objects.get(center)
		if e == null or e.kind != GridObject.Kind.EXPLOSIVE:
			continue
		done[center] = true
		objects.erase(center)
		events.append({"t": "object_destroyed", "pos": center, "kind": e.kind})
		for c: Vector2i in grid.plus_area(center):
			blast_all[c] = true
			var u: Unit = unit_at(c)
			if u != null:
				damage_unit(u, Mission.EXPLOSIVE_DMG, "explosion", by_id)
			if reactor.pos == c:
				damage_reactor(Mission.EXPLOSIVE_DMG, "explosion")
			var chained: GridObject = objects.get(c)
			if chained != null and chained.kind == GridObject.Kind.EXPLOSIVE and not done.get(c, false):
				chained.hp -= Mission.EXPLOSIVE_DMG
				if chained.hp <= 0:
					queue.append(c)
	tel.bump("explosions")
	tel.bump("barrels_triggered", done.size())
	events.append({"t": "explosion", "cells": blast_all.keys()})

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
	if unit.has_system("vector_thrusters") and not unit.thrusters_used:
		BuildEffects.proc(self, unit, "system", "vector_thrusters")
		unit.thrusters_used = true
	unit.moved_this_turn += path.size()
	move_unit(unit, dest)
	events.append({"t": "move", "id": unit.id, "path": path})
	unit.ap -= 1
	tel.note_action(unit.kind, "move")
	return true

func player_action(unit: Unit, action_id: String, target_cell: Vector2i, opts: Dictionary = {}) -> bool:
	if phase != Phase.PLAYER or not unit.is_alive():
		return false
	var free: bool = MechActions.is_free(action_id)
	if not free and unit.ap < 1:
		return false
	if not action_id in MechActions.available_actions(self, unit):
		return false
	if not ActionPreview.build(self, unit, action_id, target_cell, opts).valid:
		return false
	if not free:
		unit.ap -= 1
	MechActions.execute(self, unit, action_id, target_cell, opts)
	tel.note_action(unit.kind, action_id)
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
	# Freeze the acting set BEFORE reinforcements land -- a unit that enters this
	# phase waits until next phase to do anything.
	var can_act: Array[int] = []
	for id: int in _sorted_ids():
		var u: Unit = units[id]
		if not u.is_player() and u.is_alive():
			can_act.append(id)

	_resolve_due_spawns()

	var due: Array[Telegraph] = []
	for tg: Telegraph in telegraphs:
		if tg.resolve_on_turn == turn_number:
			due.append(tg)
	for tg: Telegraph in due:
		_resolve_telegraph(tg)
		telegraphs.erase(tg)
	if _check_end():
		return

	for id: int in can_act:
		var u: Unit = units.get(id)
		if u == null or not u.is_alive():
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
			m.reset_turn()
	_announce_spawns(turn_number)
	_check_end()

## Wave 1 (data.initial_enemies) is placed on the board directly (see _init).
## Every later wave is announced here at the top of its player phase, enters
## next enemy phase.
func _announce_spawns(turn: int) -> void:
	var schedule: Dictionary = data.spawn_schedule
	if not schedule.has(turn):
		return
	var points: Array[Vector2i] = data.spawn_points
	for kind: Unit.Kind in schedule[turn]:
		var anchor: Vector2i = points[_spawn_index % points.size()]
		_spawn_index += 1
		pending_spawns.append({
			"kind": kind,
			"cell": anchor,
			"edge_dir": _entry_dir(anchor, reactor.pos),
			"arrive_on_turn": turn,
		})
		events.append({"t": "spawn_telegraph", "cell": anchor, "kind": kind})

## Bring in every reinforcement whose arrival phase is now. They do NOT act
## this phase (see _run_enemy_turn's frozen acting set).
func _resolve_due_spawns() -> void:
	var still: Array = []
	for sp: Dictionary in pending_spawns:
		if sp["arrive_on_turn"] != turn_number:
			still.append(sp)
			continue
		var cell: Vector2i = _nearest_free_cell(sp["cell"])
		if cell == Vector2i(-1, -1):
			still.append(sp)   # totally boxed in -- try again next phase
			continue
		var u: Unit = _spawn_unit(sp["kind"], Unit.Team.ENEMY, cell)
		events.append({"t": "spawn", "id": u.id, "pos": cell, "kind": sp["kind"]})
	pending_spawns = still

static func _entry_dir(from: Vector2i, goal: Vector2i) -> Vector2i:
	var dx: int = goal.x - from.x
	var dy: int = goal.y - from.y
	if absi(dx) >= absi(dy):
		return Vector2i(signi(dx), 0)
	return Vector2i(0, signi(dy))

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
		# ONE charge geometry, shared with Intent.project's prediction.
		var oc: Dictionary = Intent.charge_outcome(self, owner.pos, tg.charge_dir, {}, [])
		var dest: Vector2i = oc["stop"]
		if dest != owner.pos:
			move_unit(owner, dest)
			events.append({"t": "charge_move", "id": owner.id, "to": dest})
		owner.charge_state = Unit.ChargeState.READY
		if oc["pit"]:
			damage_unit(owner, Mission.PIT_DAMAGE, "pit", -1)
			tel.bump("charges_blocked")
			events.append({"t": "charge_result", "id": owner.id, "hit": false, "pit": true})
			events.append({"t": "telegraph_resolve", "kind": "charge", "cells": oc["cells"]})
			return
		var ahead: Vector2i = dest + tg.charge_dir
		var struck: Unit = unit_at(ahead)
		var aobj: GridObject = object_at(ahead)
		var did_hit: bool = true
		if struck != null:
			damage_unit(struck, tg.damage, "charge", owner.id)
		elif aobj != null and aobj.is_destructible():
			damage_object(aobj, tg.damage, -1)
		elif reactor.pos == ahead:
			damage_reactor(tg.damage, "charge")
		else:
			did_hit = false
			tel.bump("charges_blocked")
		events.append({"t": "charge_result", "id": owner.id, "hit": did_hit, "pit": false})
		events.append({"t": "telegraph_resolve", "kind": "charge", "cells": oc["cells"]})
	else:
		for c: Vector2i in tg.cells:
			var u: Unit = unit_at(c)
			if u != null:
				damage_unit(u, tg.damage, "aoe", tg.owner_id)
			if reactor.pos == c:
				damage_reactor(tg.damage, "aoe")
		if owner != null:
			owner.charge_state = Unit.ChargeState.READY
		events.append({"t": "telegraph_resolve", "kind": "aoe", "cells": tg.cells})

# ----------------------------------------------------------------- end game

func _check_end() -> bool:
	if phase == Phase.WON or phase == Phase.LOST:
		return true
	if data.defeat_if_reactor_destroyed and reactor.hp <= 0:
		_end_game(false)
		return true
	if data.defeat_if_squad_lost:
		var any_mech_alive: bool = false
		for m: Unit in player_mechs():
			if m.is_alive():
				any_mech_alive = true
				break
		if not any_mech_alive:
			_end_game(false)
			return true
	if turns_survived >= data.turn_limit:
		_end_game(true)
		return true
	return false

## Optional objective for Reactor Breach: all three mechs still operational.
func optional_objective_met() -> bool:
	if data.objective_optional == "":
		return true
	for m: Unit in player_mechs():
		if not m.is_alive():
			return false
	return true

func _end_game(won: bool) -> void:
	phase = Phase.WON if won else Phase.LOST
	tel.finalize(self, won)
	events.append({"t": "game_over", "won": won})

## Isolated action simulation for previews. Mission data/telegraphs are read-only
## during actions; mutable units, terrain, occupancy and telemetry are independent.
func simulation_copy() -> BattleState:
	var result := BattleState.new(data, loadout)
	result.units.clear()
	for id: int in units:
		result.units[id] = units[id].copy()
	result.occupancy = occupancy.duplicate()
	result.objects.clear()
	for c: Vector2i in objects:
		var o: GridObject = objects[c]
		result.objects[c] = GridObject._mk(o.kind, o.pos, o.owner_id, o.hp)
		result.objects[c].max_hp = o.max_hp
	result.reactor = result.objects[reactor.pos]
	result.grid = Grid.new(grid.width, grid.height, grid.wall_cells())
	result.phase = phase
	result.turn_number = turn_number
	result.turns_survived = turns_survived
	result.pending_spawns = pending_spawns.duplicate(true)
	result.telegraphs = telegraphs.duplicate()
	result.events.clear()
	return result
