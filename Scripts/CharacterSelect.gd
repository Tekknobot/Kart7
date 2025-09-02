extends Control

@export_file("*.tscn") var main_scene_path := "res://Scenes/main.tscn"
@export_file("*.tscn") var title_scene_path := "res://Scenes/Title.tscn"

@onready var grid: GridContainer   = $"Center/VBox/Grid"
@onready var back_btn: Button      = $"Center/VBox/Back"
@onready var select_title: Label   = $"Center/VBox/Title"

const DEFAULT_RACERS := [
	"Voltage","Grip","Torque","Razor","Havok","Blitz","Nitro","Rogue"
]

func _ready() -> void:	
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	# --- Style ONLY the title label ---
	if select_title:
		_style_label(
			select_title,
			28,
			Color.hex(0xFFFFFFFF),  # white text
			2,
			Color(0,0,0,0.90),      # dark outline
			Vector2(2,2),           # shadow offset
			Color(0,0,0,0.55)       # shadow color
		)
		_pulse(select_title, 1.03, 0.8)

	var names: Array = DEFAULT_RACERS
	if _has_prop(Globals, "racer_names"):
		names = Array(Globals.racer_names)

	# Assign names (if an instance didn't set racer_name) and connect pressed
	var i := 0
	for child in grid.get_children():
		if child is RacerButton:
			var nm := String(child.racer_name)
			if nm == "" and names.size() > 0:
				nm = names[i % names.size()]
				child.racer_name = StringName(nm)  # RacerButton updates its own label
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

# --------- helpers (positional args; 4.4.1-safe) ---------

func _style_label(l: Label, font_size: int, font_col: Color, outline_size: int, outline_col: Color, shadow_off: Vector2, shadow_col: Color) -> void:
	var ls := LabelSettings.new()
	ls.font_size = font_size
	ls.font_color = font_col
	ls.outline_size = outline_size
	ls.outline_color = outline_col
	ls.shadow_color = shadow_col
	ls.shadow_offset = shadow_off
	l.label_settings = ls
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _pulse(node: CanvasItem, scale_up: float, seconds_each_way: float) -> void:
	node.scale = Vector2.ONE
	var tw := create_tween()
	tw.set_loops()
	var s1 := tw.tween_property(node, "scale", Vector2(scale_up, scale_up), seconds_each_way)
	s1.set_trans(Tween.TRANS_SINE)
	s1.set_ease(Tween.EASE_IN_OUT)
	var s2 := tw.tween_property(node, "scale", Vector2.ONE, seconds_each_way)
	s2.set_trans(Tween.TRANS_SINE)
	s2.set_ease(Tween.EASE_IN_OUT)
