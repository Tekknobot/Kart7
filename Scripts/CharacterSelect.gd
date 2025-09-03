extends Control

@export_file("*.tscn") var main_scene_path := "res://Scenes/main.tscn"
@export_file("*.tscn") var title_scene_path := "res://Scenes/Title.tscn"

@onready var grid: GridContainer   = $"Center/VBox/Grid"
@onready var back_btn: Button      = $"Center/VBox/Back"
@onready var select_title: Label   = $"Center/VBox/Title"

const DEFAULT_RACERS := [
	"Voltage","Grip","Torque","Razor","Havok","Blitz","Nitro","Rogue"
]
# Use hex ints so this can be const (convert to Color when used)
const RACER_COLOR_HEX := {
	"Voltage": 0xFFD54DFF,
	"Grip":    0x66BB6AFF,
	"Torque":  0xFF5F00FF,
	"Razor":   0xEF5350FF,
	"Havok":   0xAB47BCFF,
	"Blitz":   0x42A5F5FF,
	"Nitro":   0x76FF03FF,
	"Rogue":   0x26C6DAFF
}

func _ready() -> void:
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	# title style (unchanged)
	if select_title:
		_style_label(select_title, 16, Color.hex(0xFFFFFFFF), 2, Color(0,0,0,0.90), Vector2(2,2), Color(0,0,0,0.55))
		_pulse(select_title, 1.03, 0.8)

	# ✅ deterministically assign unique names/colors to every RacerButton
	_populate_grid_unique()

	if back_btn:
		back_btn.pressed.connect(_back)

	_focus_first_racer()

func _on_racer_pressed(name: String) -> void:
	if Globals.has_method("set_selected_racer"):
		Globals.set_selected_racer(name)  # also sets Globals.selected_color
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

# ---- helpers (4.4.1-safe) ----
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

func _next_unused(names: Array, used: Dictionary, start_idx: int) -> String:
	var n := names.size()
	var k := start_idx
	if n <= 0:
		return ""
	# find the next name that hasn't been used yet
	while k < start_idx + n:
		var cand := String(names[k % n])
		if not used.has(cand):
			return cand
		k += 1
	# fallback (should not happen): first name
	return String(names[start_idx % n])

func _populate_grid_unique() -> void:
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	# source of truth for names
	var names: Array = DEFAULT_RACERS
	if _has_prop(Globals, "racer_names"):
		names = Array(Globals.racer_names)

	var used := {}   # name -> true
	var idx := 0

	for child in grid.get_children():
		if child is RacerButton:
			var nm := String(child.racer_name)

			# if blank OR duplicate, assign the next unused name
			if nm == "" or used.has(nm):
				nm = _next_unused(names, used, idx)

			# write name + color to the button
			child.set_racer_name(StringName(nm))   # also updates tint via Globals
			child.refresh_from_globals()           # push color to shader (safety)

			# (re)wire the click with the correct name
			child.pressed.connect(Callable(self, "_on_racer_pressed").bind(nm))

			used[nm] = true
			idx += 1

	# sanity: warn if any expected name wasn’t placed
	for nm in names:
		if not used.has(String(nm)):
			push_warning("CharacterSelect: missing racer '" + String(nm) + "' in grid.")
