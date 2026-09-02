extends GutTest

## The Chokepoint -- the second hand-designed slice. Covers the mission registry
## / dev picker logic, the map data being internally valid (in bounds, nothing
## stacked, reactor reachable from every enemy origin), a clean init, determinism,
## and the signature tactic the layout exists for: shoving a centre-lane enemy
## one tile into a shoulder pit.

# ------------------------------------------------------------- registry / picker

func test_registry_lists_both_missions() -> void:
	assert_eq(Mission.ids(), [Mission.REACTOR_BREACH, Mission.THE_CHOKEPOINT])
	assert_eq(Mission.catalog().size(), 2)
	for e: Dictionary in Mission.catalog():
		assert_true(e.has("id") and e.has("name"))
	assert_eq(Mission.display_name(Mission.THE_CHOKEPOINT), "The Chokepoint")

func test_by_id_builds_the_right_mission() -> void:
	assert_eq(Mission.by_id(Mission.THE_CHOKEPOINT).id, Mission.THE_CHOKEPOINT)
	assert_eq(Mission.by_id(Mission.REACTOR_BREACH).id, Mission.REACTOR_BREACH)
	assert_eq(Mission.by_id("nonsense").id, Mission.REACTOR_BREACH, "unknown id falls back to the default slice")

func test_by_id_returns_a_fresh_instance_each_call() -> void:
	var a := Mission.by_id(Mission.THE_CHOKEPOINT)
	var b := Mission.by_id(Mission.THE_CHOKEPOINT)
	assert_ne(a, b, "no shared mutable MissionData between runs")
	a.walls.append(Vector2i(0, 0))
	assert_ne(a.walls.size(), b.walls.size())

# ------------------------------------------------------------- data validity

func test_all_terrain_and_units_are_in_bounds_and_unstacked() -> void:
	var m := Mission.the_chokepoint()
	var used: Dictionary = {}
	var claim := func(tag: String, c: Vector2i) -> void:
		assert_true(c.x >= 0 and c.y >= 0 and c.x < m.grid_w and c.y < m.grid_h,
			"%s %s in bounds" % [tag, c])
		assert_false(used.has(c), "%s %s does not overlap %s" % [tag, c, used.get(c, "")])
		used[c] = tag
	for w: Vector2i in m.walls: claim.call("wall", w)
	for p: Vector2i in m.pits: claim.call("pit", p)
	for b: Vector2i in m.barrels: claim.call("barrel", b)
	claim.call("reactor", m.reactor_pos)
	for k: int in m.mech_starts: claim.call("mech", m.mech_starts[k])
	for e: Dictionary in m.initial_enemies: claim.call("enemy", e["cell"])
	for sp: Vector2i in m.spawn_points:
		assert_true(sp.x >= 0 and sp.y >= 0 and sp.x < m.grid_w and sp.y < m.grid_h,
			"spawn point %s in bounds" % sp)

func test_reactor_is_reachable_from_every_enemy_origin() -> void:
	var m := Mission.the_chokepoint()
	var g := Grid.new(m.grid_w, m.grid_h, m.walls)
	var no_units: Dictionary[Vector2i, bool] = {}
	var origins: Array[Vector2i] = []
	for e: Dictionary in m.initial_enemies:
		origins.append(e["cell"])
	for sp: Vector2i in m.spawn_points:
		origins.append(sp)
	for o: Vector2i in origins:
		assert_false(g.find_path(o, m.reactor_pos, no_units).is_empty(),
			"a walls-only path exists from %s to the reactor" % o)

func test_spawn_schedule_fits_the_defined_spawn_points() -> void:
	var m := Mission.the_chokepoint()
	var needed := 0
	for turn: int in m.spawn_schedule:
		needed += (m.spawn_schedule[turn] as Array).size()
	assert_true(needed <= m.spawn_points.size(),
		"%d scheduled spawns, %d spawn points" % [needed, m.spawn_points.size()])
	for turn: int in m.spawn_schedule:
		assert_true(turn >= 2 and turn <= m.turn_limit, "wave announced on a real player phase")

func test_the_two_missions_have_distinct_layouts() -> void:
	var rb := Mission.reactor_breach()
	var cp := Mission.the_chokepoint()
	assert_ne(rb.id, cp.id)
	assert_ne(rb.walls, cp.walls)
	assert_ne(rb.initial_enemies.size(), cp.initial_enemies.size())
	assert_true(Unit.Kind.ARTILLERY_ENEMY in _enemy_kinds(rb),
		"Reactor Breach uses the Artillery")
	assert_true(Unit.Kind.ARTILLERY_ENEMY not in _enemy_kinds(cp),
		"Chokepoint drops the Artillery -- it is a lane mission")

func _enemy_kinds(m: MissionData) -> Array:
	var out: Array = []
	for e: Dictionary in m.initial_enemies:
		out.append(e["kind"])
	for turn: int in m.spawn_schedule:
		for k: int in m.spawn_schedule[turn]:
			out.append(k)
	return out

# ------------------------------------------------------------- init / determinism

func test_init_places_the_squad_terrain_and_reactor() -> void:
	var s := BattleState.new(Mission.the_chokepoint())
	assert_eq(s.data.id, Mission.THE_CHOKEPOINT)
	assert_eq(s.data.turn_limit, 5)
	assert_eq(s.reactor.pos, Vector2i(6, 6))
	assert_eq(s.reactor.max_hp, 12)

	var kinds: Array = []
	for mech: Unit in s.player_mechs():
		kinds.append(mech.kind)
	assert_eq(s.player_mechs().size(), 3)
	assert_true(Unit.Kind.LANCER in kinds and Unit.Kind.BULWARK in kinds and Unit.Kind.GRAPPLER in kinds)

	assert_eq(s.living_enemies().size(), 3, "all three lanes are live from turn 1")
	for e: Unit in s.living_enemies():
		assert_eq(e.kind, Unit.Kind.GRUNT)

	assert_eq(s.object_at(Vector2i(5, 5)).kind, GridObject.Kind.PIT)
	assert_eq(s.object_at(Vector2i(7, 5)).kind, GridObject.Kind.PIT)
	assert_eq(s.object_at(Vector2i(5, 7)).kind, GridObject.Kind.EXPLOSIVE)
	assert_eq(s.object_at(Vector2i(7, 7)).kind, GridObject.Kind.EXPLOSIVE)

func test_two_fresh_states_are_identical() -> void:
	var a := BattleState.new(Mission.the_chokepoint())
	var b := BattleState.new(Mission.the_chokepoint())
	assert_eq(a.turn_number, b.turn_number)
	assert_eq(a.living_enemies().size(), b.living_enemies().size())
	for i: int in a.living_enemies().size():
		assert_eq(a.living_enemies()[i].pos, b.living_enemies()[i].pos)
		assert_eq(a.living_enemies()[i].kind, b.living_enemies()[i].kind)
	for i: int in a.player_mechs().size():
		assert_eq(a.player_mechs()[i].pos, b.player_mechs()[i].pos)
		assert_eq(a.player_mechs()[i].kind, b.player_mechs()[i].kind)

func test_reinforcements_announced_on_turn_2_not_before() -> void:
	var s := BattleState.new(Mission.the_chokepoint())
	assert_eq(s.pending_spawns.size(), 0, "nothing telegraphed on turn 1")
	s.end_player_turn()                       # -> player phase 2
	assert_eq(s.turn_number, 2)
	assert_eq(s.pending_spawns.size(), 3, "wave 2 (Charger + 2 Grunts) telegraphed on player phase 2")
	for sp: Dictionary in s.pending_spawns:
		assert_eq(sp["arrive_on_turn"], 2)

# ------------------------------------------------------------- the signature tactic

## The centre lane's shoulder pits exist so a shove is worth more than a hit:
## one tile sideways destroys a Charger the squad could otherwise only chip.
func test_throwing_a_centre_charger_into_a_shoulder_pit_destroys_it() -> void:
	var s := BattleState.new(Mission.the_chokepoint())
	# clear the lane so we control the setup
	for e: Unit in s.living_enemies():
		s.damage_unit(e, 999)
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(6, 4))
	g.ap = 2
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	assert_eq(s.object_at(Vector2i(5, 5)).kind, GridObject.Kind.PIT, "the NW shoulder pit is there")

	var p := ActionPreview.build(s, g, "throw", Vector2i(6, 5), {"dest": Vector2i(5, 5)})
	assert_true(p.valid, "grappler can throw the charger west into the pit")
	var predicted_lethal := false
	for h: Dictionary in p.hits:
		if h["id"] == charger.id and h["lethal"]:
			predicted_lethal = true
	assert_true(predicted_lethal, "preview: the charger dies in the pit")

	assert_true(s.player_action(g, "throw", Vector2i(6, 5), {"dest": Vector2i(5, 5)}))
	assert_false(charger.is_alive(), "execution matches -- one displacement, one kill")
	assert_eq(s.tel.c.get("pit_deaths", 0), 1)

# ------------------------------------------------------------- telemetry

func test_kill_cause_is_categorised_for_the_dev_summary() -> void:
	var s := TestUtil.bare_state()
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(4, 4))
	s.tel.note_death(s, foe, "explosion", -1)
	assert_eq(s.tel.c.get("blast_kills", 0), 1)
	assert_eq(s.tel.c.get("enemies_killed", 0), 1)
	var foe2 := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 4))
	s.tel.note_death(s, foe2, "collision", -1)
	assert_eq(s.tel.c.get("collision_kills", 0), 1)
	assert_string_contains(s.tel.summary_text(s), "blast")
