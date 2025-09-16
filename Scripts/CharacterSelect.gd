extends Control

@export_file("*.tscn") var main_scene_path  := "res://Scenes/Main.tscn"
@export_file("*.tscn") var title_scene_path := "res://Scenes/Title.tscn"
@export_file("*.tscn") var worldmap_scene_path := "res://Scenes/WorldMap.tscn"
@export_file("*.tscn") var split_main_scene_path := "res://Scenes/SplitMain.tscn"  # NEW

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

# --- 2P state ---
var _two_players: bool = false
var _stage: int = 1                 # 1 = P1 selecting, 2 = P2 selecting
var _p1_choice: String = ""
var _p2_choice: String = ""
var _p1_device: int = -1            # keyboard by default
var _p2_device: int = -1000         # sentinel = unknown; first pad event joins

func _ready() -> void:
	if grid == null:
		push_error("CharacterSelect: Grid not found at Center/VBox/Grid.")
		return

	# Titles
	if select_title:
		_style_label(game_title, 32, Color.hex(0xEF5350FF), 2, Color(0,0,0,0.90), Vector2(2,2), Color(0,0,0,0.55))
		_style_label(select_title, 16, Color.hex(0xFFFFFFFF), 2, Color(0,0,0,0.90), Vector2(2,2), Color(0,0,0,0.55))
		_pulse(select_title, 1.03, 0.8)

	# Fade overlay
	_setup_transition_overlay()
	_fade_in()

	# Decide 1P vs 2P
	_two_players = false
	if Engine.has_meta("two_player_mode"):
		_two_players = bool(Engine.get_meta("two_player_mode"))
	if Engine.has_meta("player_count"):
		var pc := int(Engine.get_meta("player_count"))
		if pc >= 2:
			_two_players = true

	# Seed devices from meta if available
	if Engine.has_meta("p1_device"):
		_p1_device = int(Engine.get_meta("p1_device"))
	if Engine.has_meta("p2_device"):
		_p2_device = int(Engine.get_meta("p2_device"))

	_populate_grid_unique()

	if back_btn:
		back_btn.pressed.connect(_back)

	_focus_first_racer()
	RenderingServer.set_default_clear_color(Color(0,0,0))

	# Header
	if _two_players:
		_set_select_title("PLAYER 1 — CHOOSE")
	else:
		_set_select_title("CHOOSE YOUR RACER")

func _input(event: InputEvent) -> void:
	# Detect P2's controller on first pad input during stage 2
	if not _two_players:
		return
	if _stage != 2:
		return

	if event is InputEventJoypadButton and event.pressed:
		if _p2_device == -1000:
			_p2_device = event.device
			Engine.set_meta("p2_device", _p2_device)
			_set_select_title("PLAYER 2 — CHOOSE  (Pad " + str(_p2_device) + ")")
	if event is InputEventJoypadMotion:
		if _p2_device == -1000:
			_p2_device = event.device
			Engine.set_meta("p2_device", _p2_device)
			_set_select_title("PLAYER 2 — CHOOSE  (Pad " + str(_p2_device) + ")")

# Called by each grid button with its node + name
# Called by each grid button with its node + name
func _on_racer_button_pressed(btn: Button, name: String) -> void:
	# 1-PLAYER FLOW
	if not _two_players:
		# Store to Globals (also sets p1_color for you)
		if Globals.has_method("set_selected_racer_for_slot"):
			Globals.set_selected_racer_for_slot(1, name)

		# Store to Engine metas (used by World/WorldMap/SplitMain)
		Engine.set_meta("p1_racer", name)
		Engine.set_meta("player_count", 1)

		# (Optional legacy) keep single-racer UI in sync
		if Globals.has_method("set_selected_racer"):
			Globals.set_selected_racer(name)

		# Go to WORLD MAP
		await _fade_to_scene(worldmap_scene_path)
		return

	# 2-PLAYER FLOW
	# STEP 1 — P1 chooses
	if _stage == 1:
		# Store P1 to Globals + Engine metas
		if Globals.has_method("set_selected_racer_for_slot"):
			Globals.set_selected_racer_for_slot(1, name)
		Engine.set_meta("p1_racer", name)

		# Grey out P1's button to prevent duplicates
		if btn != null:
			btn.disabled = true
			btn.modulate = Color(1,1,1,0.45)

		_stage = 2
		if _p2_device == -1000 and not Engine.has_meta("p2_device"):
			_set_select_title("PLAYER 2 — PRESS ANY BUTTON")
		else:
			_set_select_title("PLAYER 2 — CHOOSE")
		return

	# STEP 2 — P2 chooses
	if _stage == 2:
		# Avoid choosing the same driver as P1
		var p1 := ""
		if Engine.has_meta("p1_racer"):
			p1 = String(Engine.get_meta("p1_racer"))
		if name == p1:
			return

		# Store P2 to Globals + Engine metas
		if Globals.has_method("set_selected_racer_for_slot"):
			Globals.set_selected_racer_for_slot(2, name)
		Engine.set_meta("p2_racer", name)
		Engine.set_meta("player_count", 2)

		# Default devices if none were set (P1 keyboard/-1, P2 gamepad 0)
		if not Engine.has_meta("p1_device"):
			Engine.set_meta("p1_device", -1)
		if not Engine.has_meta("p2_device"):
			var dev := _p2_device
			if dev == -1000:
				dev = 0
			Engine.set_meta("p2_device", dev)

		# Go to WORLD MAP
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
	var c := transition.color
	c.r = 0.0; c.g = 0.0; c.b = 0.0; c.a = 1.0
	transition.color = c

func _fade_in() -> void:
	if transition == null:
		return
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(transition, "color:a", 0.0, FADE_IN_TIME)
	await tw.finished
	transition.visible = false

func _fade_out() -> void:
	if transition == null:
		return
	transition.visible = true
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

# --- UI + GRID HELPERS ---

func _set_select_title(t: String) -> void:
	if select_title != null:
		select_title.text = t

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
			# Bind button node + name so we can disable P1's pick in 2P
			child.pressed.connect(Callable(self, "_on_racer_button_pressed").bind(child, nm))
			used[nm] = true
			idx += 1

	for nm in names:
		if not used.has(String(nm)):
			push_warning("CharacterSelect: missing racer '" + String(nm) + "' in grid.")
