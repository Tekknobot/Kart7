# Scripts/AI/WaypointPlacer.gd
@tool
extends Node2D
@export var path_node: NodePath

func _unhandled_input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var wp := get_node_or_null(path_node)
		if wp and wp.has_method("get"):
			if wp.has_variable("points"):
				var p := get_viewport().get_mouse_position()
				wp.points.append(p)
				print("Added waypoint:", p)
