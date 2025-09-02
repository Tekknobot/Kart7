# Globals.gd
extends Node

var screenSize: Vector2 = Vector2(480, 360)

enum RoadType { VOID, ROAD, GRAVEL, OFF_ROAD, WALL, SINK }

var _camera_map_pos: Vector2 = Vector2.ZERO
var race_can_drive: bool = false   # false = lock all racers until GO

# --- Character select state ---
var racer_names := PackedStringArray([
	"Voltage","Grip","Torque","Razor","Havok","Blitz","Nitro","Rogue"
])

var selected_racer: StringName = "Voltage"  # default

func set_camera_map_position(p: Vector2) -> void:
	_camera_map_pos = p

func get_camera_map_position() -> Vector2:
	return _camera_map_pos

func set_selected_racer(name: String) -> void:
	if name in racer_names:
		selected_racer = name
