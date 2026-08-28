extends GutTest

## Drives the real mission end to end, headless. A deliberately simple greedy
## player (attack what's in reach, otherwise close on the nearest enemy)
## should hold the reactor for 5 turns -- if this ever fails, the mission
## constants in mission.gd need a tune. Also covers both loss conditions and
## the bare survival-turn win.

func test_greedy_player_survives_the_mission() -> void:
	var s := BattleState.new()
	var guard := 0
	while s.phase == BattleState.Phase.PLAYER and guard < 40:
		guard += 1
		_greedy_player_turn(s)
		if s.phase != BattleState.Phase.PLAYER:
			break
		s.end_player_turn()
	assert_eq(s.phase, BattleState.Phase.WON, "greedy play holds the reactor for 5 turns")
	assert_gt(s.reactor.hp, 0)
	assert_true(s.turns_survived >= Mission.SURVIVE_TURNS)

func test_reactor_destroyed_is_a_loss() -> void:
	var s := BattleState.new()
	s.damage_reactor(s.reactor.hp)
	assert_true(s._check_end())
	assert_eq(s.phase, BattleState.Phase.LOST)

func test_all_mechs_destroyed_is_a_loss() -> void:
	var s := BattleState.new()
	for m in s.player_mechs():
		s.damage_unit(m, 999)
	assert_true(s._check_end())
	assert_eq(s.phase, BattleState.Phase.LOST)

func test_surviving_five_enemy_turns_with_reactor_alive_wins() -> void:
	var s := BattleState.new()
	s.turns_survived = Mission.SURVIVE_TURNS - 1
	# wipe scheduled resistance so the final enemy turn is quiet
	for id in s.units.keys():
		var u: Unit = s.units[id]
		if not u.is_player():
			s.damage_unit(u, 999)
	s.end_player_turn()
	assert_eq(s.phase, BattleState.Phase.WON)

# ------------------------------------------------------------------- greedy bot

func _greedy_player_turn(s: BattleState) -> void:
	for mech: Unit in s.player_mechs():
		var safety := 0
		while mech.is_alive() and mech.ap > 0 and s.phase == BattleState.Phase.PLAYER and safety < 6:
			safety += 1
			if not _greedy_one_action(s, mech):
				break

func _greedy_one_action(s: BattleState, mech: Unit) -> bool:
	var enemies := s.living_enemies()
	if enemies.is_empty():
		return false
	var acts := MechActions.available_actions(s, mech)

	# 1. melee an adjacent enemy
	for d: Vector2i in Grid.DIRS:
		var t := s.unit_at(mech.pos + d)
		if t != null and not t.is_player():
			for melee: String in ["thrust", "shield_bash", "punch"]:
				if melee in acts and s.player_action(mech, melee, mech.pos + d):
					return true

	# 2. ranged shot that hits an enemy without clipping the reactor
	for ranged: String in ["cannon", "throw_spear"]:
		if not ranged in acts:
			continue
		for cell: Vector2i in ActionPreview.valid_targets(s, mech, ranged):
			var p := ActionPreview.build(s, mech, ranged, cell)
			if p.valid and not p.hits_reactor and _has_enemy(s, p.affected_ids):
				if s.player_action(mech, ranged, cell):
					return true

	# 3. mortar the tile of the enemy nearest the reactor
	if "mortar" in acts:
		var focus := _nearest_to(enemies, s.reactor.pos)
		var mp := ActionPreview.build(s, mech, "mortar", focus.pos)
		if mp.valid and not mp.hits_reactor and s.player_action(mech, "mortar", focus.pos):
			return true

	# 4. otherwise close on the nearest enemy
	var target := _nearest_to(enemies, mech.pos)
	var dest := _closest_reachable(s, mech, target.pos)
	if dest != mech.pos and s.player_move(mech, dest):
		return true
	return false

func _has_enemy(s: BattleState, ids: Array) -> bool:
	for id: int in ids:
		var u: Unit = s.units.get(id)
		if u != null and not u.is_player():
			return true
	return false

func _nearest_to(units: Array[Unit], pos: Vector2i) -> Unit:
	var best: Unit = units[0]
	for u: Unit in units:
		if Grid.manhattan(u.pos, pos) < Grid.manhattan(best.pos, pos):
			best = u
	return best

func _closest_reachable(s: BattleState, mech: Unit, goal: Vector2i) -> Vector2i:
	var best := mech.pos
	var best_d := Grid.manhattan(mech.pos, goal)
	for cell: Vector2i in s.reachable_for(mech).keys():
		var d := Grid.manhattan(cell, goal)
		if d < best_d:
			best_d = d
			best = cell
	return best
