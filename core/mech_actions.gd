class_name MechActions
extends RefCounted

## Deterministic resolvers for every player mech action, plus the geometry
## helpers the preview layer reuses so "what you see" always equals "what
## happens". Each resolver mutates BattleState and appends view events;
## BattleState.player_action() handles AP and legality.

const THRUST_DMG: int = 2
const THRUST_COLLISION: int = 2
const PUNCH_DMG: int = 1
const THROW_DMG: int = 3
const THROW_RANGE: int = 4

const BASH_DMG: int = 2
const BASH_PUSH: int = 2
const BASH_COLLISION: int = 2

## Grapple: a tether to a cardinal target up to GRAPPLE_RANGE away. It pulls an
## enemy/ally by a player-chosen 1..GRAPPLE_PULL_MAX tiles, or (on a wall / the
## reactor) reels the Grappler itself up to GRAPPLE_RANGE toward the anchor.
## Grapple deals NO damage -- its whole value is displacement.
const GRAPPLE_RANGE: int = 4
const GRAPPLE_PULL_MAX: int = 3
## Sentinel for "no second-stage destination chosen yet" (value-equal to
## ActionPreview.NONE, so either may be passed in).
const NO_DEST: Vector2i = Vector2i(-9999, -9999)
## Throw: hurl an adjacent unit in ANY cardinal direction, 1..GRAPPLER_THROW_DIST
## tiles. Slams (wall / unit / edge) resolve through the shared Push rules.
const GRAPPLER_THROW_DIST: int = 3
const GRAPPLER_THROW_COLLISION: int = 3

## Picking your own gear back up is free — the cost of throwing the spear /
## deploying the shield is meant to be positional, not an action-economy tax.
const FREE_ACTIONS: Array[String] = ["retrieve_spear", "retrieve_shield", "emergency_winch", "engineer_repair"]

static func is_free(action_id: String) -> bool:
	return action_id in FREE_ACTIONS

## Push distance for a melee action (thrust / bash / punch).
static func melee_push(action_id: String) -> int:
	match action_id:
		"thrust": return 1
		"shield_bash": return BASH_PUSH
	return 0

# --- descriptive lookups: one source of truth for card text and previews ---

## Primary on-hit damage (0 for actions that only deal collision damage).
static func action_damage(action_id: String) -> int:
	match action_id:
		"impact_spear": return 1
		"thermal_lance": return 3
		"thrust": return THRUST_DMG
		"punch": return PUNCH_DMG
		"shield_bash": return BASH_DMG
		"throw_spear": return THROW_DMG
	return 0

## Extra damage dealt on a hard stop (to the moved unit, and to anything it slams).
static func action_collision(action_id: String) -> int:
	match action_id:
		"impact_spear", "repulsor_plate": return 2
		"thrust": return THRUST_COLLISION
		"shield_bash": return BASH_COLLISION
		"throw": return GRAPPLER_THROW_COLLISION
	return 0

## Reach in cells. 1 == must be adjacent.
static func action_range(action_id: String) -> int:
	match action_id:
		"impact_spear", "anchor_shot", "tow_cable": return 3
		"thermal_lance": return 2
		"repulsor_plate", "emergency_winch": return 1
		"thrust", "punch", "shield_bash", "throw": return 1
		"throw_spear": return THROW_RANGE
		"grapple": return GRAPPLE_RANGE
	return 0

## Forced-movement distance this action applies. -1 == "player-chosen".
static func action_push(action_id: String) -> int:
	match action_id:
		"impact_spear": return 2
		"repulsor_plate": return 3
		"thrust": return 1
		"shield_bash": return BASH_PUSH
		"throw": return -1
		"grapple": return -1
	return 0

## Short keyword tags for the ability card (geometry / consequences, not prose).
static func action_tags(action_id: String) -> Array[String]:
	match action_id:
		"thrust": return ["Melee", "Push 1", "Slam"]
		"punch": return ["Melee", "Weak"]
		"throw_spear": return ["Line", "Pierce", "Drops spear"]
		"retrieve_spear": return ["Pick up", "Restores Thrust"]
		"shield_bash": return ["Melee", "Push 2", "Slam"]
		"deploy_shield": return ["Terrain", "Blocks move", "Drops bonus"]
		"retrieve_shield": return ["Pick up", "Restores bonus"]
		"grapple": return ["Line %d" % GRAPPLE_RANGE, "Pull 1-%d" % GRAPPLE_PULL_MAX, "Enemy / ally / self", "No damage"]
		"throw": return ["Grab adjacent", "Any direction", "Fling 1-%d" % GRAPPLER_THROW_DIST, "Slam %d" % GRAPPLER_THROW_COLLISION]
	return []

# ------------------------------------------------------------- action listing

static func available_actions(state: BattleState, unit: Unit) -> Array[String]:
	var acts: Array[String] = []
	if not unit.is_player():
		return acts
	var secondary := unit.secondary()
	acts.append("punch" if unit.kind == Unit.Kind.LANCER and not unit.has_spear else SquadLoadout.primary(unit.kind))
	if secondary == "throw_spear":
		if unit.has_spear:
			acts.append(secondary)
		elif adjacent_object(state, unit, GridObject.Kind.THROWN_SPEAR) != null:
			acts.append("retrieve_spear")
	elif secondary == "deploy_shield":
		if not unit.shield_deployed:
			acts.append(secondary)
		elif adjacent_object(state, unit, GridObject.Kind.DEPLOYED_SHIELD) != null:
			acts.append("retrieve_shield")
	elif secondary != "brace" or not unit.braced:
		acts.append(secondary)
	if unit.has_system("emergency_winch") and not unit.winch_used:
		acts.append("emergency_winch")
	if unit.pilot_id == "engineer" and not unit.engineer_used and (unit.impaired_slot >= 0 or unit.damage_state() in [Unit.DamageState.DAMAGED, Unit.DamageState.CRITICAL]):
		acts.append("engineer_repair")
	return acts

static func action_label(action_id: String) -> String:
	match action_id:
		"thrust": return "Thrust"
		"punch": return "Punch"
		"throw_spear": return "Throw Spear"
		"retrieve_spear": return "Retrieve Spear"
		"shield_bash": return "Shield Bash"
		"deploy_shield": return "Deploy Shield"
		"retrieve_shield": return "Retrieve Shield"
		"grapple": return "Grapple"
		"throw": return "Throw"
	return SquadLoadout.label(action_id)

# ------------------------------------------------------------- dispatch

## `opts` carries the second-stage choice for Grapple / Throw:
##   opts["dest"] : Vector2i -- the player-chosen final tile for the displaced
##                              entity. Absent -> a sensible default (max pull /
##                              straight-away throw), which is what tests and the
##                              headless bot use.
static func execute(state: BattleState, unit: Unit, action_id: String, target_cell: Vector2i, opts: Dictionary = {}) -> void:
	if action_id not in available_actions(state, unit):
		return
	var old_positions: Dictionary = {}
	for ally: Unit in state.player_mechs():
		old_positions[ally.id] = ally.pos
	var ace_ready: bool = unit.pilot_id == "ace" and unit.moved_this_turn >= 3 and not unit.ace_used
	var actuators: bool = unit.has_system("reinforced_actuators")
	_execute(state, unit, action_id, target_cell, opts)
	BuildEffects.after_action(state, unit, action_id, old_positions, ace_ready, actuators)

static func _execute(state: BattleState, unit: Unit, action_id: String, target_cell: Vector2i, opts: Dictionary) -> void:
	match action_id:
		"thrust": _melee(state, unit, target_cell, THRUST_DMG, 1 + unit.push_bonus(), THRUST_COLLISION)
		"punch": _melee(state, unit, target_cell, PUNCH_DMG, 0, 0)
		"shield_bash": _melee(state, unit, target_cell, BASH_DMG, BASH_PUSH + unit.push_bonus(), BASH_COLLISION)
		"throw_spear": _throw_spear(state, unit, target_cell)
		"retrieve_spear": _retrieve_spear(state, unit)
		"deploy_shield": _deploy_shield(state, unit, target_cell)
		"retrieve_shield": _retrieve_shield(state, unit)
		"grapple": _grapple(state, unit, target_cell, opts.get("dest", NO_DEST))
		"impact_spear", "thermal_lance": _line_secondary(state, unit, action_id, target_cell)
		"repulsor_plate": _melee(state, unit, target_cell, 0, 3 + unit.push_bonus(), 2)
		"brace":
			unit.braced = true
		"engineer_repair": BuildEffects.repair(state, unit)
		"anchor_shot":
			for c: Vector2i in state.objects.keys():
				var o: GridObject = state.objects[c]
				if o.kind == GridObject.Kind.ANCHOR and o.owner_id == unit.id:
					state.remove_object_at(c)
					state.events.append({"t": "object_destroyed", "pos": c})
			state.place_object(GridObject._mk(GridObject.Kind.ANCHOR, target_cell, unit.id, 0))
			state.events.append({"t": "anchor_place", "pos": target_cell})
		"tow_cable", "emergency_winch":
			var plan := rescue_plan(state, unit, target_cell, opts.get("dest", NO_DEST), action_id)
			if not plan.is_empty():
				var ally: Unit = state.units[plan.entity]
				var res := Push.resolve(state, ally, plan.dir, plan.dist, 0, unit.id, true)
				state.events.append({"t": "grapple_pull", "id": unit.id, "target_id": ally.id, "from": res.start, "to": res.final_pos})
				if action_id == "emergency_winch":
					unit.winch_used = true
					BuildEffects.proc(state, unit, "system", "emergency_winch")
		"throw": _grappler_throw(state, unit, target_cell, opts.get("dest", NO_DEST))

# ------------------------------------------------------------- resolvers

static func _melee(state: BattleState, unit: Unit, target_cell: Vector2i, damage: int, push_dist: int, collision: int) -> void:
	var target: Unit = state.unit_at(target_cell)
	if target == null:
		return
	var dir: Vector2i = target_cell - unit.pos
	state.events.append({"t": "attack", "id": unit.id, "target": target_cell})
	state.damage_unit(target, damage, "melee", unit.id)
	if push_dist > 0 and target.is_alive():
		var res: Push.Result = Push.resolve(state, target, dir, push_dist, collision, unit.id)
		state.events.append({"t": "push", "id": target.id, "from": res.start, "to": res.final_pos, "collided": res.collided_with})

static func _throw_spear(state: BattleState, unit: Unit, target_cell: Vector2i) -> void:
	var dir: Vector2i = Grid.cardinal_dir(unit.pos, target_cell)
	var la: Dictionary = state.line_attack(unit.pos, dir, THROW_RANGE)
	var landing: Vector2i = spear_landing_cell(state, unit, dir)
	if la["hit_unit"] != null:
		state.damage_unit(la["hit_unit"], THROW_DMG, "pierce", unit.id)
	elif la["hit_reactor"]:
		state.damage_reactor(THROW_DMG, "friendly_fire")
	elif la.get("hit_object") != null and la["hit_object"].is_destructible():
		state.damage_object(la["hit_object"], THROW_DMG, unit.id)
	unit.has_spear = false
	state.place_object(GridObject.make_spear(landing, unit.id))
	state.events.append({"t": "spear_throw", "id": unit.id, "from": unit.pos, "to": landing})

static func _retrieve_spear(state: BattleState, unit: Unit) -> void:
	var spear: GridObject = adjacent_object(state, unit, GridObject.Kind.THROWN_SPEAR)
	if spear == null:
		return
	state.remove_object_at(spear.pos)
	unit.has_spear = true
	state.events.append({"t": "spear_retrieve", "id": unit.id, "from": spear.pos})

static func _deploy_shield(state: BattleState, unit: Unit, target_cell: Vector2i) -> void:
	unit.shield_deployed = true
	state.place_object(GridObject.make_shield(target_cell, unit.id))
	state.events.append({"t": "shield_deploy", "id": unit.id, "pos": target_cell})

static func _retrieve_shield(state: BattleState, unit: Unit) -> void:
	var shield: GridObject = adjacent_object(state, unit, GridObject.Kind.DEPLOYED_SHIELD)
	if shield == null:
		return
	state.remove_object_at(shield.pos)
	unit.shield_deployed = false
	state.events.append({"t": "shield_retrieve", "id": unit.id, "from": shield.pos})

# ------------------------------------------------------------- grappler
#
# Grapple and Throw are both just DISPLACEMENT COMMANDS -- {entity, dir, dist,
# collision} -- resolved by the shared Push system. grapple_plan / throw_plan
# build the command from (focus cell, chosen destination); execution and the
# preview both go through them, so what you see is exactly what happens.

## Cells the grabbed thing at `focus` may be placed on. For a unit focus: the
## 1..GRAPPLE_PULL_MAX tiles it can be reeled to (slide stops at walls/units).
## For a wall / reactor anchor: the tiles the Grappler itself can be reeled to.
static func grapple_dests(state: BattleState, unit: Unit, focus: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir: Vector2i = Grid.cardinal_dir(unit.pos, focus)
	if dir == Vector2i.ZERO:
		return out
	var victim: Unit = state.unit_at(focus)
	if victim != null:
		var tr: Dictionary = Push.trace(state, focus, -dir, GRAPPLE_PULL_MAX + unit.push_bonus(), unit.id, victim.is_player())
		var n: int = Grid.manhattan(focus, tr["final"])
		# reeling an ally into a pit would kill it -- drop that last cell.
		if tr["hazard"] == "pit" and victim.is_player():
			n -= 1
		for k: int in range(1, n + 1):
			out.append(focus - dir * k)
	elif _is_anchor(state, focus):
		# self-reel never enters a pit voluntarily -- trace stops at it, drop it.
		var tr2: Dictionary = Push.trace(state, unit.pos, dir, GRAPPLE_RANGE, unit.id, true)
		var n2: int = Grid.manhattan(unit.pos, tr2["final"])
		if tr2["hazard"] == "pit":
			n2 -= 1
		for k: int in range(1, n2 + 1):
			out.append(unit.pos + dir * k)
	return out

static func _is_anchor(state: BattleState, cell: Vector2i) -> bool:
	return state.grid.is_wall(cell) or state.reactor.pos == cell or (state.object_at(cell) != null and state.object_at(cell).kind == GridObject.Kind.ANCHOR)

## Turn (focus, dest) into a displacement command, or {} if illegal.
static func grapple_plan(state: BattleState, unit: Unit, focus: Vector2i, dest: Vector2i) -> Dictionary:
	var dir: Vector2i = Grid.cardinal_dir(unit.pos, focus)
	if dir == Vector2i.ZERO:
		return {}
	var dests: Array[Vector2i] = grapple_dests(state, unit, focus)
	if dests.is_empty():
		return {}
	if dest != NO_DEST and dest not in dests:
		return {}
	var d: Vector2i = dest if dest in dests else dests[dests.size() - 1]   # default: max pull
	var victim: Unit = state.unit_at(focus)
	if victim != null:
		return {"entity": victim.id, "dir": -dir, "dist": Grid.manhattan(focus, d), "collision": 0, "is_self": false}
	return {"entity": unit.id, "dir": dir, "dist": Grid.manhattan(unit.pos, d), "collision": 0, "is_self": true}

## Every tile the adjacent unit at `focus` may be thrown onto, each tagged
## `slam` if landing there is a hard stop (wall / unit / edge collision).
## Harmful destinations are omitted for allied targets.
static func throw_dests(state: BattleState, unit: Unit, focus: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var victim: Unit = state.unit_at(focus)
	if victim == null or Grid.manhattan(unit.pos, focus) != 1:
		return out
	var is_ally: bool = victim.is_player()
	var seen: Dictionary[Vector2i, bool] = {}
	for tdir: Vector2i in Grid.DIRS:
		var tr: Dictionary = Push.trace(state, focus, tdir, (GRAPPLER_THROW_DIST + unit.push_bonus()), unit.id, is_ally)
		var landed: Vector2i = tr["final"]
		var is_pit: bool = tr["hazard"] == "pit"
		var slammed: bool = tr["collided"] != "none"
		var run: int = Grid.manhattan(focus, landed)
		for k: int in range(1, run + 1):
			var c: Vector2i = focus + tdir * k
			var last: bool = k == run
			if last and is_pit:
				# a pit destroys the thrown unit -- never offered for an ally
				if is_ally:
					continue
				if not seen.get(c, false):
					seen[c] = true
					out.append({"cell": c, "slam": true, "pit": true})
				continue
			# For an ally, "landing next to a wall" is a gentle placement, not a slam.
			var this_slam: bool = slammed and last and not is_ally and not is_pit
			if not seen.get(c, false):
				seen[c] = true
				out.append({"cell": c, "slam": this_slam})
		# Aiming at the blocker itself is an explicit "slam it into that" pick --
		# enemies only, never into the Grappler, never a pit (handled above).
		if slammed and not is_pit and not is_ally and tr["blocker"] != unit.pos \
				and state.grid.in_bounds(tr["blocker"]) and not seen.get(tr["blocker"], false):
			seen[tr["blocker"]] = true
			out.append({"cell": tr["blocker"], "slam": true})
	return out

## Turn (focus, dest) into a Throw command, or {} if illegal / unsafe-for-ally.
static func throw_plan(state: BattleState, unit: Unit, focus: Vector2i, dest: Vector2i) -> Dictionary:
	var victim: Unit = state.unit_at(focus)
	if victim == null or Grid.manhattan(unit.pos, focus) != 1:
		return {}
	var is_ally: bool = victim.is_player()
	var dir: Vector2i
	var dist: int
	if dest == NO_DEST:
		dir = focus - unit.pos                 # default: straight away from the Grappler
		dist = (GRAPPLER_THROW_DIST + unit.push_bonus())
	else:
		if dest == unit.pos:
			return {}                          # never throw a unit into the Grappler
		dir = Grid.cardinal_dir(focus, dest)
		if dir == Vector2i.ZERO:
			return {}
		var man: int = Grid.manhattan(focus, dest)
		if man < 1 or man > (GRAPPLER_THROW_DIST + unit.push_bonus()):
			return {}
		var full: Dictionary = Push.trace(state, focus, dir, (GRAPPLER_THROW_DIST + unit.push_bonus()), unit.id, is_ally)
		var run: int = Grid.manhattan(focus, full["final"])
		var slammed: bool = full["collided"] != "none"
		var is_pit: bool = full["hazard"] == "pit"
		if is_pit and dest == full["final"]:
			if is_ally:
				return {}                      # never throw an ally into a pit
			dist = man                         # slides exactly into the pit
		elif dest == full["blocker"] and not is_pit:
			if is_ally or not slammed:
				return {}                      # can't aim an ally at a wall
			dist = (GRAPPLER_THROW_DIST + unit.push_bonus())
		elif man > run:
			return {}                          # something's in the way sooner
		elif man == run and slammed and not is_pit and not is_ally:
			dist = (GRAPPLER_THROW_DIST + unit.push_bonus())          # enemy: "throw hard into that wall/edge"
		else:
			dist = man                         # precise placement (ally-safe path too)
	return {"entity": victim.id, "dir": dir, "dist": dist, "collision": GRAPPLER_THROW_COLLISION}

static func _grapple(state: BattleState, unit: Unit, focus: Vector2i, dest: Vector2i) -> void:
	var plan: Dictionary = grapple_plan(state, unit, focus, dest)
	if plan.is_empty():
		return
	var entity: Unit = state.units.get(plan["entity"])
	if entity == null:
		return
	var res: Push.Result = Push.resolve(state, entity, plan["dir"], plan["dist"], plan["collision"], unit.id, entity.is_player())
	if plan["is_self"]:
		state.events.append({"t": "grapple_self", "id": unit.id, "from": res.start, "to": res.final_pos})
	else:
		state.events.append({"t": "grapple_pull", "id": unit.id, "target_id": entity.id,
			"from": res.start, "to": res.final_pos})

static func _grappler_throw(state: BattleState, unit: Unit, focus: Vector2i, dest: Vector2i) -> void:
	var plan: Dictionary = throw_plan(state, unit, focus, dest)
	if plan.is_empty():
		return
	var victim: Unit = state.units.get(plan["entity"])
	if victim == null:
		return
	var t: Dictionary = Push.trace(state, victim.pos, plan["dir"], plan["dist"], unit.id, victim.is_player())
	state.events.append({"t": "attack", "id": unit.id, "target": focus})
	state.events.append({"t": "throw_unit", "id": unit.id, "victim_id": victim.id,
		"from": victim.pos, "to": t["final"]})
	Push.resolve(state, victim, plan["dir"], plan["dist"], plan["collision"], unit.id, victim.is_player())

# ------------------------------------------------------------- shared geometry

## The cell a thrown spear ends up on for direction `dir`: just short of
## whatever it hits, or the last clear cell if it hits nothing. Vector2i(-1,-1)
## if there is nowhere valid to land.
static func spear_landing_cell(state: BattleState, unit: Unit, dir: Vector2i) -> Vector2i:
	if dir == Vector2i.ZERO:
		return Vector2i(-1, -1)
	var la: Dictionary = state.line_attack(unit.pos, dir, THROW_RANGE)
	var cells: Array = la["cells"]
	var ideal: Vector2i
	if la["hit_unit"] != null or la["hit_reactor"]:
		ideal = cells[cells.size() - 2] if cells.size() >= 2 else unit.pos
	elif cells.is_empty():
		ideal = unit.pos
	else:
		ideal = cells[cells.size() - 1]
	return _free_cell_near(state, ideal)

static func _free_cell_near(state: BattleState, ideal: Vector2i) -> Vector2i:
	var probes: Array[Vector2i] = [ideal]
	for d: Vector2i in Grid.DIRS:
		probes.append(ideal + d)
	for c: Vector2i in probes:
		if not state.grid.in_bounds(c):
			continue
		if state.grid.is_wall(c):
			continue
		if state.unit_at(c) != null:
			continue
		if state.object_at(c) != null:
			continue
		return c
	return Vector2i(-1, -1)

static func adjacent_object(state: BattleState, unit: Unit, kind: GridObject.Kind) -> GridObject:
	var probes: Array[Vector2i] = [unit.pos]
	for d: Vector2i in Grid.DIRS:
		probes.append(unit.pos + d)
	for c: Vector2i in probes:
		var obj: GridObject = state.object_at(c)
		if obj != null and obj.kind == kind and obj.owner_id == unit.id:
			return obj
	return null

static func rescue_dests(state: BattleState, unit: Unit, focus: Vector2i, action: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var ally := state.unit_at(focus)
	if ally == null or not ally.is_player() or ally == unit:
		return out
	var dir := Grid.cardinal_dir(focus, unit.pos)
	if action == "tow_cable" and (dir == Vector2i.ZERO or Grid.manhattan(unit.pos, focus) > 3):
		return out
	if action == "emergency_winch" and Grid.manhattan(unit.pos, focus) != 1:
		return out
	var dirs: Array[Vector2i] = []
	if action == "emergency_winch":
		dirs.assign(Grid.DIRS)
	else:
		dirs.append(dir)
	for d: Vector2i in dirs:
		for distance: int in range(1, 2 if action == "emergency_winch" else 3):
			var tr := Push.trace(state, focus, d, distance, unit.id, true)
			if tr.collided == "none" and tr.final != focus:
				out.append(tr.final)
	return out

static func rescue_plan(state: BattleState, unit: Unit, focus: Vector2i, dest: Vector2i, action: String) -> Dictionary:
	var dests := rescue_dests(state, unit, focus, action)
	if dests.is_empty() or (dest != NO_DEST and dest not in dests):
		return {}
	var d: Vector2i = dests[-1] if dest == NO_DEST else dest
	return {"entity": state.unit_at(focus).id, "dir": Grid.cardinal_dir(focus, d), "dist": Grid.manhattan(focus, d)}

static func _line_secondary(state: BattleState, unit: Unit, action: String, target: Vector2i) -> void:
	var dir := Grid.cardinal_dir(unit.pos, target)
	var la := state.line_attack(unit.pos, dir, action_range(action))
	var damage := action_damage(action)
	state.events.append({"t": "attack", "id": unit.id, "target": la.hit_pos if la.hit_pos.x >= 0 else target})
	if la.hit_unit != null:
		var victim: Unit = la.hit_unit
		state.damage_unit(victim, damage, "line", unit.id)
		if action == "impact_spear" and victim.is_alive():
			var res := Push.resolve(state, victim, dir, 2 + unit.push_bonus(), 2, unit.id)
			state.events.append({"t": "push", "id": victim.id, "from": res.start, "to": res.final_pos})
	elif la.hit_reactor:
		state.damage_reactor(damage, "friendly_fire")
	elif la.get("hit_object") != null and la.hit_object.is_destructible():
		state.damage_object(la.hit_object, damage, unit.id)
