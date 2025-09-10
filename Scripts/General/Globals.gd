# Globals.gd
extends Node

var screenSize: Vector2 = Vector2(640, 360)

enum RoadType { VOID, ROAD, GRAVEL, OFF_ROAD, WALL, SINK }

var _camera_map_pos: Vector2 = Vector2.ZERO
var race_can_drive: bool = false   # false = lock all racers until GO
var selected_color: Color = Color.WHITE

# --- Character select state ---
var racer_names := PackedStringArray([
	"Voltage","Grip","Torque","Razor","Havok","Blitz","Nitro","Rogue"
])

var selected_racer: StringName = "Voltage"  # default

# --- Racer color map (hex ints -> Color.hex) ---
const RACER_COLOR_HEX := {
	"Voltage": 0xFFD54DFF, # gold
	"Grip":    0x66BB6AFF, # green
	"Torque":  0xFF5F00FF, # orange
	"Razor":   0xEF5350FF, # red
	"Havok":   0xAB47BCFF, # purple
	"Blitz":   0x42A5F5FF, # blue
	"Nitro":   0x76FF03FF, # neon lime
	"Rogue":   0x26C6DAFF  # cyan
}

const RACER_COLOR_NAME := {
	"Voltage": "Gold",
	"Grip":    "Green",
	"Torque":  "Orange",
	"Razor":   "Red",
	"Havok":   "Purple",
	"Blitz":   "Blue",
	"Nitro":   "Lime",
	"Rogue":   "Cyan"
}

# --- Selected city shared across scenes ---
var selected_city: StringName = "New York"

func set_selected_city(name: String) -> void:
	selected_city = StringName(name)

func get_selected_city() -> String:
	return String(selected_city)

func set_camera_map_position(p: Vector2) -> void:
	_camera_map_pos = p

func get_camera_map_position() -> Vector2:
	return _camera_map_pos
	
func get_racer_color(name: String) -> Color:
	if RACER_COLOR_HEX.has(name):
		return Color.hex(int(RACER_COLOR_HEX[name]))
	return Color.WHITE

func get_racer_color_name(name: String) -> String:
	return RACER_COLOR_NAME.get(name, "White")

func set_selected_racer(name: String) -> void:
	selected_racer = StringName(name)
	selected_color = get_racer_color(name)
