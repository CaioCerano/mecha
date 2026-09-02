extends GutTest

## The core rule: what the preview says == what execution does. Regression
## coverage for the two known gaps this pass closed -- Bulwark stow mitigation
## in collision previews, and the Charger-into-a-pit outcome.

func _state() -> BattleState:
	var s := TestUtil.bare_state()
	for w in s.grid.wall_cells():
		s.grid.set_wall(w, false)
	return s

# ------------------------------------------------- Bulwark stow mitigation

func test_stowed_bulwark_collision_preview_matches_execution() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	g.ap = 2
	var b := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))   # stowed -> -1
	var foe := TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 5))

	var p := ActionPreview.build(s, g, "throw", Vector2i(3, 5), {"dest": Vector2i(5, 5)})
	assert_true(p.valid)
	var predicted := -1
	for h in p.hits:
		if h["id"] == b.id:
			predicted = h["amount"]
	assert_eq(predicted, MechActions.GRAPPLER_THROW_COLLISION - 1, "preview mitigates the stowed Bulwark by 1")

	var before := b.hp
	MechActions.execute(s, g, "throw", Vector2i(3, 5), {"dest": Vector2i(5, 5)})
	assert_eq(before - b.hp, predicted, "and execution deals exactly the previewed amount")

func test_deployed_bulwark_takes_full_collision_in_preview_and_execution() -> void:
	var s := _state()
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	g.ap = 2
	var b := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 5))
	b.shield_deployed = true   # bonus gone
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 5))

	var p := ActionPreview.build(s, g, "throw", Vector2i(3, 5), {"dest": Vector2i(5, 5)})
	var predicted := -1
	for h in p.hits:
		if h["id"] == b.id:
			predicted = h["amount"]
	assert_eq(predicted, MechActions.GRAPPLER_THROW_COLLISION, "no mitigation while deployed")
	var before := b.hp
	MechActions.execute(s, g, "throw", Vector2i(3, 5), {"dest": Vector2i(5, 5)})
	assert_eq(before - b.hp, predicted)

func test_stowed_bulwark_explosion_preview_matches_execution() -> void:
	var s := _state()
	var b := TestUtil.add(s, Unit.Kind.BULWARK, Unit.Team.PLAYER, Vector2i(5, 4))   # stowed, in the blast
	var g := TestUtil.add(s, Unit.Kind.GRAPPLER, Unit.Team.PLAYER, Vector2i(2, 5))
	g.ap = 2
	TestUtil.add(s, Unit.Kind.GRUNT, Unit.Team.ENEMY, Vector2i(3, 5))
	s.objects[Vector2i(5, 5)] = GridObject.make_explosive(Vector2i(5, 5), Mission.EXPLOSIVE_HP)

	var p := ActionPreview.build(s, g, "throw", Vector2i(3, 5), {"dest": Vector2i(5, 5)})
	assert_true(p.valid)
	var predicted := -1
	for h in p.hits:
		if h["id"] == b.id:
			predicted = h["amount"]
	assert_eq(predicted, Mission.EXPLOSIVE_DMG - 1, "blast on a stowed Bulwark is mitigated in the preview, once")
	var before := b.hp
	MechActions.execute(s, g, "throw", Vector2i(3, 5), {"dest": Vector2i(5, 5)})
	assert_eq(before - b.hp, predicted)

# ------------------------------------------------- Charger + pit

func test_charge_into_pit_outcome_matches_execution() -> void:
	var s := _state()
	var c := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 0))
	s.objects[Vector2i(6, 3)] = GridObject.make_pit(Vector2i(6, 3))
	s.telegraphs.append(Telegraph.charge(c.id, [] as Array[Vector2i], Vector2i(0, 1), Mission.CHARGER_DMG, 99))

	var oc := Intent.charge_outcome(s, c.pos, Vector2i(0, 1), {}, [])
	assert_true(oc["pit"], "prediction: this charge ends in the pit")
	assert_eq(oc["stop"], Vector2i(6, 3))

	s.turn_number = 99
	s._resolve_telegraph(s.telegraphs[0])
	assert_eq(c.pos, Vector2i(6, 3), "execution: charger ended in the pit cell")
	assert_false(c.is_alive(), "and was destroyed -- exactly as predicted")

func test_moving_a_blocker_turns_a_normal_charge_into_a_pit_self_destruct() -> void:
	var s := _state()
	var c := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 1))
	var mech := TestUtil.add(s, Unit.Kind.LANCER, Unit.Team.PLAYER, Vector2i(6, 2))
	s.objects[Vector2i(6, 3)] = GridObject.make_pit(Vector2i(6, 3))
	s.telegraphs.append(Telegraph.charge(c.id, [] as Array[Vector2i], Vector2i(0, 1), Mission.CHARGER_DMG, 99))

	assert_false(Intent.charge_outcome(s, c.pos, Vector2i(0, 1), {}, [])["pit"], "baseline: bonks the Lancer, no pit")
	var changes := Intent.project(s, {mech.id: Vector2i(2, 2)}, [] as Array)
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_eq(ch.kind, "charge")
	assert_true(ch.destroyed, "with the Lancer pulled away the charge runs into the pit -- Charger OUT")
	assert_true(ch.interrupted, "and the Lancer is safe")
	assert_eq(ch.safe_cell, Vector2i(6, 2))

func test_blocker_keeps_a_charger_out_of_a_pit() -> void:
	var s := _state()
	var c := TestUtil.add(s, Unit.Kind.CHARGER, Unit.Team.ENEMY, Vector2i(6, 0))
	s.objects[Vector2i(6, 3)] = GridObject.make_pit(Vector2i(6, 3))
	s.telegraphs.append(Telegraph.charge(c.id, [] as Array[Vector2i], Vector2i(0, 1), Mission.CHARGER_DMG, 99))

	assert_true(Intent.charge_outcome(s, c.pos, Vector2i(0, 1), {}, [])["pit"], "baseline: it self-destructs")
	var changes := Intent.project(s, {}, [Vector2i(6, 2)] as Array)
	assert_eq(changes.size(), 1)
	var ch: Intent.Change = changes[0]
	assert_false(ch.destroyed, "a blocker before the pit saves the charger")
	assert_eq(ch.projected_dest, Vector2i(6, 1), "it stops one tile short of the blocker")
