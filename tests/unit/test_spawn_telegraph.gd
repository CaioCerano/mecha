extends GutTest

## Reinforcement pipeline: a wave is announced at the top of its player phase,
## physically enters the next enemy phase WITHOUT acting, and only acts the
## enemy phase after that. No damage from a unit the player couldn't have seen
## coming last player phase.

func test_bare_state_starts_with_no_pending_spawns() -> void:
	var s := TestUtil.bare_state()
	assert_eq(s.pending_spawns.size(), 0)

func test_resolve_due_spawn_places_unit_at_the_telegraphed_cell() -> void:
	var s := TestUtil.bare_state()
	s.turn_number = 3
	s.pending_spawns.append({
		"kind": Unit.Kind.GRUNT, "cell": Vector2i(6, 0),
		"edge_dir": Vector2i(0, 1), "arrive_on_turn": 3,
	})
	s._resolve_due_spawns()
	assert_eq(s.pending_spawns.size(), 0, "the pending entry is consumed")
	var e := s.living_enemies()
	assert_eq(e.size(), 1)
	assert_eq(e[0].pos, Vector2i(6, 0), "enters exactly where the telegraph said")

func test_reinforcement_not_yet_due_is_left_pending() -> void:
	var s := TestUtil.bare_state()
	s.turn_number = 2
	s.pending_spawns.append({
		"kind": Unit.Kind.CHARGER, "cell": Vector2i(0, 6),
		"edge_dir": Vector2i(1, 0), "arrive_on_turn": 3,
	})
	s._resolve_due_spawns()
	assert_eq(s.pending_spawns.size(), 1, "not this phase")
	assert_eq(s.living_enemies().size(), 0)

func test_wave_two_is_announced_entering_player_phase_two() -> void:
	var s := BattleState.new()
	assert_eq(s.turn_number, 1)
	assert_eq(s.pending_spawns.size(), 0, "nothing telegraphed on the opening turn")

	s.end_player_turn()   # resolve enemy phase 1, roll into player phase 2

	assert_eq(s.turn_number, 2)
	assert_eq(s.phase, BattleState.Phase.PLAYER)
	assert_gt(s.pending_spawns.size(), 0, "wave 2 is now telegraphed")
	for sp: Dictionary in s.pending_spawns:
		assert_eq(sp["arrive_on_turn"], 2)
	assert_eq(s.living_enemies().size(), 2, "only wave 1 is actually on the board yet")

## A minimal mission with a single reinforcing Grunt so the "enters, then acts"
## timing is exact and not coupled to the real encounter's schedule.
func _test_mission() -> MissionData:
	var m := MissionData.new()
	m.reactor_pos = Vector2i(6, 6)
	m.reactor_hp = 12
	m.turn_limit = 9
	m.mech_starts = {Unit.Kind.LANCER: Vector2i(6, 8)}
	m.initial_enemies = [{"kind": Unit.Kind.GRUNT, "cell": Vector2i(6, 1)}]
	m.spawn_points = [Vector2i(0, 6)]
	m.spawn_schedule = {2: [Unit.Kind.GRUNT]}
	return m

func test_reinforcement_enters_without_acting_then_acts_next_phase() -> void:
	var s := BattleState.new(_test_mission())
	s.end_player_turn()   # -> player phase 2, wave 2 announced
	var before_ids := {}
	for e: Unit in s.living_enemies():
		before_ids[e.id] = true

	s.end_player_turn()   # enemy phase 2: the reinforcement ENTERS, does not act

	var fresh: Array[Unit] = []
	for e: Unit in s.living_enemies():
		if not before_ids.has(e.id):
			fresh.append(e)
	assert_eq(fresh.size(), 1, "the reinforcement is on the board")
	assert_eq(fresh[0].pos, Vector2i(0, 6), "entered and stayed put on its spawn cell this phase")

	var tracked: Unit = fresh[0]
	var d_before := Grid.manhattan(tracked.pos, s.reactor.pos)
	s.end_player_turn()   # enemy phase 3: now it acts
	assert_lt(Grid.manhattan(tracked.pos, s.reactor.pos), d_before,
		"the reinforcement advances on the reactor the phase after it arrived")
