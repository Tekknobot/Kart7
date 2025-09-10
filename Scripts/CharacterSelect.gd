extends Control

@export_file("*.tscn") var main_scene_path  := "res://Scenes/Main.tscn"
@export_file("*.tscn") var title_scene_path := "res://Scenes/Title.tscn"
@export_file("*.tscn") var worldmap_scene_path := "res://Scenes/WorldMap.tscn"

@onready var grid: GridContainer   = $"Center/VBox/Grid"
@onready var back_btn: Button      = $"Center/VBox/Back"
@onready var select_title: Label   = $"Center/VBox/Title"
@onready var game_title: Label     = $"Center/VBox/GameTitle"
@onready var transition: ColorRect = get_node_or_null(^"Transition") as ColorRect

const DEFAULT_RACERS := [
	"Voltage","Grip","Torque","Razor","Havok","Blitz","Nitro","Rogue"
]

const RACER_COLOR_HEX := {
	"Voltage": 0xFFD54DFF, "Grip": 0x66BB6AFF, "Torque": 0xFF5F00FF, "Razor": 0xEF5350FF,
	"Havok": 0xAB47BCFF, "Blitz": 0x42A5F5FF, "Nitro": 0x76FF03FF, "Rogue": 0x26C6DAFF
}

var _is_transitioning := false
const FADE_IN_TIME  := 0.40
const FADE_OUT_TIME := 0.35

func _ready() -> void:
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	# Titles (unchanged)
	if select_title:
		_style_label(game_title, 32, Color.hex(0xEF5350FF), 2, Color(0,0,0,0.90), Vector2(2,2), Color(0,0,0,0.55))
		_style_label(select_title, 16, Color.hex(0xFFFFFFFF), 2, Color(0,0,0,0.90), Vector2(2,2), Color(0,0,0,0.55))
		_pulse(select_title, 1.03, 0.8)

	# Ensure the Transition overlay is ready (covers screen)
	_setup_transition_overlay()
	# Fade in from black when this scene appears
	_fade_in()  # fire-and-forget

	_populate_grid_unique()

	if back_btn:
		back_btn.pressed.connect(_back)

	_focus_first_racer()
	
	RenderingServer.set_default_clear_color(Color(0,0,0))

func _on_racer_pressed(name: String) -> void:
	if Globals.has_method("set_selected_racer"):
		Globals.set_selected_racer(name)
			
	await _fade_to_scene(worldmap_scene_path)

func _back() -> void:
	await _fade_to_scene(title_scene_path)

# --- TRANSITION HELPERS ---

func _setup_transition_overlay() -> void:
	if transition == null:
		push_warning("CharacterSelect: Transition ColorRect not found.")
		return
	transition.set_anchors_preset(Control.PRESET_FULL_RECT)
	transition.visible = true
	# Start fully opaque black so we can fade in
	var c := transition.color
	c.r = 0.0; c.g = 0.0; c.b = 0.0; c.a = 1.0
	transition.color = c

func _fade_in() -> void:
	if transition == null:
		return
	# Fade alpha 1 -> 0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(transition, "color:a", 0.0, FADE_IN_TIME)
	await tw.finished
	transition.visible = false

func _fade_out() -> void:
	if transition == null:
		return
	transition.visible = true
	# Ensure we start from current alpha (usually 0) -> 1
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(transition, "color:a", 1.0, FADE_OUT_TIME)
	await tw.finished

func _fade_to_scene(path: String) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true
	await _fade_out()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Could not load scene: %s" % path)
	_is_transitioning = false

# --- EXISTING HELPERS (unchanged) ---

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
	s1.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var s2 := tw.tween_property(node, "scale", Vector2.ONE, seconds_each_way)
	s2.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _next_unused(names: Array, used: Dictionary, start_idx: int) -> String:
	var n := names.size()
	var k := start_idx
	if n <= 0:
		return ""
	while k < start_idx + n:
		var cand := String(names[k % n])
		if not used.has(cand):
			return cand
		k += 1
	return String(names[start_idx % n])

func _populate_grid_unique() -> void:
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	var names: Array = DEFAULT_RACERS
	if _has_prop(Globals, "racer_names"):
		names = Array(Globals.racer_names)

	var used := {}
	var idx := 0

	for child in grid.get_children():
		if child is RacerButton:
			var nm := String(child.racer_name)
			if nm == "" or used.has(nm):
				nm = _next_unused(names, used, idx)
			child.set_racer_name(StringName(nm))
			child.refresh_from_globals()
			child.pressed.connect(Callable(self, "_on_racer_pressed").bind(nm))
			used[nm] = true
			idx += 1

	for nm in names:
		if not used.has(String(nm)):
			push_warning("CharacterSelect: missing racer '" + String(nm) + "' in grid.")
