class_name TerrainFx
extends RefCounted

## Pure prediction of a chain explosion -- mirrors BattleState.detonate() step
## for step (breadth-first drain, local HP copies, EXPLOSIVE_DMG per cell,
## Unit.mitigate() damage modifiers) so a preview's numbers equal execution's.

## `initial` : barrel cells that detonate first.
## `unit_pos_override` : id -> hypothetical cell (for previewing a slam that
##                        just moved a unit next to the barrel).
## `damage_so_far`     : id -> damage the previewed action already dealt (so a
##                        unit that a slam left at 1 HP dies to the blast, not
##                        takes a phantom full hit).
static func explosion_plan(state: BattleState, initial: Array,
		unit_pos_override: Dictionary = {}, damage_so_far: Dictionary = {}) -> Dictionary:
	var exp_hp: Dictionary = {}
	for pos: Vector2i in state.objects:
		var o: GridObject = state.objects[pos]
		if o.kind == GridObject.Kind.EXPLOSIVE:
			exp_hp[pos] = o.hp

	var occ: Dictionary = {}
	var unit_hp: Dictionary = {}
	for id: int in state.units:
		var u: Unit = state.units[id]
		if u.is_alive():
			var at: Vector2i = unit_pos_override.get(id, u.pos)
			occ[at] = id
			unit_hp[id] = maxi(u.hp - int(damage_so_far.get(id, 0)), 0)

	var unit_dmg: Dictionary = {}
	var reactor_dmg: int = 0
	var blast: Dictionary = {}
	var done: Dictionary = {}
	var queue: Array = initial.duplicate()

	while not queue.is_empty():
		var center: Vector2i = queue.pop_front()
		if done.get(center, false):
			continue
		if not exp_hp.has(center):
			continue
		done[center] = true
		exp_hp.erase(center)
		for c: Vector2i in state.grid.plus_area(center):
			blast[c] = true
			if occ.has(c):
				var uid: int = occ[c]
				if unit_hp.get(uid, 0) > 0:
					var dmg: int = mini(state.units[uid].mitigate(Mission.EXPLOSIVE_DMG), unit_hp[uid])
					unit_hp[uid] -= dmg
					unit_dmg[uid] = unit_dmg.get(uid, 0) + dmg
			if state.reactor.pos == c:
				reactor_dmg += mini(Mission.EXPLOSIVE_DMG, maxi(state.reactor.hp - reactor_dmg, 0))
			if exp_hp.has(c) and c != center:
				exp_hp[c] -= Mission.EXPLOSIVE_DMG
				if exp_hp[c] <= 0:
					queue.append(c)

	var hits: Array = []
	for id: int in unit_dmg:
		if unit_dmg[id] > 0:
			hits.append({"id": id, "amount": unit_dmg[id]})
	return {"blast": blast.keys(), "hits": hits, "reactor_dmg": reactor_dmg, "detonated": done.keys()}
