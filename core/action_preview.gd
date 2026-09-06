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
	var outcome_state: BattleState
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
	if action_id not in MechActions.available_actions(state, unit):
		return out
	match action_id:
		"brace", "engineer_repair":
			out.append(unit.pos)
		"repulsor_plate":
			for d: Vector2i in Grid.DIRS:
				var victim := state.unit_at(unit.pos + d)
				if victim != null and not victim.is_player():
					out.append(victim.pos)
		"tow_cable", "emergency_winch":
			for ally: Unit in state.player_mechs():
				if not MechActions.rescue_dests(state, unit, ally.pos, action_id).is_empty():
					out.append(ally.pos)
		"anchor_shot":
			for d: Vector2i in Grid.DIRS:
				for c: Vector2i in state.line_attack(unit.pos, d, 3).cells:
					if state.unit_at(c) == null and state.object_at(c) == null and not state.grid.is_wall(c):
						out.append(c)
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
		"throw_spear", "impact_spear", "thermal_lance":
			for d: Vector2i in Grid.DIRS:
				for c: Vector2i in state.line_attack(unit.pos, d, MechActions.action_range(action_id))["cells"]:
					out.append(c)
		"grapple":
			# stage-1 "grab" targets: first unit / wall / reactor down each
			# cardinal line, only if it can actually be pulled.
			for d: Vector2i in Grid.DIRS:
				var la: Dictionary = state.line_attack(unit.pos, d, MechActions.GRAPPLE_RANGE)
				var focus: Vector2i = NONE
				if la["hit_unit"] != null or la["hit_reactor"] or (la.get("hit_object") != null and la["hit_object"].kind == GridObject.Kind.ANCHOR):
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
	if target_cell not in valid_targets(state, unit, action_id):
		return p
	var dest: Vector2i = opts.get("dest", MechActions.NO_DEST)
	if action_id == "grapple" and MechActions.grapple_plan(state, unit, target_cell, dest).is_empty():
		return p
	if action_id == "throw" and MechActions.throw_plan(state, unit, target_cell, dest).is_empty():
		return p
	if action_id in ["tow_cable", "emergency_winch"] and MechActions.rescue_plan(state, unit, target_cell, dest, action_id).is_empty():
		return p
	if action_id == "throw_spear":
		p.spear_landing = MechActions.spear_landing_cell(state, unit, Grid.cardinal_dir(unit.pos, target_cell))
		if p.spear_landing == Vector2i(-1, -1):
			return p
	p.valid = true
	p.target_cells = [target_cell]
	if action_id in ["throw_spear", "impact_spear", "thermal_lance", "grapple", "tow_cable", "anchor_shot"]:
		p.line_cells = state.line_attack(unit.pos, Grid.cardinal_dir(unit.pos, target_cell), MechActions.action_range(action_id))["cells"]
	# Run the actual resolver on isolated runtime data. This also models impairment
	# between sequential hits, proc consumption, death before push, and chain blasts.
	var sim := state.simulation_copy()
	var actor: Unit = sim.units[unit.id]
	MechActions.execute(sim, actor, action_id, target_cell, opts)
	p.outcome_state = sim
	for event: Dictionary in sim.events:
		match event.t:
			"damage":
				p._add_hit(state, event.id, event.amount if event.cause == "explosion" else event.get("potential", event.amount), event.pos, true)
			"reactor_damage":
				p.hits_reactor = true
				p.reactor_damage += event.amount
			"displacement":
				p._add_displacement(event.id, event.from, event.to, event.dir, event.collided, event.blocker, event.collision)
				if event.id == unit.id:
					p.mover_id = unit.id
			"explosion":
				for c: Vector2i in event.cells:
					if c not in p.explosion_cells:
						p.explosion_cells.append(c)
	return p
