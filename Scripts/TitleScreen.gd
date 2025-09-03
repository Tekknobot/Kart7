extends Control

@export_file("*.tscn")
var character_select_scene: String = "res://Scenes/CharacterSelect.tscn"

@onready var game_title: Label = $Center/VBox/GameTitle
@onready var subtitle:   Label = $Center/VBox/Subtitle
@onready var start_btn:  Button = $Center/VBox/Start
@onready var quit_btn:   Button = $Center/VBox/Quit

func _ready() -> void:
	# Wire up actions
	start_btn.pressed.connect(_on_start)
	quit_btn.pressed.connect(_on_quit)
	start_btn.grab_focus()

	# ---- Title + subtitle styling (use positional args) ----
	_style_label(game_title, 32, Color.hex(0xFFD54DFF), 3, Color.hex(0x291600FF), Vector2(3,3), Color(0,0,0,0.65))
	_style_label(subtitle,   32, Color.hex(0xFFFFFFFF), 1, Color(0,0,0,0.85), Vector2(2,2), Color(0,0,0,0.5))

	# Gentle breathing pulse on the big title
	_pulse(game_title, 1.06, 0.6)

	# Blink “Start” a bit to attract attention
	_blink_alpha(start_btn, 0.85, 0.7)

	# Focus pop without lambdas
	_connect_focus_pop(start_btn)
	_connect_focus_pop(quit_btn)

func _unhandled_input(event: InputEvent) -> void:
	start_btn.pressed.connect(_on_start)
	quit_btn.pressed.connect(_on_quit)

func _on_start() -> void:
	var err := get_tree().change_scene_to_file(character_select_scene)
	if err != OK:
		push_error("Could not load Character Select scene at: %s" % character_select_scene)

func _on_quit() -> void:
	get_tree().quit()

# ---------------- helpers (no nested funcs, no chains) ----------------
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

func _blink_alpha(node: CanvasItem, min_a: float, seconds_each_way: float) -> void:
	node.modulate = Color(1,1,1,1)
	var tw := create_tween()
	tw.set_loops()
	var a1 := tw.tween_property(node, "modulate:a", min_a, seconds_each_way)
	a1.set_trans(Tween.TRANS_SINE)
	a1.set_ease(Tween.EASE_IN_OUT)
	var a2 := tw.tween_property(node, "modulate:a", 1.0, seconds_each_way)
	a2.set_trans(Tween.TRANS_SINE)
	a2.set_ease(Tween.EASE_IN_OUT)

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
