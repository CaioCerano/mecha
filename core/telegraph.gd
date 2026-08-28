class_name Telegraph
extends RefCounted

## A pending enemy attack, shown to the player for a full turn before it
## fires. Charger charges and enemy-artillery strikes are both telegraphs.

enum Kind { CHARGE_LINE, AOE }

var kind: Kind
var owner_id: int
var cells: Array[Vector2i] = []      # cells that will be hit / travelled
var damage: int
var resolve_on_turn: int             # enemy turn number on which it fires
var charge_dir: Vector2i = Vector2i.ZERO   # CHARGE_LINE: direction of travel

static func charge(owner_id: int, cells: Array[Vector2i], dir: Vector2i, damage: int, resolve_on_turn: int) -> Telegraph:
	var t := Telegraph.new()
	t.kind = Kind.CHARGE_LINE
	t.owner_id = owner_id
	t.cells = cells
	t.charge_dir = dir
	t.damage = damage
	t.resolve_on_turn = resolve_on_turn
	return t

static func aoe(owner_id: int, cells: Array[Vector2i], damage: int, resolve_on_turn: int) -> Telegraph:
	var t := Telegraph.new()
	t.kind = Kind.AOE
	t.owner_id = owner_id
	t.cells = cells
	t.damage = damage
	t.resolve_on_turn = resolve_on_turn
	return t
