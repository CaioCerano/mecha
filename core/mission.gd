class_name Mission
extends RefCounted

## The one mission: defend the reactor for 5 turns. Every map / spawn / stat
## tunable lives here so iteration is a single-file edit.

const GRID_W: int = 12
const GRID_H: int = 12
const SURVIVE_TURNS: int = 5
const REACTOR_HP: int = 10
const REACTOR_POS: Vector2i = Vector2i(6, 6)

## Wall clusters — kept sparse so positioning still has room to breathe, but
## dense enough that corridors, cover, and push-into-wall combos exist.
static func walls() -> Array[Vector2i]:
	return [
		# top-left chunk
		Vector2i(2, 2), Vector2i(3, 2), Vector2i(2, 3),
		# top-right pillar
		Vector2i(8, 2), Vector2i(9, 2),
		# left corridor wall
		Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8),
		# right corridor wall
		Vector2i(8, 4), Vector2i(8, 5),
		# bottom cover near reactor
		Vector2i(5, 9), Vector2i(6, 9), Vector2i(7, 9),
		# lone blocks
		Vector2i(9, 8), Vector2i(2, 9),
	]

## Enemies enter from these edge cells (cycled through per spawn).
static func spawn_points() -> Array[Vector2i]:
	return [
		Vector2i(0, 0), Vector2i(11, 0), Vector2i(0, 11), Vector2i(11, 11),
		Vector2i(6, 0), Vector2i(0, 6),
	]

## Starting cell for each player mech.
static func mech_starts() -> Dictionary:
	return {
		Unit.Kind.SPEAR: Vector2i(5, 7),
		Unit.Kind.SHIELD: Vector2i(6, 8),
		Unit.Kind.ARTILLERY: Vector2i(7, 7),
	}

## hp / move range per unit kind.
static func unit_stats(kind: Unit.Kind) -> Dictionary:
	match kind:
		Unit.Kind.SPEAR: return {"hp": 6, "move": 4}
		Unit.Kind.SHIELD: return {"hp": 8, "move": 3}
		Unit.Kind.ARTILLERY: return {"hp": 5, "move": 3}
		Unit.Kind.GRUNT: return {"hp": 3, "move": 3}
		Unit.Kind.CHARGER: return {"hp": 4, "move": 3}
		Unit.Kind.ARTILLERY_ENEMY: return {"hp": 3, "move": 2}
	return {"hp": 1, "move": 1}

## Per enemy-turn spawn schedule: turn number -> list of enemy kinds.
## Each entry is assigned a spawn point round-robin.
static func spawn_schedule() -> Dictionary:
	return {
		1: [Unit.Kind.GRUNT, Unit.Kind.GRUNT],
		2: [Unit.Kind.CHARGER],
		3: [Unit.Kind.ARTILLERY_ENEMY, Unit.Kind.GRUNT],
		4: [Unit.Kind.CHARGER],
		5: [Unit.Kind.GRUNT],
	}

## Enemy damage numbers.
const GRUNT_MELEE_DMG: int = 2
const CHARGER_DMG: int = 3
const ENEMY_ARTILLERY_DMG: int = 2
