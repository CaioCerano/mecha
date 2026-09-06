class_name Unit
extends RefCounted

## A single combatant on the grid. Plain data — BattleState owns all mutation.

enum Team { PLAYER, ENEMY }

enum Kind {
	LANCER, BULWARK, GRAPPLER,                     # player mechs
	GRUNT, CHARGER, ARTILLERY_ENEMY, INTERCEPTOR,  # enemies
}

## Charger / enemy-artillery windup state machine.
enum ChargeState { READY, WINDING }

var id: int
var team: Team
var kind: Kind
var pos: Vector2i
var hp: int
var max_hp: int
var move_range: int
var max_ap: int = 2
var ap: int = 0

# Lancer: the spear is in hand until thrown.
var has_spear: bool = true
# Bulwark: shield is stowed (defensive bonus active) until deployed.
var shield_deployed: bool = false
# Charger / enemy-artillery: are we winding up a telegraphed attack?
var charge_state: ChargeState = ChargeState.READY

## Bare unit of a given kind — for menus / labels that need display_name() etc.
## without a live battle unit.
static func new_of(k: Kind) -> Unit:
	var u := Unit.new()
	u.kind = k
	return u

func is_alive() -> bool:
	return hp > 0

func is_player() -> bool:
	return team == Team.PLAYER

## Incoming damage after this unit's own mitigation, BEFORE HP clamping. The
## single source of truth for damage modifiers -- BattleState.damage_unit(),
## ActionPreview and TerrainFx all call this so a preview number always equals
## the executed number. Only modifier today: a stowed Bulwark shrugs off 1.
func mitigate(amount: int, cause: String = "hit") -> int:
	if amount <= 0:
		return 0
	if kind == Kind.BULWARK and not shield_deployed:
		amount = maxi(1, amount - 1)
	if cause == "collision" and has_system("shock_absorbers"):
		amount = maxi(0, amount - 1)
	return amount

func is_mech() -> bool:
	return kind == Kind.LANCER or kind == Kind.BULWARK or kind == Kind.GRAPPLER

func display_name() -> String:
	match kind:
		Kind.LANCER: return "Lancer"
		Kind.BULWARK: return "Bulwark"
		Kind.GRAPPLER: return "Grappler"
		Kind.GRUNT: return "Grunt"
		Kind.CHARGER: return "Charger"
		Kind.ARTILLERY_ENEMY: return "Enemy Artillery"
		Kind.INTERCEPTOR: return "Interceptor"
	return "Unit"

# Build runtime state belongs to this mission's unit, never to menu selections.
var secondary_id: String = "" # empty means frame baseline, including legacy test fixtures
var systems: Array[String] = ["", ""]
var pilot_id: String = ""
var impaired_slot: int = -1
var impairment_triggered: bool = false
var engineer_used: bool = false
var winch_used: bool = false
var thrusters_used: bool = false
var moved_this_turn: int = 0
var ace_used: bool = false
var brawler_used: bool = false
var rescuer_used: bool = false
var suite_used: bool = false
var braced: bool = false

enum DamageState { NORMAL, DAMAGED, CRITICAL, DISABLED }

func secondary() -> String:
	if secondary_id != "":
		return secondary_id
	return SquadLoadout.SECONDARIES.get(kind, [""])[0]

func has_system(id: String) -> bool:
	for i: int in systems.size():
		if systems[i] == id and i != impaired_slot:
			return true
	return false

func damage_state() -> DamageState:
	if hp <= 0:
		return DamageState.DISABLED
	if hp * 4 <= max_hp:
		return DamageState.CRITICAL
	if hp * 2 <= max_hp:
		return DamageState.DAMAGED
	return DamageState.NORMAL

func damage_label() -> String:
	return ["NORMAL", "DAMAGED", "CRITICAL", "DISABLED"][damage_state()]

func movement() -> int:
	return maxi(0, move_range + int(has_system("vector_thrusters") and not thrusters_used) - int(damage_state() == DamageState.CRITICAL))

func push_bonus() -> int:
	return int(has_system("reinforced_actuators")) + int(pilot_id == "ace" and moved_this_turn >= 3 and not ace_used)

func reset_turn() -> void:
	thrusters_used = false
	moved_this_turn = 0
	ace_used = false
	brawler_used = false
	rescuer_used = false
	braced = false
	suite_used = false

func copy() -> Unit:
	var result := Unit.new()
	for property: Dictionary in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = get(property.name)
			result.set(property.name, value.duplicate(true) if value is Array or value is Dictionary else value)
	return result
