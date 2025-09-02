extends Control

@export_file("*.tscn")
var character_select_scene: String = "res://Scenes/CharacterSelect.tscn"

@onready var start_btn: Button = $Center/VBox/Start
@onready var quit_btn: Button = $Center/VBox/Quit

func _ready() -> void:
	start_btn.pressed.connect(_on_start)
	quit_btn.pressed.connect(_on_quit)
	start_btn.grab_focus() # keyboard/joypad focus

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_start()
	elif event.is_action_pressed("ui_cancel"):
		_on_quit()

func _on_start() -> void:
	var err := get_tree().change_scene_to_file(character_select_scene)
	if err != OK:
		push_error("Could not load Character Select scene at: %s" % character_select_scene)

func _on_quit() -> void:
	get_tree().quit()
