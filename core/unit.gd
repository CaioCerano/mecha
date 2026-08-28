class_name Unit
extends RefCounted

## A single combatant on the grid. Plain data — BattleState owns all mutation.

enum Team { PLAYER, ENEMY }

enum Kind {
	SPEAR, SHIELD, ARTILLERY,          # player mechs
	GRUNT, CHARGER, ARTILLERY_ENEMY,   # enemies
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

# Spear mech: the spear is in hand until thrown.
var has_spear: bool = true
# Shield mech: shield is stowed (defensive bonus active) until deployed.
var shield_deployed: bool = false
# Charger / enemy-artillery: are we winding up a telegraphed attack?
var charge_state: ChargeState = ChargeState.READY

func is_alive() -> bool:
	return hp > 0

func is_player() -> bool:
	return team == Team.PLAYER

func is_mech() -> bool:
	return kind == Kind.SPEAR or kind == Kind.SHIELD or kind == Kind.ARTILLERY

func display_name() -> String:
	match kind:
		Kind.SPEAR: return "Spear"
		Kind.SHIELD: return "Shield"
		Kind.ARTILLERY: return "Artillery"
		Kind.GRUNT: return "Grunt"
		Kind.CHARGER: return "Charger"
		Kind.ARTILLERY_ENEMY: return "Enemy Artillery"
	return "Unit"
