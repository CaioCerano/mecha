extends Node2D

## Entry point. Loads the battle scene. Placeholder until the view layer lands.

func _ready() -> void:
	var battle_scene: PackedScene = load("res://game/battle.tscn")
	if battle_scene != null:
		add_child(battle_scene.instantiate())
