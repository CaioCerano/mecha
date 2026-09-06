extends GutTest

## Guards the `-- battle kit` dev path: deploying a customised squad straight
## into a mission must start at turn 1, player phase, every mech at full AP,
## enemies unmoved.
func test_kit_flow_starts_clean() -> void:
	var flow := GameFlow.new()
	flow.loadout.mechs[Unit.Kind.LANCER] = {
		"secondary_id": "impact_spear",
		"systems": ["vector_thrusters", "shock_absorbers"],
		"pilot_id": "ace"}
	add_child_autofree(flow)
	flow.menu.deploy_requested.emit()
	await get_tree().process_frame
	var s: BattleState = flow.battle.state
	assert_eq(s.turn_number, 1, "turn 1")
	assert_eq(s.phase, BattleState.Phase.PLAYER, "player phase")
	for m: Unit in s.player_mechs():
		assert_eq(m.ap, m.max_ap, "%s starts with full AP" % m.display_name())
	assert_true(s.telegraphs.is_empty(), "no enemy has acted yet")

func test_bare_battlestate_kit_full_ap() -> void:
	var l := SquadLoadout.new()
	l.mechs[Unit.Kind.LANCER] = {
		"secondary_id": "impact_spear",
		"systems": ["vector_thrusters", "shock_absorbers"],
		"pilot_id": "ace"}
	var s := BattleState.new(Mission.reactor_breach(), l)
	for m: Unit in s.player_mechs():
		assert_eq(m.ap, m.max_ap, "%s full AP from BattleState.new" % m.display_name())
