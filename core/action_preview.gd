class_name ActionPreview
extends RefCounted

## Pure, side-effect-free description of what an action would do from a given
## target cell. The battle scene renders this before the player commits, and
## BattleState.player_action() uses `.valid` as the legality gate. Geometry
## is delegated to MechActions / BattleState so preview == execution.

const NONE: Vector2i = Vector2i(-9999, -9999)

class Preview:
	extends RefCounted
	var valid: bool = false
	var target_cells: Array[Vector2i] = []   # the cell(s) the player is aiming at
	var line_cells: Array[Vector2i] = []     # attack line travelled
	var aoe_cells: Array[Vector2i] = []      # area of effect
	var push_from: Vector2i = ActionPreview.NONE
	var push_to: Vector2i = ActionPreview.NONE
	var spear_landing: Vector2i = ActionPreview.NONE
	var affected_ids: Array[int] = []        # units that would be hit
	var hits_reactor: bool = false

## Every cell the player is allowed to click for this action right now.
static func valid_targets(state: BattleState, unit: Unit, action_id: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match action_id:
		"thrust", "punch", "shield_bash":
			for d: Vector2i in Grid.DIRS:
				var c: Vector2i = unit.pos + d
				if state.unit_at(c) != null:
					out.append(c)
		"throw_spear":
			for d: Vector2i in Grid.DIRS:
				for c: Vector2i in state.line_attack(unit.pos, d, MechActions.THROW_RANGE)["cells"]:
					out.append(c)
		"cannon":
			for d: Vector2i in Grid.DIRS:
				for c: Vector2i in state.line_attack(unit.pos, d, MechActions.CANNON_RANGE)["cells"]:
					out.append(c)
		"deploy_shield":
			for d: Vector2i in Grid.DIRS:
				var c: Vector2i = unit.pos + d
				if state.grid.in_bounds(c) and not state.grid.is_wall(c) \
						and state.unit_at(c) == null and state.object_at(c) == null:
					out.append(c)
		"mortar":
			for y: int in range(state.grid.height):
				for x: int in range(state.grid.width):
					var c := Vector2i(x, y)
					if Grid.manhattan(unit.pos, c) <= MechActions.MORTAR_RANGE:
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

static func build(state: BattleState, unit: Unit, action_id: String, target_cell: Vector2i) -> Preview:
	var p := Preview.new()
	if not target_cell in valid_targets(state, unit, action_id):
		return p
	p.valid = true

	match action_id:
		"thrust", "shield_bash", "punch":
			p.target_cells = [target_cell]
			var victim: Unit = state.unit_at(target_cell)
			if victim != null:
				p.affected_ids.append(victim.id)
			var push_dist: int = 0 if action_id == "punch" else 1
			if push_dist > 0 and victim != null:
				var dir: Vector2i = target_cell - unit.pos
				var t: Dictionary = Push.trace(state, target_cell, dir, push_dist)
				p.push_from = target_cell
				p.push_to = t["final"]
				if t["collided"] == "unit":
					var slammed: Unit = state.unit_at(t["blocker"])
					if slammed != null:
						p.affected_ids.append(slammed.id)
		"throw_spear", "cannon":
			var dir2: Vector2i = Grid.cardinal_dir(unit.pos, target_cell)
			var rng: int = MechActions.THROW_RANGE if action_id == "throw_spear" else MechActions.CANNON_RANGE
			var la: Dictionary = state.line_attack(unit.pos, dir2, rng)
			p.line_cells = la["cells"]
			p.target_cells = [target_cell]
			if la["hit_unit"] != null:
				p.affected_ids.append(la["hit_unit"].id)
			p.hits_reactor = la["hit_reactor"]
			if action_id == "throw_spear":
				p.spear_landing = MechActions.spear_landing_cell(state, unit, dir2)
				if p.spear_landing == Vector2i(-1, -1):
					p.valid = false
		"mortar":
			p.target_cells = [target_cell]
			p.aoe_cells = state.grid.plus_area(target_cell)
			for c: Vector2i in p.aoe_cells:
				var u: Unit = state.unit_at(c)
				if u != null:
					p.affected_ids.append(u.id)
				if state.reactor.pos == c:
					p.hits_reactor = true
		"deploy_shield":
			p.target_cells = [target_cell]
		"retrieve_spear", "retrieve_shield":
			p.target_cells = [target_cell]
	return p
