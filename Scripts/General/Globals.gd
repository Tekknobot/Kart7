# Globals.gd
extends Node

var screenSize: Vector2 = Vector2(480, 360)

enum RoadType { VOID, ROAD, GRAVEL, OFF_ROAD, WALL, SINK }

var _camera_map_pos: Vector2 = Vector2.ZERO

func set_camera_map_position(p: Vector2) -> void:
	_camera_map_pos = p

func get_camera_map_position() -> Vector2:
	return _camera_map_pos
