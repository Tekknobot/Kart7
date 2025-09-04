extends Control
class_name PauseMenu

@export_file("*.tscn")
var main_menu_scene: String = "res://Scenes/title.tscn"

@export var pause_action: String = "Pause"      # must exist in Project > Input Map
@export var resume_btn: Button
@export var menu_btn:   Button

func _ready() -> void:
	hide()
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep input while paused

	# Auto-find if not assigned in Inspector
	if resume_btn == null: resume_btn = $"VBoxContainer/Resume"
	if menu_btn   == null: menu_btn   = $"VBoxContainer/MainMenu"
	assert(resume_btn != null and menu_btn != null, "Hook up Resume/MainMenu buttons.")

	# Signals like your title scene
	resume_btn.pressed.connect(_on_resume_pressed)
	menu_btn.pressed.connect(_on_main_menu_pressed)

	# Simple, deterministic focus movement
	_wire_focus_neighbors()

func _input(event: InputEvent) -> void:
	# Same debug you use on the title screen
	if event is InputEventJoypadButton and event.pressed:
		print("Pressed button index:", event.button_index)

	# Open when hidden
	if not visible and event.is_action_pressed(pause_action):
		_show_menu()
		get_viewport().set_input_as_handled()
		return

	# If hidden, let gameplay see everything else
	if not visible:
		return

	# Do NOT manually handle ui_accept here; like your title scene,
	# Godot will press the focused Button automatically.

func _show_menu() -> void:
	get_tree().paused = true
	show()
	resume_btn.grab_focus()

func _hide_menu() -> void:
	get_tree().paused = false
	hide()
	get_viewport().gui_release_focus()

func _on_resume_pressed() -> void:
	_hide_menu()

func _on_main_menu_pressed() -> void:
	_hide_menu()
	get_tree().change_scene_to_file(main_menu_scene)

func _wire_focus_neighbors() -> void:
	resume_btn.focus_mode = Control.FOCUS_ALL
	menu_btn.focus_mode   = Control.FOCUS_ALL

	# Up/Down wrap between the two
	resume_btn.focus_neighbor_bottom = resume_btn.get_path_to(menu_btn)
	resume_btn.focus_neighbor_top    = resume_btn.get_path_to(menu_btn)
	menu_btn.focus_neighbor_top      = menu_btn.get_path_to(resume_btn)
	menu_btn.focus_neighbor_bottom   = menu_btn.get_path_to(resume_btn)
	# (No left/right wiring so D-pad LR won't toggle unless you want it)
