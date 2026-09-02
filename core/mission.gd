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

# ----------------------------------------------------------------- mission registry

## Every hand-designed mission, by id. NOT a campaign -- just the set the dev
## mission picker can launch. BattleState.new(Mission.by_id(x)) starts one.
const REACTOR_BREACH: String = "reactor_breach"
const THE_CHOKEPOINT: String = "the_chokepoint"

## id -> short label, in menu order. The picker reads this.
static func catalog() -> Array:
	return [
		{"id": REACTOR_BREACH, "name": "Reactor Breach"},
		{"id": THE_CHOKEPOINT, "name": "The Chokepoint"},
	]

static func ids() -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in catalog():
		out.append(e["id"])
	return out

static func display_name(id: String) -> String:
	for e: Dictionary in catalog():
		if e["id"] == id:
			return e["name"]
	return id

## Build a fresh MissionData for `id`. Unknown -> the default slice.
static func by_id(id: String) -> MissionData:
	match id:
		THE_CHOKEPOINT: return the_chokepoint()
		_: return reactor_breach()

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
	m.id = REACTOR_BREACH
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

# ----------------------------------------------------------------- THE CHOKEPOINT

## The second hand-designed slice. Same 12x12 board, same 5-turn hold, same
## enemy roster minus the Artillery -- but a completely different SHAPE: one
## east-west divider wall splits the map into a northern muster field and the
## reactor's half, joined by THREE two-wide gaps. Three mechs, three lanes:
## the mission does not let you out-damage one lane in peace.
##
##  - WEST gap (cols 1-2), CENTRE gap (cols 6-7), EAST gap (cols 10-11). Each is
##    two wide, so one body / one deployed shield narrows a lane but never seals
##    it -- there is no single tile that wins the mission.
##  - CENTRE is the dangerous lane: a clean straight line from the north edge to
##    the reactor, and both reinforcement Chargers come down it. A Charger that
##    is not dealt with hits the reactor.
##  - Two PITS on the centre lane's shoulders ((5,5) / (7,5)): nothing falls in
##    on its own -- shove / grapple a centre enemy one tile sideways for an
##    instant kill. Displacement clearly beats chipping 3 off a 4-HP Charger.
##  - Two BARRELS beside the reactor's south approach ((5,7) / (7,7)): pop one
##    to clear a cluster hitting the reactor from the flank -- but a mech start
##    tile sits in each blast, so it costs you tempo to set up safely.
##  - Chamber nubs ((4,6)(4,7) / (8,6)(8,7)) stop the flank lanes from cutting
##    straight across into the reactor; flankers have to come around, which is
##    the window for Lancer to range over from the open south, for Bulwark to
##    bash one into a nub, for Grappler to reel one off its line.
##  - Two Interceptors (waves 3 & 4) ignore the reactor and pull a mech off
##    station -- you cannot leave all three planted on their gaps.
static func the_chokepoint() -> MissionData:
	var m := MissionData.new()
	m.id = THE_CHOKEPOINT
	m.grid_w = 12
	m.grid_h = 12
	m.reactor_pos = Vector2i(6, 6)
	m.reactor_hp = 12
	m.turn_limit = 5
	m.objective_primary = "Hold the reactor until the end of turn 5"
	m.objective_optional = "Keep all three mechs operational"

	m.walls = [
		# the divider -- gaps at cols 2-3 (west), cols 6-7 (centre), cols 8-9 (east)
		Vector2i(0, 4), Vector2i(1, 4), Vector2i(4, 4), Vector2i(5, 4),
		Vector2i(10, 4), Vector2i(11, 4),
		# reactor chamber -- one nub W and E of the reactor so a flank lane can't
		# slide straight in along row 6
		Vector2i(4, 6), Vector2i(8, 6),
	]
	m.pits = [
		Vector2i(5, 5),   # NW shoulder of the centre lane -- shove a centre enemy in
		Vector2i(7, 5),   # NE shoulder of the centre lane
	]
	m.barrels = [
		Vector2i(5, 7),   # SW of the reactor, by its (5,6)/(6,7) approach cells
		Vector2i(7, 7),   # SE of the reactor, by its (7,6)/(6,7) approach cells
	]

	m.mech_starts = {
		Unit.Kind.LANCER: Vector2i(3, 9),     # SW -- ranges across the open south
		Unit.Kind.BULWARK: Vector2i(6, 8),    # dead centre, forward -- holds the choke
		Unit.Kind.GRAPPLER: Vector2i(9, 9),   # SE -- reels flankers off line
	}
	m.initial_enemies = [
		{"kind": Unit.Kind.GRUNT, "cell": Vector2i(6, 2)},   # centre lane -- fast
		{"kind": Unit.Kind.GRUNT, "cell": Vector2i(2, 2)},   # west lane
		{"kind": Unit.Kind.GRUNT, "cell": Vector2i(9, 2)},   # east lane -- all three live turn 1
	]

	# cycled round-robin as waves are announced (see schedule order below)
	m.spawn_points = [
		Vector2i(6, 0),    # 0: wave-2 CHARGER     -> centre lane
		Vector2i(0, 6),    # 1: wave-2 GRUNT       -> west lane
		Vector2i(11, 6),   # 2: wave-2 GRUNT       -> east lane
		Vector2i(6, 0),    # 3: wave-3 CHARGER     -> centre lane again
		Vector2i(11, 6),   # 4: wave-3 INTERCEPTOR -> east, hunts a mech
		Vector2i(0, 6),    # 5: wave-4 GRUNT       -> west lane
		Vector2i(6, 0),    # 6: wave-4 GRUNT       -> centre lane
		Vector2i(0, 6),    # 7: wave-4 INTERCEPTOR -> west, hunts a mech
	]
	m.spawn_schedule = {
		2: [Unit.Kind.CHARGER, Unit.Kind.GRUNT, Unit.Kind.GRUNT],
		3: [Unit.Kind.CHARGER, Unit.Kind.INTERCEPTOR],
		4: [Unit.Kind.GRUNT, Unit.Kind.GRUNT, Unit.Kind.INTERCEPTOR],
	}
	return m
