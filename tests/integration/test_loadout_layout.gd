extends GutTest

## Regression: LoadoutScreen is parented under GameFlow (a Node2D), so Control
## anchor presets have no rect to resolve against. The screen must still fill the
## viewport and lay out the active mech's identity panel + four config columns.
func test_active_mech_config_is_laid_out_under_node2d_parent() -> void:
	var flow := GameFlow.new()
	add_child_autofree(flow)
	await get_tree().process_frame
	await get_tree().process_frame
	var menu: LoadoutScreen = flow.menu
	assert_gt(menu.size.x, 100.0, "screen filled the viewport width")
	assert_gt(menu.size.y, 100.0, "screen filled the viewport height")
	assert_eq(menu.active_kind, Unit.Kind.LANCER, "Lancer shown first")
	assert_eq(menu.selectors.size(), 4, "secondary + 2 systems + pilot")
	assert_gt(menu._config_host.get_global_rect().size.x, 400.0, "config area has real width")
	assert_gt(menu._config_host.get_global_rect().size.y, 200.0, "config area has real height")

	# roster switch rebuilds the whole config for another frame
	menu.active_kind = Unit.Kind.GRAPPLER
	menu._rebuild_config()
	for entry: Dictionary in menu.selectors:
		assert_eq(entry.kind, Unit.Kind.GRAPPLER, "selectors follow the roster")
	var secondary: Dictionary = menu.selectors.filter(
		func(e: Dictionary) -> bool: return e.field == "secondary_id")[0]
	assert_true("anchor_shot" in secondary.options, "Grappler's own secondaries are offered")
	assert_false("impact_spear" in secondary.options, "not another frame's secondaries")
