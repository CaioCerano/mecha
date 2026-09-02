extends GutTest

## Intent.project: recompute charge telegraphs against a hypothetical board and
## report when the player's action would change / interrupt one.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

func _charge(s: BattleState, owner: Unit, dir: Vector2i) -> void:
	s.telegraphs.append(Telegraph.charge(owner.id, [] as Array[Vector2i], dir, Mission.CHARGER_DMG, 99))

func test_shoving_the_charger_off_its_lane_interrupts_it() -> void:
	var s := _state()
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, 6))
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 6))
	_charge(s, charger, Vector2i(1, 0))   # aimed straight down row 6 at the Lancer

	var changes := Intent.project(s, {charger.id: Vector2i(1, 3)}, [])
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_eq(ch.owner_id, charger.id)
	assert_true(ch.interrupted, "no longer hits the Lancer")
	assert_eq(ch.safe_cell, lancer.pos)

func test_dropping_a_blocker_in_the_lane_interrupts_the_charge() -> void:
	var s := _state()
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, 6))
	_charge(s, charger, Vector2i(1, 0))   # aimed at the reactor at (6,6)

	var changes := Intent.project(s, {}, [Vector2i(3, 6)] as Array[Vector2i])
	assert_eq(changes.size(), 1)
	assert_true(changes[0].interrupted)
	assert_eq(changes[0].safe_cell, s.reactor.pos)

func test_unrelated_move_does_not_flag_a_change() -> void:
	var s := _state()
	var charger := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(1, 6))
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 2))
	_charge(s, charger, Vector2i(1, 0))   # at the reactor, nothing in the way

	var changes := Intent.project(s, {lancer.id: Vector2i(3, 2)}, [])
	assert_true(changes.is_empty(), "moving a mech outside the lane changes nothing")

func test_aoe_telegraphs_are_not_projected() -> void:
	var s := _state()
	var arty := TestUtil.add(s, Unit.Kind.ARTILLERY_ENEMY, Unit.Team.ENEMY, Vector2i(6, 3))
	s.telegraphs.append(Telegraph.aoe(arty.id, s.grid.plus_area(s.reactor.pos), Mission.ENEMY_ARTILLERY_DMG, 99))
	var changes := Intent.project(s, {arty.id: Vector2i(0, 0)}, [])
	assert_true(changes.is_empty(), "an AoE strike is locked to the reactor regardless of the owner")
