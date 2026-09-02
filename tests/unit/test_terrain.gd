extends GutTest

## Data-driven terrain: walls, pits, explosive barrels. All three ride the
## SAME grid / pathfinding / Push / preview systems -- no bespoke checks.

func _state() -> BattleState:
	var s := TestUtil.bare_state()      # reactor-only board, no walls
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func _pit(s: BattleState, c: Vector2i) -> void:
	s.objects[c] = GridObject.make_pit(c)

func _barrel(s: BattleState, c: Vector2i, hp := Mission.EXPLOSIVE_HP) -> GridObject:
	var o := GridObject.make_explosive(c, hp)
	s.objects[c] = o
	return o

# ------------------------------------------------------------------- walls

func test_wall_blocks_movement_and_astar() -> void:
	var s := _state()
	s.grid.set_wall(Vector2i(6, 5), true)
	var g := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_false(s.reachable_for(g).has(Vector2i(6, 5)), "can't stand on a wall")
	var path := s.grid.find_path(Vector2i(5, 5), Vector2i(7, 5), s.blocked_for_move())
	assert_false(path.has(Vector2i(6, 5)), "A* routes around the wall")

func test_wall_blocks_grunt_and_interceptor_pathing() -> void:
	var s := _state()
	for y in range(3, 9):
		s.grid.set_wall(Vector2i(4, y), true)   # a vertical wall
	var g := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(2, 6))
	var gp := EnemyAi.plan_grunt(s, g)
	for c in gp.path:
		assert_false(s.grid.is_wall(c), "grunt never steps on a wall")
	var i := TestUtil.add(s, Unit.Kind.INTERCEPTOR, Unit.Team.ENEMY, Vector2i(2, 3))
	var ip := EnemyAi.plan_interceptor(s, i)
	for c in ip.path:
		assert_false(s.grid.is_wall(c), "interceptor never steps on a wall")

func test_forced_move_into_wall_matches_preview() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	s.grid.set_wall(Vector2i(7, 5), true)
	var p := ActionPreview.build(s, lancer, "thrust", Vector2i(6, 5))
	var predicted := 0
	for h in p.hits:
		if h["id"] == foe.id:
			predicted = h["amount"]
	var before := foe.hp
	MechActions.execute(s, lancer, "thrust", Vector2i(6, 5))
	assert_eq(before - foe.hp, predicted, "preview's wall-slam damage == execution")
	assert_eq(foe.pos, Vector2i(6, 5), "stopped before the wall")

# ------------------------------------------------------------------- pits

func test_pit_blocks_voluntary_movement_and_astar() -> void:
	var s := _state()
	_pit(s, Vector2i(6, 5))
	var g := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_true(s.blocked_for_move().get(Vector2i(6, 5), false), "pit is move-blocked")
	assert_false(s.reachable_for(g).has(Vector2i(6, 5)), "can't walk into a pit")
	var path := s.grid.find_path(Vector2i(5, 5), Vector2i(7, 5), s.blocked_for_move())
	assert_false(path.has(Vector2i(6, 5)), "A* avoids the pit")

func test_forced_move_into_pit_destroys_the_unit() -> void:
	var s := _state()
	var victim := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 5))
	_pit(s, Vector2i(6, 5))
	var res := Push.resolve(s, victim, Vector2i(1, 0), 3, 3)
	assert_eq(res.hazard, "pit")
	assert_eq(victim.pos, Vector2i(6, 5), "slid into the pit")
	assert_false(victim.is_alive(), "and was destroyed")

func test_pit_preview_matches_execution() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(3, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(4, 5))
	_pit(s, Vector2i(6, 5))
	var p := ActionPreview.build(s, g, "throw", Vector2i(4, 5), {"dest": Vector2i(6, 5)})
	assert_true(p.valid)
	var lethal_predicted := false
	for h in p.hits:
		if h["id"] == foe.id and h["lethal"]:
			lethal_predicted = true
	assert_true(lethal_predicted, "preview flags the pit throw as lethal")
	MechActions.execute(s, g, "throw", Vector2i(4, 5), {"dest": Vector2i(6, 5)})
	assert_false(foe.is_alive(), "and it dies")

func test_ally_pit_displacement_is_predictable() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(3, 5))
	TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(4, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(2, 5))
	_pit(s, Vector2i(6, 5))
	var ally_cells: Array = []
	for e in MechActions.throw_dests(s, g, Vector2i(4, 5)):
		ally_cells.append(e["cell"])
	assert_false(Vector2i(6, 5) in ally_cells, "an ally is never offered a pit destination")
	assert_false(s.player_action(g, "throw", Vector2i(4, 5), {"dest": Vector2i(6, 5)}), "and the throw is rejected")

func test_enemy_pit_throw_is_offered_and_tagged() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(3, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(4, 5))
	_pit(s, Vector2i(6, 5))
	var pit_dest: Dictionary = {}
	for e in MechActions.throw_dests(s, g, Vector2i(4, 5)):
		if e["cell"] == Vector2i(6, 5):
			pit_dest = e
	assert_false(pit_dest.is_empty(), "the pit IS a valid enemy throw target")
	assert_true(pit_dest.get("pit", false), "and it's tagged as a pit")

# ------------------------------------------------------------------- explosives

func test_explosive_blocks_movement() -> void:
	var s := _state()
	_barrel(s, Vector2i(6, 5))
	var g := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_true(s.blocked_for_move().get(Vector2i(6, 5), false))
	assert_false(s.reachable_for(g).has(Vector2i(6, 5)))

func test_explosive_triggers_and_hits_area() -> void:
	var s := _state()
	var barrel := _barrel(s, Vector2i(6, 5))         # adjacent to the reactor at (6,6)
	var near := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 4))   # in the plus area
	var far := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 3))    # outside
	var rbefore := s.reactor.hp
	s.damage_object(barrel, Mission.EXPLOSIVE_HP)
	assert_null(s.object_at(Vector2i(6, 5)), "barrel consumed")
	assert_eq(near.hp, near.max_hp - Mission.EXPLOSIVE_DMG, "unit in the blast is hurt")
	assert_eq(far.hp, far.max_hp, "unit outside is untouched")
	assert_eq(s.reactor.hp, rbefore - Mission.EXPLOSIVE_DMG, "reactor in the blast -> hit")

func test_slam_into_explosive_triggers_it() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(3, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(4, 5))
	_barrel(s, Vector2i(6, 5))
	var p := ActionPreview.build(s, g, "throw", Vector2i(4, 5), {"dest": Vector2i(6, 5)})
	assert_true(p.valid)
	assert_false(p.explosion_cells.is_empty(), "preview shows the blast")
	var predicted := 0
	for h in p.hits:
		if h["id"] == foe.id:
			predicted = h["amount"]
	var before := foe.hp
	MechActions.execute(s, g, "throw", Vector2i(4, 5), {"dest": Vector2i(6, 5)})
	assert_null(s.object_at(Vector2i(6, 5)), "barrel gone")
	assert_eq(before - foe.hp, predicted, "preview damage on the thrown unit == execution (slam + blast)")

func test_chain_reaction() -> void:
	var s := _state()
	var a := _barrel(s, Vector2i(4, 5))
	_barrel(s, Vector2i(5, 5))                       # inside a's plus area -> chains
	var bystander := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))  # only in b's blast
	s.damage_object(a, Mission.EXPLOSIVE_HP)
	assert_null(s.object_at(Vector2i(4, 5)))
	assert_null(s.object_at(Vector2i(5, 5)), "second barrel detonated in the chain")
	assert_lt(bystander.hp, bystander.max_hp, "caught by the chained blast")
