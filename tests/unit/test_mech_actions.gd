extends GutTest

## Mech identity: Lancer thrust/throw/retrieve and the positioning problem it
## creates, Bulwark bash/deploy (deploy is move-terrain only now), Grappler
## grapple (reel a unit in, or reel yourself to an anchor) and throw (hurl an
## adjacent unit, collisions resolve slams). Also checks preview == execution.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

# ------------------------------------------------------------------- lancer

func test_thrust_damages_pushes_and_wall_collision() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	s.grid.set_wall(Vector2i(7, 5), true)
	MechActions.execute(s, lancer, "thrust", Vector2i(6, 5))
	# 2 thrust + 2 collision into the wall = 4, grunt has 3 hp -> dead
	assert_false(foe.is_alive(), "thrust + wall collision kills a 3hp grunt")

func test_thrust_push_into_open_moves_target_one_tile() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	MechActions.execute(s, lancer, "thrust", Vector2i(6, 5))
	assert_eq(foe.pos, Vector2i(7, 5), "pushed one tile into open space")
	assert_eq(foe.hp, foe.max_hp - 2, "only the thrust damage, no collision")

func test_throw_spear_hits_takes_spear_away_and_swaps_to_punch() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	assert_true("thrust" in MechActions.available_actions(s, lancer))

	MechActions.execute(s, lancer, "throw_spear", Vector2i(6, 5))
	assert_false(lancer.has_spear, "spear is now on the battlefield")
	assert_lt(foe.hp, foe.max_hp, "the throw connected")
	var landing: Vector2i = Vector2i(5, 5)
	assert_not_null(s.object_at(landing), "spear landed just short of the target")
	assert_eq(s.object_at(landing).kind, GridObject.Kind.THROWN_SPEAR)

	var acts := MechActions.available_actions(s, lancer)
	assert_true("punch" in acts, "without the spear only Punch is available")
	assert_false("thrust" in acts)
	assert_false("throw_spear" in acts)

func test_retrieve_spear_only_when_adjacent_then_restores_thrust() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	MechActions.execute(s, lancer, "throw_spear", Vector2i(6, 5))
	# spear at (5,5); mech far away -> cannot retrieve
	assert_false("retrieve_spear" in MechActions.available_actions(s, lancer))

	s.move_unit(lancer, Vector2i(5, 6))   # step adjacent to the spear
	assert_true("retrieve_spear" in MechActions.available_actions(s, lancer))
	MechActions.execute(s, lancer, "retrieve_spear", Vector2i(5, 5))
	assert_true(lancer.has_spear)
	assert_null(s.object_at(Vector2i(5, 5)), "spear picked up off the grid")
	assert_true("thrust" in MechActions.available_actions(s, lancer))

func test_retrieve_spear_via_player_action_costs_no_ap() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 5))
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))   # stops the spear at (5, 5)
	lancer.ap = 2
	MechActions.execute(s, lancer, "throw_spear", Vector2i(6, 5))
	s.move_unit(lancer, Vector2i(5, 6))
	lancer.ap = 1
	assert_true(s.player_action(lancer, "retrieve_spear", Vector2i(5, 5)))
	assert_true(lancer.has_spear)
	assert_eq(lancer.ap, 1, "retrieve is free — positioning is the only cost")

func test_throw_spear_blocked_by_wall_lands_short() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 5))
	s.grid.set_wall(Vector2i(5, 5), true)
	MechActions.execute(s, lancer, "throw_spear", Vector2i(4, 5))
	assert_not_null(s.object_at(Vector2i(4, 5)), "lands in the last clear cell before the wall")

# ------------------------------------------------------------------- bulwark

func test_retrieve_shield_works_with_zero_ap() -> void:
	var s := _state()
	var bulwark := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	MechActions.execute(s, bulwark, "deploy_shield", Vector2i(6, 5))
	bulwark.ap = 0
	assert_true(s.player_action(bulwark, "retrieve_shield", Vector2i(6, 5)), "no AP left, still allowed")
	assert_false(bulwark.shield_deployed)

func test_deploy_shield_blocks_movement_but_not_line() -> void:
	var s := _state()
	var bulwark := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_false(bulwark.shield_deployed)
	MechActions.execute(s, bulwark, "deploy_shield", Vector2i(6, 5))
	assert_true(bulwark.shield_deployed)
	var obj := s.object_at(Vector2i(6, 5))
	assert_not_null(obj)
	assert_true(obj.blocks_move(), "shield is still a wall you can hide behind")
	assert_false(obj.blocks_line(), "but projectiles pass over it now")
	assert_true(s.blocked_for_move().get(Vector2i(6, 5), false), "pathfinding avoids it")

func test_shield_bonus_reduces_damage_only_while_stowed() -> void:
	var s := _state()
	var bulwark := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	s.damage_unit(bulwark, 3)
	assert_eq(bulwark.hp, bulwark.max_hp - 2, "stowed: 3 damage becomes 2")
	MechActions.execute(s, bulwark, "deploy_shield", Vector2i(6, 5))
	s.damage_unit(bulwark, 3)
	assert_eq(bulwark.hp, bulwark.max_hp - 5, "deployed: full 3 damage")

func test_retrieve_shield_restores_bonus_and_clears_terrain() -> void:
	var s := _state()
	var bulwark := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	MechActions.execute(s, bulwark, "deploy_shield", Vector2i(6, 5))
	MechActions.execute(s, bulwark, "retrieve_shield", Vector2i(6, 5))
	assert_false(bulwark.shield_deployed)
	assert_null(s.object_at(Vector2i(6, 5)))

func test_shield_bash_pushes_two_tiles() -> void:
	var s := _state()
	var bulwark := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	MechActions.execute(s, bulwark, "shield_bash", Vector2i(6, 5))
	assert_eq(foe.pos, Vector2i(8, 5), "bash shoves two tiles")
	assert_eq(foe.hp, foe.max_hp - 2, "bash damage, no collision in the open")

func test_shield_bash_into_wall_adds_collision() -> void:
	var s := _state()
	var bulwark := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	s.grid.set_wall(Vector2i(7, 5), true)
	MechActions.execute(s, bulwark, "shield_bash", Vector2i(6, 5))
	# 2 bash + 2 collision into the wall = 4, grunt has 3 hp -> dead
	assert_false(foe.is_alive(), "bash + wall collision kills a 3hp grunt")

func test_line_attack_passes_through_deployed_shield() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	s.place_object(GridObject.make_shield(Vector2i(4, 5), 999))
	MechActions.execute(s, lancer, "throw_spear", Vector2i(6, 5))
	assert_false(foe.is_alive(), "the spear flew over the shield and killed the grunt")

# ------------------------------------------------------------------- grappler

func test_grapple_reels_an_enemy_in() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	MechActions.execute(s, grappler, "grapple", Vector2i(6, 5))
	assert_eq(foe.pos, Vector2i(3, 5), "default reel is the maximum pull, up to the grappler")
	assert_eq(foe.hp, foe.max_hp, "grapple deals no damage — its value is displacement")

func test_grapple_reels_an_ally_in() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var friend := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 5))
	assert_true(Vector2i(6, 5) in ActionPreview.valid_targets(s, grappler, "grapple"))
	MechActions.execute(s, grappler, "grapple", Vector2i(6, 5))
	assert_eq(friend.pos, Vector2i(3, 5), "allies can be pulled to safety too")

func test_grapple_does_not_chip_an_ally() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var friend := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(6, 5))
	MechActions.execute(s, grappler, "grapple", Vector2i(6, 5))
	assert_eq(friend.pos, Vector2i(3, 5))
	assert_eq(friend.hp, friend.max_hp, "reeling an ally is a pure rescue, no tether bite")

func test_grapple_on_a_wall_pulls_the_grappler() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	s.grid.set_wall(Vector2i(6, 5), true)
	var targets := ActionPreview.valid_targets(s, grappler, "grapple")
	assert_true(Vector2i(6, 5) in targets, "the wall is a valid anchor")
	MechActions.execute(s, grappler, "grapple", Vector2i(6, 5))
	assert_eq(grappler.pos, Vector2i(5, 5), "grappler yanks itself up against the wall")

func test_throw_hurls_an_adjacent_enemy_multiple_tiles() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 5))
	MechActions.execute(s, grappler, "throw", Vector2i(3, 5))
	assert_eq(foe.pos, Vector2i(6, 5), "flew three tiles")
	assert_eq(foe.hp, foe.max_hp, "clean throw into open space, no collision")

func test_throw_slams_enemy_into_enemy_hurting_both() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var thrown := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(3, 5))
	var wall_of_meat := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 5))
	MechActions.execute(s, grappler, "throw", Vector2i(3, 5))
	assert_eq(thrown.pos, Vector2i(4, 5), "stopped against the other unit")
	assert_eq(thrown.hp, thrown.max_hp - MechActions.GRAPPLER_THROW_COLLISION, "thrown unit takes collision damage")
	assert_eq(wall_of_meat.hp, wall_of_meat.max_hp - MechActions.GRAPPLER_THROW_COLLISION, "so does the one it hit")

func test_throw_can_target_an_ally() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var friend := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(3, 5))
	assert_true(Vector2i(3, 5) in ActionPreview.valid_targets(s, grappler, "throw"))
	MechActions.execute(s, grappler, "throw", Vector2i(3, 5))
	assert_eq(friend.pos, Vector2i(6, 5), "emergency repositioning of an ally")

# ------------------------------------------------------------------- preview

func test_preview_matches_execution_for_thrust_push() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	var foe := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 5))
	var p := ActionPreview.build(s, lancer, "thrust", Vector2i(6, 5))
	assert_true(p.valid)
	assert_eq(p.push_to, Vector2i(7, 5), "preview predicts the push destination")
	assert_true(foe.id in p.affected_ids)
	MechActions.execute(s, lancer, "thrust", Vector2i(6, 5))
	assert_eq(foe.pos, p.push_to, "execution lands where the preview said")

func test_preview_matches_execution_for_grapple_pull() -> void:
	var s := _state()
	var grappler := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(6, 5))
	var p := ActionPreview.build(s, grappler, "grapple", Vector2i(6, 5))
	assert_true(p.valid)
	assert_eq(p.push_to, Vector2i(3, 5), "preview predicts where the enemy lands")
	assert_true(foe.id in p.affected_ids)
	MechActions.execute(s, grappler, "grapple", Vector2i(6, 5))
	assert_eq(foe.pos, p.push_to, "execution matches the preview")

func test_preview_flags_friendly_fire_on_reactor() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 4))
	var p := ActionPreview.build(s, lancer, "throw_spear", Vector2i(6, 6))
	assert_true(p.valid)
	assert_true(p.hits_reactor, "preview warns the spear line clips the reactor")

func test_invalid_targets_are_rejected() -> void:
	var s := _state()
	var lancer := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(5, 5))
	assert_false(ActionPreview.build(s, lancer, "thrust", Vector2i(7, 5)).valid, "no unit there / not adjacent")
	assert_false(ActionPreview.build(s, lancer, "throw_spear", Vector2i(7, 7)).valid, "not a cardinal line")
