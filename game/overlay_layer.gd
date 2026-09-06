class_name OverlayLayer
extends Node2D

## All the battlefield feedback drawn on top of the terrain: movement range,
## action target cells, attack lines, AoE, push destination, spear landing,
## and the persistent enemy telegraphs. battle.gd rebuilds the layer set each
## refresh; draw order is insertion order.



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
			var polygon := GridView.cell_polygon(c)
			if spec["ring"]:
				draw_arc(GridView.cell_to_world(c), GridView.HALF_HEIGHT * 0.72, 0.0, TAU, 28, color, 2.0, true)
			elif spec["filled"]:
				draw_colored_polygon(polygon, color)
			else:
				draw_polyline(polygon + PackedVector2Array([polygon[0]]), color, 2.0, true)
