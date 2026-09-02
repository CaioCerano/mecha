class_name MissionData
extends RefCounted

## One hand-designed tactical mission, as plain data. NOT a campaign format --
## just the layout + schedule + objective text for a single encounter, so a
## mission can be defined without hardcoding it into BattleState. Rules
## constants (unit stats, damage numbers, terrain damage) live in Mission /
## the enemy AI, not here -- those are shared, not per-mission.

var id: String = "mission"

# --- map ---
var grid_w: int = 12
var grid_h: int = 12
var walls: Array[Vector2i] = []
var pits: Array[Vector2i] = []
var barrels: Array[Vector2i] = []
var reactor_pos: Vector2i = Vector2i(6, 6)
var reactor_hp: int = 12

# --- units ---
var mech_starts: Dictionary = {}          # Unit.Kind -> Vector2i
var initial_enemies: Array = []           # [{ kind: Unit.Kind, cell: Vector2i }]

# --- reinforcements ---
## edge cells, cycled round-robin as waves are announced.
var spawn_points: Array[Vector2i] = []
## player-phase turn number -> Array[Unit.Kind]. Announced at the top of that
## player phase, enters that enemy phase, first acts the enemy phase after.
var spawn_schedule: Dictionary = {}

# --- objective / end conditions ---
var turn_limit: int = 5
var objective_primary: String = "Hold the reactor"
var objective_optional: String = ""       # "" == this mission has none
var defeat_if_reactor_destroyed: bool = true
var defeat_if_squad_lost: bool = true
## victory is always "survive `turn_limit` enemy phases with the reactor alive"
## for this prototype -- the only mode BattleState._check_end implements.
