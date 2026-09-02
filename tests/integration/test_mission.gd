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
	assert_true(s.turns_survived >= s.data.turn_limit)

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

# ------------------------------------------------------------------- Reactor Breach

func test_reactor_breach_initializes_squad_terrain_and_reactor() -> void:
	var s := BattleState.new()   # default = Mission.reactor_breach()
	assert_eq(s.data.id, "reactor_breach")
	assert_eq(s.data.turn_limit, 5)
	# squad
	var kinds: Array = []
	for m: Unit in s.player_mechs():
		kinds.append(m.kind)
	assert_eq(s.player_mechs().size(), 3)
	assert_true(Unit.Kind.LANCER in kinds and Unit.Kind.BULWARK in kinds and Unit.Kind.GRAPPLER in kinds)
	# initial enemies
	assert_eq(s.living_enemies().size(), 2, "two grunts on the board at start")
	for e: Unit in s.living_enemies():
		assert_eq(e.kind, Unit.Kind.GRUNT)
	# terrain
	assert_eq(s.object_at(Vector2i(6, 3)).kind, GridObject.Kind.PIT)
	assert_eq(s.object_at(Vector2i(9, 3)).kind, GridObject.Kind.PIT)
	assert_eq(s.object_at(Vector2i(4, 5)).kind, GridObject.Kind.EXPLOSIVE)
	assert_eq(s.object_at(Vector2i(9, 6)).kind, GridObject.Kind.EXPLOSIVE)
	assert_true(s.grid.is_wall(Vector2i(3, 3)))
	# reactor
	assert_eq(s.reactor.pos, Vector2i(6, 6))
	assert_eq(s.reactor.max_hp, 12)

func test_reactor_breach_reinforcements_announced_then_arrive() -> void:
	var s := BattleState.new()
	assert_eq(s.pending_spawns.size(), 0, "nothing telegraphed on turn 1")
	s.end_player_turn()               # -> player phase 2
	assert_eq(s.turn_number, 2)
	var announced: int = s.pending_spawns.size()
	assert_eq(announced, 2, "wave 2 (Charger + Artillery) announced on player phase 2")
	for sp: Dictionary in s.pending_spawns:
		assert_eq(sp["arrive_on_turn"], 2)
	var before: int = s.living_enemies().size()
	s.end_player_turn()               # enemy phase 2: wave 2 enters -> player phase 3
	assert_eq(s.living_enemies().size(), before + announced, "wave 2 is now on the board")
	for sp: Dictionary in s.pending_spawns:
		assert_eq(sp["arrive_on_turn"], 3, "wave 2 is no longer pending; only wave 3 is")

func test_killing_every_enemy_is_not_required_for_victory() -> void:
	var s := BattleState.new()
	s.turns_survived = s.data.turn_limit - 1
	assert_gt(s.living_enemies().size(), 0)
	s.end_player_turn()               # one more enemy phase -> turns_survived hits the limit
	assert_eq(s.phase, BattleState.Phase.WON)
	assert_gt(s.living_enemies().size(), 0, "enemies still alive -- holding the reactor was enough")

func test_optional_objective_tracks_squad() -> void:
	var s := BattleState.new()
	assert_true(s.optional_objective_met(), "all three mechs operational at start")
	s.damage_unit(s.player_mechs()[0], 999)
	assert_false(s.optional_objective_met(), "a destroyed mech fails the optional objective")

func test_restart_returns_to_deterministic_initial_state() -> void:
	var a := BattleState.new()
	a.end_player_turn()
	a.end_player_turn()               # advance a couple of phases
	var b := BattleState.new()        # "restart" == a fresh BattleState
	assert_eq(b.turn_number, 1)
	assert_eq(b.turns_survived, 0)
	assert_eq(b.reactor.hp, b.reactor.max_hp)
	assert_eq(b.living_enemies().size(), 2)
	var b0 := BattleState.new()       # two fresh states must be identical
	assert_eq(b.living_enemies().size(), b0.living_enemies().size())
	for i in b.living_enemies().size():
		assert_eq(b.living_enemies()[i].pos, b0.living_enemies()[i].pos)
		assert_eq(b.living_enemies()[i].kind, b0.living_enemies()[i].kind)
	for i in b.player_mechs().size():
		assert_eq(b.player_mechs()[i].pos, b0.player_mechs()[i].pos)

func test_surviving_five_enemy_turns_with_reactor_alive_wins() -> void:
	var s := BattleState.new()
	s.turns_survived = s.data.turn_limit - 1
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

	# 1. melee an adjacent enemy (thrust / bash both hit and shove)
	for d: Vector2i in Grid.DIRS:
		var t := s.unit_at(mech.pos + d)
		if t != null and not t.is_player():
			for melee: String in ["thrust", "shield_bash", "punch"]:
				if melee in acts and s.player_action(mech, melee, mech.pos + d):
					return true

	# 2. Grappler: throw an adjacent enemy if it lands farther from the reactor
	if "throw" in acts:
		for d: Vector2i in Grid.DIRS:
			var t := s.unit_at(mech.pos + d)
			if t == null or t.is_player():
				continue
			var tp := ActionPreview.build(s, mech, "throw", mech.pos + d)
			if tp.valid and Grid.manhattan(tp.push_to, s.reactor.pos) > Grid.manhattan(t.pos, s.reactor.pos):
				if s.player_action(mech, "throw", mech.pos + d):
					return true

	# 3. ranged spear that hits an enemy without clipping the reactor
	if "throw_spear" in acts:
		for cell: Vector2i in ActionPreview.valid_targets(s, mech, "throw_spear"):
			var p := ActionPreview.build(s, mech, "throw_spear", cell)
			if p.valid and not p.hits_reactor and _has_enemy(s, p.affected_ids):
				if s.player_action(mech, "throw_spear", cell):
					return true

	# 4. Grappler: reel in the enemy closest to the reactor to stall its advance
	if "grapple" in acts:
		var best_cell := Vector2i(-999, -999)
		var best_d := 1 << 30
		for cell: Vector2i in ActionPreview.valid_targets(s, mech, "grapple"):
			var u := s.unit_at(cell)
			if u == null or u.is_player():
				continue
			var gd := Grid.manhattan(cell, s.reactor.pos)
			if gd < best_d:
				best_d = gd
				best_cell = cell
		if best_cell.x > -999 and s.player_action(mech, "grapple", best_cell):
			return true

	# 5. otherwise close on the enemy nearest the reactor
	var target := _nearest_to(enemies, s.reactor.pos)
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
