class_name OverlayLayer
extends Node2D

## All the battlefield feedback drawn on top of the terrain: movement range,
## action target cells, attack lines, AoE, push destination, spear landing,
## and the persistent enemy telegraphs. battle.gd rebuilds the layer set each
## refresh; draw order is insertion order.

const CELL: int = GridView.CELL

## name -> { cells:Array[Vector2i], color:Color, filled:bool, ring:bool }
var _layers: Dictionary = {}

func clear_all() -> void:
	_layers.clear()
	queue_redraw()

func set_fill(layer_name: String, cells: Array, color: Color) -> void:
	_layers[layer_name] = {"cells": cells, "color": color, "filled": true, "ring": false}
	queue_redraw()

func set_outline(layer_name: String, cells: Array, color: Color) -> void:
	_layers[layer_name] = {"cells": cells, "color": color, "filled": false, "ring": false}
	queue_redraw()

func set_rings(layer_name: String, cells: Array, color: Color) -> void:
	_layers[layer_name] = {"cells": cells, "color": color, "filled": false, "ring": true}
	queue_redraw()

func _draw() -> void:
	for layer_name: String in _layers:
		var spec: Dictionary = _layers[layer_name]
		var color: Color = spec["color"]
		for c: Vector2i in spec["cells"]:
			var top_left: Vector2 = GridView.ORIGIN + Vector2(c.x * CELL, c.y * CELL)
			if spec["ring"]:
				draw_arc(top_left + Vector2(CELL, CELL) * 0.5, CELL * 0.36, 0.0, TAU, 28, color, 3.0, true)
			elif spec["filled"]:
				draw_rect(Rect2(top_left, Vector2(CELL, CELL)), color)
			else:
				draw_rect(Rect2(top_left + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)), color, false, 3.0)
