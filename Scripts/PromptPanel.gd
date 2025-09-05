extends Control
class_name PromptPanel

signal continue_pressed

@export var auto_show_on_ready := false
@export var handle_actions_locally := true
@export_file("*.tscn") var reload_scene_path := ""

@onready var _center: CenterContainer = get_node_or_null("Center")
@onready var _btn: Button = get_node_or_null("Center/Continue")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	mouse_filter = Control.MOUSE_FILTER_STOP

	if _center == null:
		_center = CenterContainer.new()
		_center.name = "Center"
		_center.set_anchors_preset(PRESET_FULL_RECT)
		add_child(_center)

	if _btn == null:
		_btn = Button.new()
		_btn.name = "Continue"
		_btn.text = "CONTINUE"
		_center.add_child(_btn)

	_btn.pressed.connect(_on_continue)

	hide()
	if auto_show_on_ready:
		show_panel()

func show_panel() -> void:
	show()
	_btn.grab_focus()

func hide_panel() -> void:
	hide()
	get_viewport().gui_release_focus()

func _on_continue() -> void:
	emit_signal("continue_pressed")
	if handle_actions_locally:
		if reload_scene_path != "":
			get_tree().change_scene_to_file(reload_scene_path)
		else:
			get_tree().reload_current_scene()
