class_name GameFlow
extends Node2D

## Only selections survive navigation. Battle runtime state is always fresh.
var loadout := SquadLoadout.new()
var mission_id: String = Mission.REACTOR_BREACH
var menu: LoadoutScreen
var battle: Battle

func _ready() -> void:
	show_loadout()
	# Dev shortcut: `godot ... -- battle [mission_id]` deploys the baseline squad
	# straight into a mission, for screenshotting / manual checks.
	var args := OS.get_cmdline_user_args()
	if "battle" in args:
		var i := args.find("battle")
		if i + 1 < args.size() and args[i + 1] in Mission.ids():
			menu.mission_id = args[i + 1]
		if "kit" in args:  # demo loadout on the Lancer, for screenshotting the dossier
			loadout.mechs[Unit.Kind.LANCER] = {
				"secondary_id": "impact_spear",
				"systems": ["vector_thrusters", "shock_absorbers"],
				"pilot_id": "ace"}
		deploy()

func show_loadout() -> void:
	if is_instance_valid(battle):
		remove_child(battle)
		battle.queue_free()
		battle = null
	menu = LoadoutScreen.new()
	menu.loadout = loadout
	menu.mission_id = mission_id
	add_child(menu)
	menu.deploy_requested.connect(deploy)

func deploy() -> void:
	if not loadout.validation_errors().is_empty():
		return
	mission_id = menu.mission_id
	remove_child(menu)
	menu.queue_free()
	menu = null
	battle = Battle.new()
	battle.mission_id = mission_id
	battle.squad_loadout = loadout.copy()
	battle.return_to_loadout.connect(show_loadout)
	add_child(battle)
