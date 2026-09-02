class_name ActionPreview
extends RefCounted

## Pure, side-effect-free description of what an action would do from a given
## target cell. The battle scene renders this before the player commits, and
## BattleState.player_action() uses `.valid` as the legality gate. Geometry
## is delegated to MechActions / BattleState / Push so preview == execution.
##
## The view layer should read this and visualize it, never recompute combat.

const NONE: Vector2i = Vector2i(-9999, -9999)

class Preview:
	extends RefCounted
	var valid: bool = false
	var target_cells: Array[Vector2i] = []   # the cell(s) the player is aiming at
	var line_cells: Array[Vector2i] = []     # attack / tether lane travelled
	var aoe_cells: Array[Vector2i] = []      # area of effect
	var spear_landing: Vector2i = ActionPreview.NONE

	## Structured outcome — what the view should draw.
	var hits: Array[Dictionary] = []          # [{id, cell, amount, lethal}]
	var displacements: Array[Dictionary] = [] # [{id, from, to, dir, collided, collision_cell, collision_amount}]
	var explosion_cells: Array[Vector2i] = [] # blast tiles if this action pops a barrel
	var mover_id: int = -1                    # unit that repositions ITSELF (grapple-to-anchor); -1 if none
	var reactor_damage: int = 0
	var hits_reactor: bool = false

	## Legacy convenience mirrors (first displacement / affected id list).
	var push_from: Vector2i = ActionPreview.NONE
	var push_to: Vector2i = ActionPreview.NONE
	var affected_ids: Array[int] = []

	## `pre_mitigated` : the amount already went through Unit.mitigate() (e.g. a
	## TerrainFx explosion total) -- don't run it again.
	func _add_hit(state: BattleState, id: int, amount: int, cell_override: Vector2i = ActionPreview.NONE,
			pre_mitigated: bool = false) -> void:
		var u: Unit = state.units.get(id)
		if u == null:
			return
		var eff: int = amount if pre_mitigated else u.mitigate(amount)
		if eff <= 0:
			return
		var at: Vector2i = cell_override if cell_override != ActionPreview.NONE else u.pos
		for h: Dictionary in hits:
			if h["id"] == id:
				h["amount"] += eff
				h["lethal"] = h["amount"] >= u.hp
				h["cell"] = at
				return
		hits.append({"id": id, "cell": at, "amount": eff, "lethal": eff >= u.hp})
		if not id in affected_ids:
			affected_ids.append(id)

	func _damage_so_far() -> Dictionary:
		var out: Dictionary = {}
		for h: Dictionary in hits:
			out[h["id"]] = out.get(h["id"], 0) + int(h["amount"])
		return out

	func _add_displacement(id: int, from: Vector2i, to: Vector2i, dir: Vector2i,
			collided: String, collision_cell: Vector2i, collision_amount: int) -> void:
		displacements.append({
			"id": id, "from": from, "to": to, "dir": dir,
			"collided": collided, "collision_cell": collision_cell,
			"collision_amount": collision_amount,
		})
		if push_from == ActionPreview.NONE:
			push_from = from
			push_to = to
		if not id in affected_ids:
			affected_ids.append(id)

## Every cell the player is allowed to click for this action right now.
static func valid_targets(state: BattleState, unit: Unit, action_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match action_id:
		"thrust", "punch", "shield_bash":
			for d: Vector2i in Grid.DIRS:
				var c: Vector2i = unit.pos + d
				if state.unit_at(c) != null:
					out.append(c)
		"throw":
			# stage-1 "grab" targets: adjacent units that can be thrown somewhere
			for d: Vector2i in Grid.DIRS:
				var c: Vector2i = unit.pos + d
				if state.unit_at(c) != null and not MechActions.throw_dests(state, unit, c).is_empty():
					out.append(c)
		"throw_spear":
			for d: Vector2i in Grid.DIRS:
				for c: Vector2i in state.line_attack(unit.pos, d, MechActions.THROW_RANGE)["cells"]:
					out.append(c)
		"grapple":
			# stage-1 "grab" targets: first unit / wall / reactor down each
			# cardinal line, only if it can actually be pulled.
			for d: Vector2i in Grid.DIRS:
				var la: Dictionary = state.line_attack(unit.pos, d, MechActions.GRAPPLE_RANGE)
				var focus: Vector2i = NONE
				if la["hit_unit"] != null or la["hit_reactor"]:
					focus = la["hit_pos"]
				elif la["blocked_by_wall"]:
					focus = unit.pos + d * (la["cells"].size() + 1)
				if focus != NONE and not MechActions.grapple_dests(state, unit, focus).is_empty():
					out.append(focus)
		"deploy_shield":
			for d: Vector2i in Grid.DIRS:
				var c: Vector2i = unit.pos + d
				if state.grid.in_bounds(c) and not state.grid.is_wall(c) \
						and state.unit_at(c) == null and state.object_at(c) == null:
					out.append(c)
		"retrieve_spear":
			var s: GridObject = MechActions.adjacent_object(state, unit, GridObject.Kind.THROWN_SPEAR)
			if s != null:
				out.append(s.pos)
		"retrieve_shield":
			var s: GridObject = MechActions.adjacent_object(state, unit, GridObject.Kind.DEPLOYED_SHIELD)
			if s != null:
				out.append(s.pos)
	return out

## `opts["dest"]` is the player's stage-2 destination for Grapple / Throw.
static func build(state: BattleState, unit: Unit, action_id: String, target_cell: Vector2i, opts: Dictionary = {}) -> Preview:
	var p := Preview.new()
	if not target_cell in valid_targets(state, unit, action_id):
		return p
	p.valid = true
	var dest: Vector2i = opts.get("dest", MechActions.NO_DEST)

	match action_id:
		"thrust", "shield_bash", "punch":
			p.target_cells = [target_cell]
			var victim: Unit = state.unit_at(target_cell)
			if victim == null:
				return p
			p._add_hit(state, victim.id, MechActions.action_damage(action_id))
			var push_dist: int = MechActions.melee_push(action_id)
			if push_dist > 0:
				_apply_push(state, p, victim, target_cell - unit.pos, push_dist,
					MechActions.action_collision(action_id))
		"throw":
			p.target_cells = [target_cell]
			var plan: Dictionary = MechActions.throw_plan(state, unit, target_cell, dest)
			if plan.is_empty():
				p.valid = false
				return p
			_apply_command(state, p, plan)
		"grapple":
			p.target_cells = [target_cell]
			var gdir: Vector2i = Grid.cardinal_dir(unit.pos, target_cell)
			p.line_cells = state.line_attack(unit.pos, gdir, MechActions.GRAPPLE_RANGE)["cells"]
			var gplan: Dictionary = MechActions.grapple_plan(state, unit, target_cell, dest)
			if gplan.is_empty():
				p.valid = false
				return p
			if gplan["is_self"]:
				p.mover_id = unit.id
			_apply_command(state, p, gplan)
		"throw_spear":
			var dir3: Vector2i = Grid.cardinal_dir(unit.pos, target_cell)
			var la2: Dictionary = state.line_attack(unit.pos, dir3, MechActions.THROW_RANGE)
			p.line_cells = la2["cells"]
			p.target_cells = [target_cell]
			if la2["hit_unit"] != null:
				p._add_hit(state, la2["hit_unit"].id, MechActions.THROW_DMG)
			elif la2["hit_reactor"]:
				p.hits_reactor = true
				p.reactor_damage = MechActions.THROW_DMG
			elif la2.get("hit_object") != null and la2["hit_object"].is_destructible():
				var bo: GridObject = la2["hit_object"]
				if bo.hp - MechActions.THROW_DMG <= 0:
					_add_explosion(state, p, [bo.pos], {})
			p.spear_landing = MechActions.spear_landing_cell(state, unit, dir3)
			if p.spear_landing == Vector2i(-1, -1):
				p.valid = false
		"deploy_shield":
			p.target_cells = [target_cell]
		"retrieve_spear", "retrieve_shield":
			p.target_cells = [target_cell]
	return p

## Trace a forced move and record the displacement + consequences, mirroring
## Push.resolve exactly. `collision_dmg` is the hard-stop damage this action
## deals (0 for a damage-free shove). Also predicts pit destruction and barrel
## chain explosions.
static func _apply_push(state: BattleState, p: Preview,
		victim: Unit, dir: Vector2i, dist: int, collision_dmg: int) -> void:
	var t: Dictionary = Push.trace(state, victim.pos, dir, dist)
	if t["hazard"] == "pit":
		p._add_displacement(victim.id, victim.pos, t["final"], dir, "hazard", t["blocker"], 0)
		p._add_hit(state, victim.id, Mission.PIT_DAMAGE, t["final"])   # lethal
		return
	var col: int = collision_dmg if t["collided"] != "none" else 0
	p._add_displacement(victim.id, victim.pos, t["final"], dir, t["collided"], t["blocker"], col)
	if col > 0:
		p._add_hit(state, victim.id, col)
		if t["collided"] == "unit":
			var slammed: Unit = state.unit_at(t["blocker"])
			if slammed != null:
				p._add_hit(state, slammed.id, col)
		elif t["collided"] == "object":
			var obj: GridObject = state.object_at(t["blocker"])
			if obj != null and obj.is_destructible() and obj.hp - col <= 0:
				_add_explosion(state, p, [obj.pos], {victim.id: t["final"]}, p._damage_so_far())

## Merge a predicted (chain) explosion into the preview.
static func _add_explosion(state: BattleState, p: Preview, barrels: Array,
		unit_pos_override: Dictionary, damage_so_far: Dictionary = {}) -> void:
	var ep: Dictionary = TerrainFx.explosion_plan(state, barrels, unit_pos_override, damage_so_far)
	for bc: Vector2i in ep["blast"]:
		if not bc in p.explosion_cells:
			p.explosion_cells.append(bc)
	for h: Dictionary in ep["hits"]:
		var at: Vector2i = unit_pos_override.get(h["id"], MechActions.NO_DEST)
		p._add_hit(state, h["id"], h["amount"], at, true)   # explosion_plan already mitigated
	if ep["reactor_dmg"] > 0:
		p.hits_reactor = true
		p.reactor_damage += ep["reactor_dmg"]

## Same, driven by a displacement command {entity, dir, dist, collision}.
static func _apply_command(state: BattleState, p: Preview, plan: Dictionary) -> void:
	var e: Unit = state.units.get(plan["entity"])
	if e == null:
		p.valid = false
		return
	_apply_push(state, p, e, plan["dir"], plan["dist"], int(plan["collision"]))
