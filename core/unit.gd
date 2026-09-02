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

func is_alive() -> bool:
	return hp > 0

func is_player() -> bool:
	return team == Team.PLAYER

## Incoming damage after this unit's own mitigation, BEFORE HP clamping. The
## single source of truth for damage modifiers -- BattleState.damage_unit(),
## ActionPreview and TerrainFx all call this so a preview number always equals
## the executed number. Only modifier today: a stowed Bulwark shrugs off 1.
func mitigate(amount: int) -> int:
	if kind == Kind.BULWARK and not shield_deployed:
		return maxi(1, amount - 1)
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
