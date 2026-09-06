class_name GridObject
extends RefCounted

## Anything that occupies a cell and isn't a unit: the thrown spear, a deployed
## shield, the reactor, and the environmental terrain -- pits and explosive
## barrels. Walls stay in Grid (pure static geometry); everything else is data
## here, queried through capability predicates so combat code never has to ask
## "is this cell a barrel".

enum Kind { THROWN_SPEAR, DEPLOYED_SHIELD, REACTOR, PIT, EXPLOSIVE, ANCHOR }

var kind: Kind
var pos: Vector2i
var owner_id: int = -1   # spear / shield: the mech it belongs to
var hp: int = 0          # reactor / explosive
var max_hp: int = 0

static func make_spear(pos: Vector2i, owner_id: int) -> GridObject:
	return _mk(Kind.THROWN_SPEAR, pos, owner_id, 0)

static func make_shield(pos: Vector2i, owner_id: int) -> GridObject:
	return _mk(Kind.DEPLOYED_SHIELD, pos, owner_id, 0)

static func make_reactor(pos: Vector2i, hp: int) -> GridObject:
	return _mk(Kind.REACTOR, pos, -1, hp)

static func make_pit(pos: Vector2i) -> GridObject:
	return _mk(Kind.PIT, pos, -1, 0)

static func make_explosive(pos: Vector2i, hp: int) -> GridObject:
	return _mk(Kind.EXPLOSIVE, pos, -1, hp)

static func _mk(kind: Kind, pos: Vector2i, owner_id: int, hp: int) -> GridObject:
	var o := GridObject.new()
	o.kind = kind
	o.pos = pos
	o.owner_id = owner_id
	o.hp = hp
	o.max_hp = hp
	return o

# ------------------------------------------------------------- capabilities

## Voluntary movement / pathfinding cannot enter this cell.
func blocks_move() -> bool:
	return kind == Kind.DEPLOYED_SHIELD or kind == Kind.REACTOR \
		or kind == Kind.PIT or kind == Kind.EXPLOSIVE

## A forced-movement slide (Push / charge) stops in the cell BEFORE this one.
## Pits are the exception: forced movement can send a unit into a pit.
func blocks_forced_move() -> bool:
	return kind == Kind.DEPLOYED_SHIELD or kind == Kind.REACTOR or kind == Kind.EXPLOSIVE or kind == Kind.ANCHOR

## Stops ranged line attacks (thrown spear, grapple line).
func blocks_line() -> bool:
	return kind == Kind.REACTOR or kind == Kind.EXPLOSIVE or kind == Kind.ANCHOR

## Entering this cell (only possible via forced movement) triggers a hazard.
func is_hazard() -> bool:
	return kind == Kind.PIT

func hazard_damage() -> int:
	return Mission.PIT_DAMAGE if kind == Kind.PIT else 0

## Slamming a unit into this deals the shared collision damage to that unit.
func is_collision_surface() -> bool:
	return kind == Kind.DEPLOYED_SHIELD or kind == Kind.REACTOR or kind == Kind.EXPLOSIVE or kind == Kind.ANCHOR

## Has HP and can be broken by damage / collisions.
func is_destructible() -> bool:
	return kind == Kind.EXPLOSIVE

func is_alive() -> bool:
	if kind == Kind.REACTOR:
		return hp > 0
	if kind == Kind.EXPLOSIVE:
		return hp > 0
	return true
