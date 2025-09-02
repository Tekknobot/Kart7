extends Control

@export_file("*.tscn") var main_scene_path := "res://Scenes/main.tscn"
@export_file("*.tscn") var title_scene_path := "res://Scenes/Title.tscn"

@onready var grid: GridContainer = $"Center/VBox/Grid"
@onready var back_btn: Button = $"Center/VBox/Back"

const DEFAULT_RACERS := [
	"Voltage","Grip","Torque","Razor","Havok","Blitz","Nitro","Rogue"
]

func _ready() -> void:	
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	var names: Array = DEFAULT_RACERS
	if _has_prop(Globals, "racer_names"):   # If you expose a PackedStringArray there
		names = Array(Globals.racer_names)  # convert to Array for consistency
		
	# Assign names (if an instance didn't set racer_name) and connect pressed
	var i := 0
	for child in grid.get_children():
		if child is RacerButton:
			var nm := String(child.racer_name)
			if nm == "" and names.size() > 0:
				nm = names[i % names.size()]
				child.racer_name = StringName(nm)
				# Label text auto-updates from racer_name in RacerButton.gd
			child.pressed.connect(func(n := nm): _choose(n))
			i += 1

	if back_btn:
		back_btn.pressed.connect(_back)

	_focus_first_racer()

func _choose(name: String) -> void:
	if Globals.has_method("set_selected_racer"):
		Globals.set_selected_racer(name)
	elif _has_prop(Globals, "selected_racer"):
		Globals.selected_racer = name

	var err := get_tree().change_scene_to_file(main_scene_path)
	if err != OK:
		push_error("Could not load main scene at: %s" % main_scene_path)

func _back() -> void:
	var err := get_tree().change_scene_to_file(title_scene_path)
	if err != OK:
		push_error("Could not load title scene at: %s" % title_scene_path)

func _focus_first_racer() -> void:
	for child in grid.get_children():
		if child is Button:
			child.grab_focus()
			return

func _has_prop(obj: Object, prop: StringName) -> bool:
	for p in obj.get_property_list():
		if p.has("name") and p["name"] == prop:
			return true
	return false
