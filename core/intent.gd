class_name Intent
extends RefCounted

## "If the player does this action, what changes about the enemy turn?"
##
## The one shared place that answers it, for every deterministic enemy plan:
##  - CHARGE_LINE telegraphs (charger)
##  - Grunt movement + target
##  - Interceptor pursuit + target
##
## Projection re-runs the SAME planners execution uses (EnemyAi.plan_for,
## _charge_outcome) against a hypothetical board -- moves the player action
## would cause, extra blockers (a deployed shield), and enemies the action
## destroys -- so a projected outcome equals the real enemy turn on that board.
## AoE (enemy-artillery) telegraphs are locked to the reactor and not projected.

class Change:
	extends RefCounted
	var owner_id: int
	var kind: String = ""                        # "charge" | "grunt" | "interceptor"
	var original_path: Array[Vector2i] = []      # charge lane OR walk path (incl. start cell)
	var projected_path: Array[Vector2i] = []
	var original_dest: Vector2i = Vector2i(-1, -1)
	var projected_dest: Vector2i = Vector2i(-1, -1)
	var original_target: int = -2               # -2 none, -1 reactor, else unit id
	var projected_target: int = -2
	var original_target_cell: Vector2i = Vector2i(-1, -1)
	var projected_target_cell: Vector2i = Vector2i(-1, -1)
	var original_damage: int = 0
	var projected_damage: int = 0
	var interrupted: bool = false                # was threatening a mech/reactor, now isn't
	var redirected: bool = false                 # now attacks a DIFFERENT valid target
	var destroyed: bool = false                  # the owner itself is wiped -> no future action
	var safe_cell: Vector2i = Vector2i(-1, -1)   # the freed mech/reactor cell to mark SAFE
	var newly_threatened_cell: Vector2i = Vector2i(-1, -1)

## `moves`    : unit_id -> hypothetical position after the previewed action.
## `blockers` : cells that become move-solid (e.g. a deploy-shield tile).
## `removed`  : unit_id -> true for enemies the previewed action destroys.
static func project(state: BattleState, moves: Dictionary = {}, blockers: Array = [], removed: Dictionary = {}) -> Array:
	var hypo: Dictionary = {"moves": moves, "blockers": blockers, "removed": removed}
	var out: Array = []

	# -------- telegraphed charges --------
	for tg: Telegraph in state.telegraphs:
		if tg.kind != Telegraph.Kind.CHARGE_LINE:
			continue
		var owner: Unit = state.units.get(tg.owner_id)
		if owner == null or not owner.is_alive():
			continue
		var orig: Dictionary = charge_outcome(state, owner.pos, tg.charge_dir, {}, [])
		if removed.get(owner.id, false):
			var chd := Change.new()
			chd.owner_id = owner.id
			chd.kind = "charge"
			chd.destroyed = true
			chd.original_path = orig["cells"]
			chd.original_target = orig["target"]
			if orig["target"] == -1 or _is_mech(state, orig["target"]):
				chd.interrupted = true
				chd.safe_cell = _cell_of(state, orig["target"])
			out.append(chd)
			continue
		var opos: Vector2i = moves.get(owner.id, owner.pos)
		var proj: Dictionary = charge_outcome(state, opos, tg.charge_dir, moves, blockers)
		if orig["cells"] == proj["cells"] and orig["target"] == proj["target"] and orig["pit"] == proj["pit"]:
			continue
		var ch := Change.new()
		ch.owner_id = owner.id
		ch.kind = "charge"
		ch.original_path = orig["cells"]
		ch.projected_path = proj["cells"]
		ch.original_dest = orig["stop"]
		ch.projected_dest = proj["stop"]
		ch.original_target = orig["target"]
		ch.projected_target = proj["target"]
		ch.original_target_cell = _cell_of(state, orig["target"])
		ch.projected_target_cell = _cell_of(state, proj["target"])
		ch.original_damage = tg.damage if orig["target"] != -2 else 0
		ch.projected_damage = tg.damage if proj["target"] != -2 else 0
		ch.destroyed = proj["pit"]                     # the player's action sends it into a pit
		var was_threat: bool = orig["target"] == -1 or _is_mech(state, orig["target"])
		if (was_threat and proj["target"] != orig["target"]) or proj["pit"]:
			ch.interrupted = true
			ch.safe_cell = _cell_of(state, orig["target"])
		if orig["target"] != proj["target"] and proj["target"] != -2:
			ch.redirected = true
			ch.newly_threatened_cell = _cell_of(state, proj["target"])
		out.append(ch)

	# -------- deterministic movers (grunt / interceptor, no telegraph) --------
	for u: Unit in state.living_enemies():
		if not EnemyAi.plans_movement(u.kind):
			continue
		if _has_telegraph(state, u.id):
			continue
		var op: EnemyAi.EnemyPlan = EnemyAi.plan_for(state, u, {})
		var pp: EnemyAi.EnemyPlan = EnemyAi.plan_for(state, u, hypo)
		if _plans_equal(op, pp):
			continue
		var ch := Change.new()
		ch.owner_id = u.id
		ch.kind = "grunt" if u.kind == Unit.Kind.GRUNT else "interceptor"
		ch.original_path = _walk(op)
		ch.projected_path = _walk(pp)
		ch.original_dest = op.dest
		ch.projected_dest = pp.dest
		ch.original_target = _tgt(op)
		ch.projected_target = _tgt(pp)
		ch.original_target_cell = op.target_cell
		ch.projected_target_cell = pp.target_cell
		ch.original_damage = op.damage if op.will_attack else 0
		ch.projected_damage = pp.damage if pp.will_attack else 0
		ch.destroyed = pp.destroyed
		var was: bool = op.will_attack
		var still: bool = pp.will_attack and _tgt(pp) == _tgt(op)
		if was and not still:
			ch.interrupted = true
			ch.safe_cell = op.target_cell
		if op.will_attack and pp.will_attack and _tgt(op) != _tgt(pp):
			ch.redirected = true
			ch.newly_threatened_cell = pp.target_cell
		out.append(ch)

	return out

# ------------------------------------------------------------------- helpers

static func _plans_equal(a: EnemyAi.EnemyPlan, b: EnemyAi.EnemyPlan) -> bool:
	return a.destroyed == b.destroyed and a.path == b.path and a.dest == b.dest \
		and a.will_attack == b.will_attack and _tgt(a) == _tgt(b)

static func _walk(p: EnemyAi.EnemyPlan) -> Array[Vector2i]:
	var out: Array[Vector2i] = [p.from]
	out.append_array(p.path)
	return out

static func _tgt(p: EnemyAi.EnemyPlan) -> int:
	if not p.will_attack:
		return -2
	return -1 if p.target_kind == "reactor" else p.target_id

static func _cell_of(state: BattleState, t: int) -> Vector2i:
	if t == -1:
		return state.reactor.pos
	if t >= 0:
		var u: Unit = state.units.get(t)
		return u.pos if u != null else Vector2i(-1, -1)
	return Vector2i(-1, -1)

static func _is_mech(state: BattleState, id: int) -> bool:
	var u: Unit = state.units.get(id)
	return u != null and u.is_player()

static func _has_telegraph(state: BattleState, owner_id: int) -> bool:
	for tg: Telegraph in state.telegraphs:
		if tg.owner_id == owner_id:
			return true
	return false

## THE charge geometry -- BattleState._resolve_telegraph and this projection
## both call it. Slide from `origin` along `dir` until the first solid thing,
## honouring hypothetical `moves` + `blockers`; a pit swallows the charger.
## Returns { cells, stop (final cell), target (-2 none / -1 reactor / unit id),
##           pit (charger self-destructs) }.
static func charge_outcome(state: BattleState, origin: Vector2i, dir: Vector2i,
		moves: Dictionary, blockers: Array) -> Dictionary:
	var occ: Dictionary[Vector2i, int] = {}
	for id: int in state.units:
		var u: Unit = state.units[id]
		if u.is_alive():
			occ[moves.get(id, u.pos)] = id
	var cells: Array[Vector2i] = []
	var cur: Vector2i = origin
	for _i: int in range(EnemyAi.CHARGER_RANGE):
		var nxt: Vector2i = cur + dir
		if not state.grid.in_bounds(nxt) or state.grid.is_wall(nxt):
			break
		if nxt in blockers or occ.has(nxt):
			break
		var obj: GridObject = state.object_at(nxt)
		if obj != null and obj.is_hazard():
			cells.append(nxt)
			cur = nxt
			return {"cells": cells, "stop": cur, "target": -2, "pit": true}
		if obj != null and obj.blocks_forced_move():
			break
		cells.append(nxt)
		cur = nxt
	var ahead: Vector2i = cur + dir
	var target: int = -2
	if occ.has(ahead):
		target = occ[ahead]
	elif state.reactor.pos == ahead:
		target = -1
	return {"cells": cells, "stop": cur, "target": target, "pit": false}
