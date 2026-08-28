extends GutTest

## Mech identity: spear thrust/throw/retrieve and the positioning problem it
## creates, shield deploy/retrieve as terrain, artillery cannon line and
## delayed mortar. Also checks preview == execution on a couple of cases.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

# ------------------------------------------------------------------- spear

func test_thrust_damages_pushes_and_wall_collision() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	s.grid.set_wall(Vector2i(7, 5), true)
	MechActions.execute(s, spear, "thrust", Vector2i(6, 5))
	# 2 thrust + 2 collision into the wall = 4, grunt has 3 hp -> dead
	assert_false(foe.is_alive(), "thrust + wall collision kills a 3hp grunt")

func test_thrust_push_into_open_moves_target_one_tile() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	MechActions.execute(s, spear, "thrust", Vector2i(6, 5))
	assert_eq(foe.pos, Vector2i(7, 5), "pushed one tile into open space")
	assert_eq(foe.hp, foe.max_hp - 2, "only the thrust damage, no collision")

func test_throw_spear_hits_takes_spear_away_and_swaps_to_punch() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	assert_true("thrust" in MechActions.available_actions(s, spear))

	MechActions.execute(s, spear, "throw_spear", Vector2i(6, 5))
	assert_false(spear.has_spear, "spear is now on the battlefield")
	assert_lt(foe.hp, foe.max_hp, "the throw connected")
	var landing: Vector2i = Vector2i(5, 5)
	assert_not_null(s.object_at(landing), "spear landed just short of the target")
	assert_eq(s.object_at(landing).kind, GridObject.Kind.THROWN_SPEAR)

	var acts := MechActions.available_actions(s, spear)
	assert_true("punch" in acts, "without the spear only Punch is available")
	assert_false("thrust" in acts)
	assert_false("throw_spear" in acts)

func test_retrieve_spear_only_when_adjacent_then_restores_thrust() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	MechActions.execute(s, spear, "throw_spear", Vector2i(6, 5))
	# spear at (5,5); mech far away -> cannot retrieve
	assert_false("retrieve_spear" in MechActions.available_actions(s, spear))

	s.move_unit(spear, Vector2i(5, 6))   # step adjacent to the spear
	assert_true("retrieve_spear" in MechActions.available_actions(s, spear))
	MechActions.execute(s, spear, "retrieve_spear", Vector2i(5, 5))
	assert_true(spear.has_spear)
	assert_null(s.object_at(Vector2i(5, 5)), "spear picked up off the grid")
	assert_true("thrust" in MechActions.available_actions(s, spear))

func test_retrieve_spear_via_player_action_costs_no_ap() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(2, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))   # stops the spear at (5, 5)
	spear.ap = 2
	MechActions.execute(s, spear, "throw_spear", Vector2i(6, 5))
	s.move_unit(spear, Vector2i(5, 6))
	spear.ap = 1
	assert_true(s.player_action(spear, "retrieve_spear", Vector2i(5, 5)))
	assert_true(spear.has_spear)
	assert_eq(spear.ap, 1, "retrieve is free — positioning is the only cost")

func test_retrieve_shield_works_with_zero_ap() -> void:
	var s := _state()
	var shield := TestUtil.add(s, Unit.Kind.SHIELD, Unit.Team.PLAYER, Vector2i(5, 5))
	MechActions.execute(s, shield, "deploy_shield", Vector2i(6, 5))
	shield.ap = 0
	assert_true(s.player_action(shield, "retrieve_shield", Vector2i(6, 5)), "no AP left, still allowed")
	assert_false(shield.shield_deployed)

func test_throw_spear_blocked_by_wall_lands_short() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(2, 5))
	s.grid.set_wall(Vector2i(5, 5), true)
	MechActions.execute(s, spear, "throw_spear", Vector2i(4, 5))
	assert_not_null(s.object_at(Vector2i(4, 5)), "lands in the last clear cell before the wall")

# ------------------------------------------------------------------- shield

func test_deploy_shield_creates_blocking_terrain_and_drops_bonus() -> void:
	var s := _state()
	var shield := TestUtil.add(s, Unit.Kind.SHIELD, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_false(shield.shield_deployed)
	MechActions.execute(s, shield, "deploy_shield", Vector2i(6, 5))
	assert_true(shield.shield_deployed)
	var obj := s.object_at(Vector2i(6, 5))
	assert_not_null(obj)
	assert_true(obj.blocks_move() and obj.blocks_line(), "shield is real terrain")
	assert_true(s.blocked_for_move().get(Vector2i(6, 5), false), "pathfinding avoids it")

func test_shield_bonus_reduces_damage_only_while_stowed() -> void:
	var s := _state()
	var shield := TestUtil.add(s, Unit.Kind.SHIELD, Unit.Team.PLAYER, Vector2i(5, 5))
	s.damage_unit(shield, 3)
	assert_eq(shield.hp, shield.max_hp - 2, "stowed shield: 3 damage becomes 2")
	MechActions.execute(s, shield, "deploy_shield", Vector2i(6, 5))
	s.damage_unit(shield, 3)
	assert_eq(shield.hp, shield.max_hp - 5, "deployed: full 3 damage")

func test_retrieve_shield_restores_bonus_and_clears_terrain() -> void:
	var s := _state()
	var shield := TestUtil.add(s, Unit.Kind.SHIELD, Unit.Team.PLAYER, Vector2i(5, 5))
	MechActions.execute(s, shield, "deploy_shield", Vector2i(6, 5))
	MechActions.execute(s, shield, "retrieve_shield", Vector2i(6, 5))
	assert_false(shield.shield_deployed)
	assert_null(s.object_at(Vector2i(6, 5)))

func test_line_attack_blocked_by_deployed_shield() -> void:
	var s := _state()
	var arty := TestUtil.add(s, Unit.Kind.ARTILLERY, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(8, 5))
	s.place_object(GridObject.make_shield(Vector2i(5, 5), 999))
	MechActions.execute(s, arty, "cannon", Vector2i(8, 5))
	assert_eq(foe.hp, foe.max_hp, "cannon stopped at the shield, foe untouched")

# ------------------------------------------------------------------- artillery

func test_cannon_hits_first_unit_in_line() -> void:
	var s := _state()
	var arty := TestUtil.add(s, Unit.Kind.ARTILLERY, Unit.Team.PLAYER, Vector2i(2, 5))
	var near := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 5))
	var far := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(7, 5))
	MechActions.execute(s, arty, "cannon", Vector2i(7, 5))
	assert_lt(near.hp, near.max_hp, "first unit in the line is hit")
	assert_eq(far.hp, far.max_hp, "the one behind it is not")

func test_mortar_resolves_on_the_following_player_turn() -> void:
	var s := _state()
	var arty := TestUtil.add(s, Unit.Kind.ARTILLERY, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 8))
	MechActions.execute(s, arty, "mortar", Vector2i(5, 8))
	assert_eq(foe.hp, foe.max_hp, "mortar does nothing the turn it is fired")
	assert_eq(s.pending_mortars.size(), 1)

	s.turn_number += 1
	s._resolve_pending_mortars()
	assert_lt(foe.hp, foe.max_hp, "it lands at the start of the next player turn")
	assert_eq(s.pending_mortars.size(), 0)

func test_mortar_destroys_a_wall_in_its_area() -> void:
	var s := _state()
	var arty := TestUtil.add(s, Unit.Kind.ARTILLERY, Unit.Team.PLAYER, Vector2i(5, 5))
	s.grid.set_wall(Vector2i(5, 8), true)
	MechActions.execute(s, arty, "mortar", Vector2i(5, 8))
	s.turn_number += 1
	s._resolve_pending_mortars()
	assert_false(s.grid.is_wall(Vector2i(5, 8)), "mortar cleared the wall tile")

# ------------------------------------------------------------------- preview

func test_preview_matches_execution_for_thrust_push() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	var p := ActionPreview.build(s, spear, "thrust", Vector2i(6, 5))
	assert_true(p.valid)
	assert_eq(p.push_to, Vector2i(7, 5), "preview predicts the push destination")
	assert_true(foe.id in p.affected_ids)
	MechActions.execute(s, spear, "thrust", Vector2i(6, 5))
	assert_eq(foe.pos, p.push_to, "execution lands where the preview said")

func test_preview_flags_friendly_fire_on_reactor() -> void:
	var s := _state()
	var arty := TestUtil.add(s, Unit.Kind.ARTILLERY, Unit.Team.PLAYER, Vector2i(6, 4))
	var p := ActionPreview.build(s, arty, "mortar", s.reactor.pos)
	assert_true(p.valid)
	assert_true(p.hits_reactor, "preview warns the AoE covers the reactor")

func test_invalid_targets_are_rejected() -> void:
	var s := _state()
	var spear := TestUtil.add(s, Unit.Kind.SPEAR, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_false(ActionPreview.build(s, spear, "thrust", Vector2i(7, 5)).valid, "no unit there / not adjacent")
	assert_false(ActionPreview.build(s, spear, "throw_spear", Vector2i(7, 7)).valid, "not a cardinal line")
