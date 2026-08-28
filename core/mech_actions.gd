class_name MechActions
extends RefCounted

## Deterministic resolvers for every player mech action, plus the geometry
## helpers the preview layer reuses so "what you see" always equals "what
## happens". Each resolver mutates BattleState and appends view events;
## BattleState.player_action() handles AP and legality.

const THRUST_DMG: int = 2
const THRUST_COLLISION: int = 2
const PUNCH_DMG: int = 1
const THROW_DMG: int = 4
const THROW_RANGE: int = 6
const BASH_DMG: int = 1
const BASH_COLLISION: int = 1
const CANNON_DMG: int = 3
const CANNON_RANGE: int = 8
const MORTAR_DMG: int = 3
const MORTAR_RANGE: int = 6

# ------------------------------------------------------------- action listing

static func available_actions(state: BattleState, unit: Unit) -> Array[String]:
	var acts: Array[String] = []
	match unit.kind:
		Unit.Kind.SPEAR:
			if unit.has_spear:
				acts = ["thrust", "throw_spear"]
			else:
				acts = ["punch"]
			if adjacent_object(state, unit, GridObject.Kind.THROWN_SPEAR) != null:
				acts.append("retrieve_spear")
		Unit.Kind.SHIELD:
			acts = ["shield_bash"]
			if unit.shield_deployed:
				if adjacent_object(state, unit, GridObject.Kind.DEPLOYED_SHIELD) != null:
					acts.append("retrieve_shield")
			else:
				acts.append("deploy_shield")
		Unit.Kind.ARTILLERY:
			acts = ["cannon", "mortar"]
	return acts

static func action_label(action_id: String) -> String:
	match action_id:
		"thrust": return "Thrust"
		"punch": return "Punch"
		"throw_spear": return "Throw Spear"
		"retrieve_spear": return "Retrieve Spear"
		"shield_bash": return "Shield Bash"
		"deploy_shield": return "Deploy Shield"
		"retrieve_shield": return "Retrieve Shield"
		"cannon": return "Cannon"
		"mortar": return "Mortar"
	return action_id

# ------------------------------------------------------------- dispatch

static func execute(state: BattleState, unit: Unit, action_id: String, target_cell: Vector2i) -> void:
	match action_id:
		"thrust": _melee(state, unit, target_cell, THRUST_DMG, 1, THRUST_COLLISION)
		"punch": _melee(state, unit, target_cell, PUNCH_DMG, 0, 0)
		"shield_bash": _melee(state, unit, target_cell, BASH_DMG, 1, BASH_COLLISION)
		"throw_spear": _throw_spear(state, unit, target_cell)
		"retrieve_spear": _retrieve_spear(state, unit)
		"deploy_shield": _deploy_shield(state, unit, target_cell)
		"retrieve_shield": _retrieve_shield(state, unit)
		"cannon": _cannon(state, unit, target_cell)
		"mortar": _mortar(state, unit, target_cell)

# ------------------------------------------------------------- resolvers

static func _melee(state: BattleState, unit: Unit, target_cell: Vector2i, damage: int, push_dist: int, collision: int) -> void:
	var target: Unit = state.unit_at(target_cell)
	if target == null:
		return
	var dir: Vector2i = target_cell - unit.pos
	state.events.append({"t": "attack", "id": unit.id, "target": target_cell})
	state.damage_unit(target, damage)
	if push_dist > 0 and target.is_alive():
		var res: Push.Result = Push.resolve(state, target, dir, push_dist, collision)
		state.events.append({"t": "push", "id": target.id, "from": res.start, "to": res.final_pos, "collided": res.collided_with})

static func _throw_spear(state: BattleState, unit: Unit, target_cell: Vector2i) -> void:
	var dir: Vector2i = Grid.cardinal_dir(unit.pos, target_cell)
	var la: Dictionary = state.line_attack(unit.pos, dir, THROW_RANGE)
	var landing: Vector2i = spear_landing_cell(state, unit, dir)
	if la["hit_unit"] != null:
		state.damage_unit(la["hit_unit"], THROW_DMG)
	elif la["hit_reactor"]:
		state.damage_reactor(THROW_DMG)
	unit.has_spear = false
	state.place_object(GridObject.make_spear(landing, unit.id))
	state.events.append({"t": "spear_throw", "id": unit.id, "from": unit.pos, "to": landing})

static func _retrieve_spear(state: BattleState, unit: Unit) -> void:
	var spear: GridObject = adjacent_object(state, unit, GridObject.Kind.THROWN_SPEAR)
	if spear == null:
		return
	state.remove_object_at(spear.pos)
	unit.has_spear = true
	state.events.append({"t": "spear_retrieve", "id": unit.id, "from": spear.pos})

static func _deploy_shield(state: BattleState, unit: Unit, target_cell: Vector2i) -> void:
	unit.shield_deployed = true
	state.place_object(GridObject.make_shield(target_cell, unit.id))
	state.events.append({"t": "shield_deploy", "id": unit.id, "pos": target_cell})

static func _retrieve_shield(state: BattleState, unit: Unit) -> void:
	var shield: GridObject = adjacent_object(state, unit, GridObject.Kind.DEPLOYED_SHIELD)
	if shield == null:
		return
	state.remove_object_at(shield.pos)
	unit.shield_deployed = false
	state.events.append({"t": "shield_retrieve", "id": unit.id, "from": shield.pos})

static func _cannon(state: BattleState, unit: Unit, target_cell: Vector2i) -> void:
	var dir: Vector2i = Grid.cardinal_dir(unit.pos, target_cell)
	var la: Dictionary = state.line_attack(unit.pos, dir, CANNON_RANGE)
	if la["hit_unit"] != null:
		state.damage_unit(la["hit_unit"], CANNON_DMG)
	elif la["hit_reactor"]:
		state.damage_reactor(CANNON_DMG)
	state.events.append({"t": "cannon", "id": unit.id, "from": unit.pos, "cells": la["cells"]})

static func _mortar(state: BattleState, unit: Unit, target_cell: Vector2i) -> void:
	var cells: Array[Vector2i] = state.grid.plus_area(target_cell)
	state.pending_mortars.append({
		"cells": cells,
		"damage": MORTAR_DMG,
		"resolve_on_turn": state.turn_number + 1,
	})
	state.events.append({"t": "mortar_mark", "id": unit.id, "cells": cells})

# ------------------------------------------------------------- shared geometry

## The cell a thrown spear ends up on for direction `dir`: just short of
## whatever it hits, or the last clear cell if it hits nothing. Vector2i(-1,-1)
## if there is nowhere valid to land.
static func spear_landing_cell(state: BattleState, unit: Unit, dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return Vector2i(-1, -1)
	var la: Dictionary = state.line_attack(unit.pos, dir, THROW_RANGE)
	var cells: Array = la["cells"]
	var ideal: Vector2i
	if la["hit_unit"] != null or la["hit_reactor"]:
		ideal = cells[cells.size() - 2] if cells.size() >= 2 else unit.pos
	elif cells.is_empty():
		ideal = unit.pos
	else:
		ideal = cells[cells.size() - 1]
	return _free_cell_near(state, ideal)

static func _free_cell_near(state: BattleState, ideal: Vector2i) -> Vector2i:
	var probes: Array[Vector2i] = [ideal]
	for d: Vector2i in Grid.DIRS:
		probes.append(ideal + d)
	for c: Vector2i in probes:
		if not state.grid.in_bounds(c):
			continue
		if state.grid.is_wall(c):
			continue
		if state.unit_at(c) != null:
			continue
		if state.object_at(c) != null:
			continue
		return c
	return Vector2i(-1, -1)

static func adjacent_object(state: BattleState, unit: Unit, kind: GridObject.Kind) -> GridObject:
	var probes: Array[Vector2i] = [unit.pos]
	for d: Vector2i in Grid.DIRS:
		probes.append(unit.pos + d)
	for c: Vector2i in probes:
		var obj: GridObject = state.object_at(c)
		if obj != null and obj.kind == kind and obj.owner_id == unit.id:
			return obj
	return null
