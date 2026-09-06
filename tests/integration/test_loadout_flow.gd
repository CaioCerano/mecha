extends GutTest

func test_launch_deploy_restart_and_return_preserve_selections() -> void:
	var flow := GameFlow.new()
	add_child_autofree(flow)
	assert_not_null(flow.menu)
	assert_null(flow.battle)
	flow.loadout.mechs[Unit.Kind.LANCER] = {"secondary_id": "thermal_lance", "systems": ["vector_thrusters", "shock_absorbers"], "pilot_id": "ace"}
	flow.menu.mission_id = Mission.THE_CHOKEPOINT
	flow.menu.deploy_requested.emit()
	assert_not_null(flow.battle)
	assert_eq(flow.battle.state.data.id, Mission.THE_CHOKEPOINT)
	var first := flow.battle.state.player_mechs()[0]
	assert_eq(first.secondary(), "thermal_lance")
	first.winch_used = true
	flow.battle.state.damage_unit(first, 3)
	flow.battle.hud.restart_pressed.emit()
	assert_eq(flow.battle.state.player_mechs()[0].hp, 6)
	assert_eq(flow.battle.state.player_mechs()[0].secondary(), "thermal_lance")
	assert_false(flow.battle.state.player_mechs()[0].winch_used)
	flow.battle.hud.loadout_pressed.emit()
	assert_null(flow.battle)
	assert_not_null(flow.menu)
	assert_eq(flow.menu.mission_id, Mission.THE_CHOKEPOINT)
	assert_eq(flow.menu.loadout.mechs[Unit.Kind.LANCER].pilot_id, "ace")
	flow.menu.loadout.mechs[Unit.Kind.LANCER].secondary_id = "impact_spear"
	flow.menu.deploy_requested.emit()
	assert_eq(flow.battle.state.player_mechs()[0].secondary(), "impact_spear")
	await get_tree().process_frame
	await get_tree().process_frame

func test_menu_disables_duplicate_system_and_pilot_choices() -> void:
	var menu := LoadoutScreen.new()
	add_child_autofree(menu)
	menu.loadout.mechs[Unit.Kind.LANCER].systems = ["stabilizers", ""]
	menu.loadout.mechs[Unit.Kind.LANCER].pilot_id = "ace"
	menu.active_kind = Unit.Kind.LANCER
	menu._rebuild_config()
	for entry: Dictionary in menu.selectors:
		if entry.field == "systems" and entry.slot == 1:
			assert_true("stabilizers" in entry.disabled_ids, "the taken System is blocked in the other slot")
	menu.active_kind = Unit.Kind.BULWARK
	menu._rebuild_config()
	for entry: Dictionary in menu.selectors:
		if entry.field == "pilot_id":
			assert_true("ace" in entry.disabled_ids, "a Pilot taken by another mech is blocked")
	menu.loadout.mechs[Unit.Kind.LANCER].secondary_id = "brace"
	menu._rebuild_config()
	assert_true(menu._deploy.disabled, "invalid loadout disables Deploy")

func test_targeting_suite_emphasizes_known_intent_only_when_active() -> void:
	var b := Battle.new()
	b.squad_loadout.mechs[Unit.Kind.LANCER].systems = ["targeting_suite", ""]
	add_child_autofree(b)
	var u := b.state.player_mechs()[0]
	b._on_mech_chosen(u.id)
	assert_true(b._suite_intersects([u.pos]))
	assert_false(b._suite_intersects([Vector2i(-1, -1)]))
	assert_eq(b.state.tel.c.get("system:targeting_suite"), 1)
	b._on_mech_chosen(u.id)
	assert_eq(b.state.tel.c.get("system:targeting_suite"), 1)
	u.impaired_slot = 0
	assert_false(b._suite_intersects([u.pos]))

func test_custom_hud_exposes_build_damage_and_status() -> void:
	var s := BattleState.new()
	var u := s.player_mechs()[0]
	u.systems = ["stabilizers", "emergency_winch"]
	u.pilot_id = "engineer"
	s.damage_unit(u, 3)
	var summary := Hud.build_summary(u)
	for text: String in ["LIGHT", "DAMAGED", "IMPAIRED", "Engineer", "Emergency Winch"]:
		assert_string_contains(summary, text)
