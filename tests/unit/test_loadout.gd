extends GutTest

func _state(kind: Unit.Kind = Unit.Kind.LANCER, secondary: String = "", systems: Array = [], pilot: String = "") -> BattleState:
	var loadout := SquadLoadout.new()
	if secondary != "": loadout.mechs[kind].secondary_id = secondary
	if not systems.is_empty(): loadout.mechs[kind].systems = systems
	loadout.mechs[kind].pilot_id = pilot
	var state := BattleState.new(Mission.reactor_breach(), loadout)
	state.units.clear()
	state.occupancy.clear()
	state.objects.clear()
	state.objects[state.reactor.pos] = state.reactor
	state.grid = Grid.new(12, 12)
	state.pending_spawns.clear()
	state.telegraphs.clear()
	var u := TestUtil.add(state, kind, Unit.Team.PLAYER, Vector2i(3, 4))
	u.ap = 2
	return state

func _actor(s: BattleState) -> Unit:
	return s.player_mechs()[0]

func _parity(s: BattleState, action: String, target: Vector2i, opts: Dictionary = {}) -> ActionPreview.Preview:
	var u := _actor(s)
	var before := var_to_bytes_with_objects(s)
	var p := ActionPreview.build(s, u, action, target, opts)
	assert_true(p.valid, action + " valid")
	assert_eq(var_to_bytes_with_objects(s), before, "preview does not mutate runtime or telemetry")
	if not p.valid: return p
	assert_true(s.player_action(u, action, target, opts), action + " executes")
	for id: int in s.units:
		var expected: Unit = p.outcome_state.units[id]
		assert_eq(s.units[id].pos, expected.pos, "position parity")
		assert_eq(s.units[id].hp, expected.hp, "HP parity")
		assert_eq(s.units[id].impaired_slot, expected.impaired_slot, "impairment parity")
	assert_eq(s.reactor.hp, p.outcome_state.reactor.hp)
	assert_eq(s.objects.keys(), p.outcome_state.objects.keys())
	return p

func test_default_loadout_actions() -> void:
	var s := BattleState.new()
	var expected := {Unit.Kind.LANCER: ["thrust", "throw_spear"], Unit.Kind.BULWARK: ["shield_bash", "deploy_shield"], Unit.Kind.GRAPPLER: ["grapple", "throw"]}
	for u: Unit in s.player_mechs():
		assert_eq(MechActions.available_actions(s, u), expected[u.kind] as Array[String])
		assert_eq(u.systems, ["", ""] as Array[String])
		assert_eq(u.pilot_id, "")

func test_invalid_secondary_rejected() -> void:
	var l := SquadLoadout.new()
	l.mechs[Unit.Kind.LANCER].secondary_id = "brace"
	assert_false(l.validation_errors().is_empty())

func test_duplicate_system_rejected_but_shared_across_frames_allowed() -> void:
	var l := SquadLoadout.new()
	l.mechs[Unit.Kind.LANCER].systems = ["stabilizers", "stabilizers"]
	assert_false(l.validation_errors().is_empty())
	l.mechs[Unit.Kind.LANCER].systems = ["stabilizers", ""]
	l.mechs[Unit.Kind.BULWARK].systems = ["stabilizers", ""]
	assert_true(l.validation_errors().is_empty())

func test_duplicate_pilot_and_unknown_ids_rejected() -> void:
	var l := SquadLoadout.new()
	l.mechs[Unit.Kind.LANCER].pilot_id = "ace"
	l.mechs[Unit.Kind.BULWARK].pilot_id = "ace"
	assert_false(l.validation_errors().is_empty())
	l.mechs[Unit.Kind.BULWARK].pilot_id = "unknown"
	assert_false(l.validation_errors().is_empty())
	l.mechs[Unit.Kind.BULWARK].pilot_id = ""
	l.mechs[Unit.Kind.LANCER].systems = ["unknown", ""]
	assert_false(l.validation_errors().is_empty())

func test_both_missions_receive_isolated_custom_loadout() -> void:
	var l := SquadLoadout.new()
	l.mechs[Unit.Kind.LANCER] = {"secondary_id": "impact_spear", "systems": ["stabilizers", "vector_thrusters"], "pilot_id": "ace"}
	for id: String in Mission.ids():
		var s := BattleState.new(Mission.by_id(id), l)
		var u := s.player_mechs()[0]
		assert_eq(u.secondary(), "impact_spear")
		assert_true(u.has_system("vector_thrusters"))
		assert_eq(u.pilot_id, "ace")
		u.systems[0] = ""
		assert_eq(l.mechs[Unit.Kind.LANCER].systems[0], "stabilizers")

func test_equipped_secondary_replaces_action_and_gates_execution() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear")
	var u := _actor(s)
	assert_eq(MechActions.available_actions(s, u), ["thrust", "impact_spear"] as Array[String])
	var before := var_to_bytes_with_objects(s)
	assert_false(s.player_action(u, "throw_spear", Vector2i(5, 4)))
	assert_false(ActionPreview.build(s, u, "throw_spear", Vector2i(5, 4)).valid)
	MechActions.execute(s, u, "throw_spear", Vector2i(5, 4))
	assert_eq(var_to_bytes_with_objects(s), before)

func test_heavy_and_stabilizers_reduce_incoming_force_to_zero() -> void:
	var s := _state(Unit.Kind.BULWARK, "brace", ["stabilizers", ""])
	var u := _actor(s)
	var enemy := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(1, 4))
	var p := Push.trace(s, u.pos, Vector2i.RIGHT, 2, enemy.id)
	var r := Push.resolve(s, u, Vector2i.RIGHT, 2, 2, enemy.id)
	assert_eq(r.final_pos, p.final)
	assert_eq(u.pos, Vector2i(3, 4))
	assert_eq(u.hp, u.max_hp)
	Push.resolve(s, u, Vector2i.RIGHT, 3, 2, enemy.id)
	assert_eq(u.pos, Vector2i(4, 4))

func test_category_action_preview_matches_execution() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear")
	var heavy := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.ENEMY, Vector2i(5, 4))
	_parity(s, "impact_spear", heavy.pos)
	assert_eq(heavy.pos, Vector2i(6, 4))

func test_impact_spear_push_and_collision_parity() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear")
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 4))
	s.grid.set_wall(Vector2i(7, 4), true)
	_parity(s, "impact_spear", enemy.pos)
	assert_eq(enemy.pos, Vector2i(6, 4))
	assert_eq(enemy.hp, 1)
	assert_true(_actor(s).has_spear)
	assert_eq(s.objects.size(), 1)

func test_thermal_lance_terrain_explosion_parity() -> void:
	var s := _state(Unit.Kind.LANCER, "thermal_lance")
	s.objects[Vector2i(5, 4)] = GridObject.make_explosive(Vector2i(5, 4), 2)
	var enemy := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(5, 3))
	var p := _parity(s, "thermal_lance", Vector2i(5, 4))
	assert_false(p.explosion_cells.is_empty())
	assert_false(enemy.is_alive())
	assert_true(_actor(s).has_spear)

func test_thermal_lance_is_range_two_without_push() -> void:
	var s := _state(Unit.Kind.LANCER, "thermal_lance")
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 4))
	var p := _parity(s, "thermal_lance", enemy.pos)
	assert_true(p.displacements.is_empty())
	assert_eq(enemy.hp, 1)
	assert_false(Vector2i(6, 4) in ActionPreview.valid_targets(s, _actor(s), "thermal_lance"))

func test_brace_blocks_enemy_force_until_next_player_phase() -> void:
	var s := _state(Unit.Kind.BULWARK, "brace")
	var u := _actor(s)
	_parity(s, "brace", u.pos)
	var enemy := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(1, 4))
	assert_true(u.braced)
	assert_eq(Push.trace(s, u.pos, Vector2i.RIGHT, 5, enemy.id).final, u.pos)
	Push.resolve(s, u, Vector2i.RIGHT, 5, 3, enemy.id)
	assert_eq(u.pos, Vector2i(3, 4))
	s._start_player_turn()
	assert_false(u.braced)
	assert_eq(Push.trace(s, u.pos, Vector2i.RIGHT, 2, enemy.id).final, Vector2i(4, 4))

func test_repulsor_plate_zero_direct_damage_collision_parity() -> void:
	var s := _state(Unit.Kind.BULWARK, "repulsor_plate")
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(4, 4))
	s.grid.set_wall(Vector2i(6, 4), true)
	_parity(s, "repulsor_plate", enemy.pos)
	assert_eq(enemy.hp, 2)
	assert_eq(enemy.pos, Vector2i(5, 4))

func test_anchor_replaces_owned_object_and_supports_grapple() -> void:
	var s := _state(Unit.Kind.GRAPPLER, "anchor_shot")
	var u := _actor(s)
	_parity(s, "anchor_shot", Vector2i(6, 4))
	assert_false(s.object_at(Vector2i(6, 4)).blocks_move())
	assert_true(s.object_at(Vector2i(6, 4)).blocks_forced_move())
	assert_true(Vector2i(6, 4) in ActionPreview.valid_targets(s, u, "grapple"))
	_parity(s, "anchor_shot", Vector2i(3, 1))
	assert_null(s.object_at(Vector2i(6, 4)))
	u.ap = 2
	_parity(s, "grapple", Vector2i(3, 1), {"dest": Vector2i(3, 2)})
	assert_eq(u.pos, Vector2i(3, 2))

func test_anchor_cannot_replace_occupied_or_hazard_tile() -> void:
	var s := _state(Unit.Kind.GRAPPLER, "anchor_shot")
	s.objects[Vector2i(5, 4)] = GridObject.make_pit(Vector2i(5, 4))
	assert_false(s.player_action(_actor(s), "anchor_shot", Vector2i(5, 4)))
	assert_false(s.player_action(_actor(s), "anchor_shot", Vector2i(7, 4)))

func test_tow_cable_safe_two_stage_parity() -> void:
	var s := _state(Unit.Kind.GRAPPLER, "tow_cable")
	var ally := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(6, 4))
	_parity(s, "tow_cable", ally.pos, {"dest": Vector2i(4, 4)})
	assert_eq(ally.pos, Vector2i(4, 4), "willing Heavy rescue moves full distance")
	assert_eq(ally.hp, ally.max_hp)

func test_tow_cable_rejects_pit_blocker_and_enemy() -> void:
	var s := _state(Unit.Kind.GRAPPLER, "tow_cable")
	var ally := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 4))
	s.objects[Vector2i(5, 4)] = GridObject.make_pit(Vector2i(5, 4))
	assert_false(ActionPreview.build(s, _actor(s), "tow_cable", ally.pos).valid)
	assert_false(s.player_action(_actor(s), "tow_cable", ally.pos, {"dest": Vector2i(5, 4)}))
	var enemy := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 2))
	assert_false(ActionPreview.build(s, _actor(s), "tow_cable", enemy.pos).valid)

func test_thrusters_first_move_then_turn_reset() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", ["vector_thrusters", ""])
	var u := _actor(s)
	assert_eq(u.movement(), 6)
	assert_true(s.player_move(u, Vector2i(4, 4)))
	assert_eq(u.movement(), 5)
	assert_eq(s.tel.c.get("system:vector_thrusters"), 1)
	s._start_player_turn()
	assert_eq(u.movement(), 6)
	var baseline := _state()
	assert_eq(_actor(baseline).movement(), 5)

func test_actuators_extend_existing_push_and_throw_planner() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", ["reinforced_actuators", ""])
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 4))
	_parity(s, "impact_spear", enemy.pos)
	assert_eq(enemy.pos, Vector2i(8, 4))
	var g := _state(Unit.Kind.GRAPPLER, "throw", ["reinforced_actuators", ""])
	var foe := TestUtil.add(g, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 3))
	_parity(g, "throw", foe.pos, {"dest": Vector2i(7, 3)})
	assert_eq(foe.pos, Vector2i(7, 3))

func test_shock_absorbers_collision_mitigation_parity() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear")
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 4))
	enemy.systems = ["shock_absorbers", ""]
	s.grid.set_wall(Vector2i(6, 4), true)
	_parity(s, "impact_spear", enemy.pos)
	assert_eq(enemy.hp, 2)
	assert_eq(enemy.mitigate(1, "collision"), 0)
	assert_eq(enemy.mitigate(1), 1)

func test_winch_once_per_mission_safe_free_and_not_reset_each_turn() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", ["emergency_winch", ""])
	var u := _actor(s)
	var ally := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(4, 4))
	u.ap = 0
	_parity(s, "emergency_winch", ally.pos, {"dest": Vector2i(4, 3)})
	assert_eq(u.ap, 0)
	assert_true(u.winch_used)
	s._start_player_turn()
	assert_false("emergency_winch" in MechActions.available_actions(s, u))
	assert_true(u.winch_used)

func test_winch_rejects_unsafe_destination_without_consuming_charge() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", ["emergency_winch", ""])
	var ally := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(4, 4))
	s.objects[Vector2i(4, 3)] = GridObject.make_pit(Vector2i(4, 3))
	assert_false(s.player_action(_actor(s), "emergency_winch", ally.pos, {"dest": Vector2i(4, 3)}))
	assert_false(_actor(s).winch_used)

func test_ace_move_distance_next_action_and_reset() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", [], "ace")
	var u := _actor(s)
	assert_true(s.player_move(u, Vector2i(3, 1)))
	assert_eq(u.push_bonus(), 1)
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(5, 1))
	_parity(s, "impact_spear", enemy.pos)
	assert_eq(enemy.pos, Vector2i(8, 1))
	assert_eq(u.push_bonus(), 0)
	assert_true(u.ace_used)
	s._start_player_turn()
	assert_false(u.ace_used)
	assert_eq(u.moved_this_turn, 0)

func test_brawler_only_first_collision_per_turn() -> void:
	var s := _state(Unit.Kind.BULWARK, "repulsor_plate", [], "brawler")
	var enemy := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(4, 4))
	enemy.hp = 10
	enemy.max_hp = 10
	s.grid.set_wall(Vector2i(5, 4), true)
	_parity(s, "repulsor_plate", enemy.pos)
	assert_eq(enemy.hp, 7)
	_parity(s, "repulsor_plate", enemy.pos)
	assert_eq(enemy.hp, 5)
	assert_eq(s.tel.c.get("pilot:brawler"), 1)
	s._start_player_turn()
	assert_false(_actor(s).brawler_used)

func test_rescuer_refunds_once_per_turn() -> void:
	var s := _state(Unit.Kind.GRAPPLER, "tow_cable", [], "rescuer")
	var ally := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 4))
	_parity(s, "tow_cable", ally.pos, {"dest": Vector2i(5, 4)})
	assert_eq(_actor(s).ap, 2)
	_parity(s, "tow_cable", ally.pos, {"dest": Vector2i(4, 4)})
	assert_eq(_actor(s).ap, 1)
	assert_eq(s.tel.c.get("pilot:rescuer"), 1)
	s._start_player_turn()
	assert_false(_actor(s).rescuer_used)

func test_damage_thresholds_and_critical_movement() -> void:
	var u := Unit.new()
	u.max_hp = 8
	u.move_range = 4
	for pair: Array in [[8, 0], [5, 0], [4, 1], [3, 1], [2, 2], [1, 2], [0, 3]]:
		u.hp = pair[0]
		assert_eq(int(u.damage_state()), pair[1])
	u.hp = 2
	assert_eq(u.movement(), 3)

func test_impairment_chooses_slot_two_then_falls_back_to_one() -> void:
	for systems: Array in [["vector_thrusters", "stabilizers"], ["vector_thrusters", ""]]:
		var s := _state(Unit.Kind.LANCER, "impact_spear", systems)
		var u := _actor(s)
		s.damage_unit(u, 3)
		assert_eq(u.impaired_slot, 1 if systems[1] != "" else 0)
		assert_false(u.has_system(u.systems[u.impaired_slot]))
		assert_eq(s.tel.c.get("condition:DAMAGED"), 1)

func test_engineer_restores_system_without_immediately_reimpairing() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", ["vector_thrusters", "stabilizers"], "engineer")
	var u := _actor(s)
	s.damage_unit(u, 3)
	assert_eq(u.impaired_slot, 1)
	_parity(s, "engineer_repair", u.pos)
	assert_eq(u.impaired_slot, -1)
	assert_true(u.has_system("stabilizers"))
	s.damage_unit(u, 1)
	assert_eq(u.impaired_slot, -1)
	s._start_player_turn()
	assert_true(u.engineer_used)
	assert_false("engineer_repair" in MechActions.available_actions(s, u))

func test_engineer_without_system_improves_one_condition_step() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", [], "engineer")
	var u := _actor(s)
	s.damage_unit(u, 5)
	assert_eq(u.damage_state(), Unit.DamageState.CRITICAL)
	_parity(s, "engineer_repair", u.pos)
	assert_eq(u.damage_state(), Unit.DamageState.DAMAGED)
	assert_eq(u.hp, 2)

func test_impaired_winch_unavailable_and_no_unequipped_system_actions() -> void:
	var s := _state(Unit.Kind.LANCER, "impact_spear", ["", "emergency_winch"])
	var u := _actor(s)
	s.damage_unit(u, 3)
	assert_false("emergency_winch" in MechActions.available_actions(s, u))
	assert_false("engineer_repair" in MechActions.available_actions(s, u))
	assert_eq(u.push_bonus(), 0)
