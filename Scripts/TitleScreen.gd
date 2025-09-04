extends Control

@export_file("*.tscn")
var character_select_scene: String = "res://Scenes/CharacterSelect.tscn"

@onready var game_title: Label = $GameTitle
@onready var subtitle:   Label = $Subtitle
@onready var start_btn:  Button = $VBox/Start
@onready var quit_btn:   Button = $VBox/Quit

func _ready() -> void:
	# Style labels (keep if you want), but make buttons default:
	_style_label(game_title, 32, Color.hex(0xFFD54DFF), 3, Color.hex(0x291600FF), Vector2(3,3), Color(0,0,0,0.65))
	_style_label(subtitle,   32, Color.hex(0xFFFFFFFF), 1, Color(0,0,0,0.85), Vector2(2,2), Color(0,0,0,0.5))

	_use_default_button(start_btn)
	_use_default_button(quit_btn)

	start_btn.pressed.connect(_on_start)
	quit_btn.pressed.connect(_on_quit)
	start_btn.grab_focus()

	_pulse(subtitle, 1.06, 0.6)
	_connect_focus_pop(start_btn)
	_connect_focus_pop(quit_btn)

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		print("Pressed button index:", event.button_index)
			
func _on_start() -> void:
	var err := get_tree().change_scene_to_file(character_select_scene)
	if err != OK:
		push_error("Could not load Character Select scene at: %s" % character_select_scene)

func _on_quit() -> void:
	get_tree().quit()

# ---------------- helpers ----------------
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

func _use_default_button(b: Button) -> void:
	# Remove any per-node overrides so the engine theme takes over
	for name in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.remove_theme_stylebox_override(name)
	for name in ["font_color", "font_color_hover", "font_color_pressed", "font_color_disabled"]:
		b.remove_theme_color_override(name)
	# Inherit the default type/appearance
	b.theme_type_variation = ""   # ensure no custom type variation
	b.flat = false                # default buttons aren't flat

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

func _focus_pop(node: CanvasItem, target: float) -> void:
	var tw := create_tween()
	var s := tw.tween_property(node, "scale", Vector2(target, target), 0.08)
	s.set_trans(Tween.TRANS_SINE)
	s.set_ease(Tween.EASE_OUT)

func _connect_focus_pop(b: Button) -> void:
	b.focus_entered.connect(Callable(self, "_on_btn_focus_entered").bind(b))
	b.focus_exited.connect(Callable(self,  "_on_btn_focus_exited").bind(b))

func _on_btn_focus_entered(b: CanvasItem) -> void:
	_focus_pop(b, 1.08)

func _on_btn_focus_exited(b: CanvasItem) -> void:
	_focus_pop(b, 1.0)
