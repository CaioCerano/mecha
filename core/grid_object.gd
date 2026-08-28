class_name GridObject
extends RefCounted

## Non-unit things that occupy a cell: the thrown spear, a deployed shield,
## and the reactor the player is defending.

enum Kind { THROWN_SPEAR, DEPLOYED_SHIELD, REACTOR }

var kind: Kind
var pos: Vector2i
var owner_id: int = -1   # spear / shield: the mech it belongs to
var hp: int = 0          # reactor only
var max_hp: int = 0      # reactor only

static func make_spear(pos: Vector2i, owner_id: int) -> GridObject:
	var o := GridObject.new()
	o.kind = Kind.THROWN_SPEAR
	o.pos = pos
	o.owner_id = owner_id
	return o

static func make_shield(pos: Vector2i, owner_id: int) -> GridObject:
	var o := GridObject.new()
	o.kind = Kind.DEPLOYED_SHIELD
	o.pos = pos
	o.owner_id = owner_id
	return o

static func make_reactor(pos: Vector2i, hp: int) -> GridObject:
	var o := GridObject.new()
	o.kind = Kind.REACTOR
	o.pos = pos
	o.hp = hp
	o.max_hp = hp
	return o

## Blocks unit movement and pathfinding.
func blocks_move() -> bool:
	return kind == Kind.DEPLOYED_SHIELD or kind == Kind.REACTOR

## Stops line attacks (cannon, thrown spear, enemy charge).
func blocks_line() -> bool:
	return kind == Kind.DEPLOYED_SHIELD or kind == Kind.REACTOR

func is_alive() -> bool:
	return kind != Kind.REACTOR or hp > 0
