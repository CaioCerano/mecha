class_name Mission
extends RefCounted

## Shared combat RULES (unit stats, damage numbers, terrain damage) plus the
## factory for the one hand-designed mission. Per-mission LAYOUT lives in the
## MissionData that reactor_breach() returns; BattleState reads that, not these.

# ----------------------------------------------------------------- rules

## hp / move range per unit kind. A rule, not a mission tunable.
static func unit_stats(kind: Unit.Kind) -> Dictionary:
	match kind:
		Unit.Kind.LANCER: return {"hp": 6, "move": 5}
		Unit.Kind.BULWARK: return {"hp": 8, "move": 4}
		Unit.Kind.GRAPPLER: return {"hp": 7, "move": 5}
		Unit.Kind.GRUNT: return {"hp": 3, "move": 3}
		Unit.Kind.CHARGER: return {"hp": 4, "move": 3}
		Unit.Kind.ARTILLERY_ENEMY: return {"hp": 3, "move": 2}
		Unit.Kind.INTERCEPTOR: return {"hp": 4, "move": 4}
	return {"hp": 1, "move": 1}

const GRUNT_MELEE_DMG: int = 3
const CHARGER_DMG: int = 3
const ENEMY_ARTILLERY_DMG: int = 2
const INTERCEPTOR_DMG: int = 2

const PIT_DAMAGE: int = 999      # routed through normal damage handling -> destroys
const EXPLOSIVE_HP: int = 2      # a solid slam (Throw / Bash / Thrust) pops it
const EXPLOSIVE_DMG: int = 3     # dealt to every unit / the reactor in the blast

# ----------------------------------------------------------------- REACTOR BREACH

## The vertical-slice mission. Hand-built to exercise every system:
##  - a north pit under the charge lane (Chargers from (6,0) self-destruct)
##  - a NE pit + wall (Grappler throw-into-pit / wall-slam)
##  - two barrels on approach lanes (slam / Charger self-trigger)
##  - a funnel of walls creating cover, corridors and blocker spots
##  - turn-4 crunch: enemy-artillery AoE on the reactor + a Charger + a new wave
##  - Interceptors that chase the squad while the reactor is under threat
static func reactor_breach() -> MissionData:
	var m := MissionData.new()
	m.id = "reactor_breach"
	m.grid_w = 12
	m.grid_h = 12
	m.reactor_pos = Vector2i(6, 6)
	m.reactor_hp = 12
	m.turn_limit = 5
	m.objective_primary = "Hold the reactor until the end of turn 5"
	m.objective_optional = "Keep all three mechs operational"

	m.walls = [
		# north funnel -- leaves column 6 (rows 1-5) open as the charge->pit lane
		Vector2i(3, 3), Vector2i(4, 3), Vector2i(4, 4),
		Vector2i(8, 3), Vector2i(9, 2),
		# west flank cover / slam surface near the west barrel
		Vector2i(2, 5), Vector2i(2, 6),
		# east flank cover near the east barrel
		Vector2i(9, 5), Vector2i(9, 8),
		# south cover by the mech starts (retreat lanes, slam walls)
		Vector2i(4, 9), Vector2i(8, 9), Vector2i(3, 8),
	]
	m.pits = [
		Vector2i(6, 3),   # north: charges down column 6 fall in; grunts detour around
		Vector2i(9, 3),   # NE: throw / grapple enemies in (wall at (9,2) beside it)
	]
	m.barrels = [
		Vector2i(4, 5),   # NW approach to the reactor -- slam a north/west enemy in
		Vector2i(9, 6),   # east lane -- a Charger from (11,6) self-triggers it
	]

	m.mech_starts = {
		Unit.Kind.LANCER: Vector2i(5, 7),
		Unit.Kind.BULWARK: Vector2i(6, 8),
		Unit.Kind.GRAPPLER: Vector2i(7, 7),
	}
	m.initial_enemies = [
		{"kind": Unit.Kind.GRUNT, "cell": Vector2i(6, 0)},   # north
		{"kind": Unit.Kind.GRUNT, "cell": Vector2i(0, 7)},   # west
	]

	m.spawn_points = [
		Vector2i(6, 0),    # 0: wave-2 CHARGER  -> north pit lane
		Vector2i(11, 6),   # 1: wave-2 ARTILLERY -> in AoE range immediately
		Vector2i(0, 6),    # 2: wave-3 GRUNT
		Vector2i(11, 0),   # 3: wave-3 INTERCEPTOR (long approach -> squad pressure ~turn 5)
		Vector2i(11, 6),   # 4: wave-4 CHARGER  -> east barrel lane
		Vector2i(0, 0),    # 5: wave-4 GRUNT
		Vector2i(6, 11),   # 6: wave-4 INTERCEPTOR
		Vector2i(0, 11),
	]
	m.spawn_schedule = {
		2: [Unit.Kind.CHARGER, Unit.Kind.ARTILLERY_ENEMY],
		3: [Unit.Kind.GRUNT, Unit.Kind.INTERCEPTOR],
		4: [Unit.Kind.CHARGER, Unit.Kind.GRUNT, Unit.Kind.INTERCEPTOR],
	}
	return m
