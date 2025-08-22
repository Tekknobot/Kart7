# Autoload/FullscreenWeb.gd  (Godot 4.x)
extends Node

var _done := false

func _unhandled_input(e: InputEvent) -> void:
	if _done:
		return
	if not OS.has_feature("web"):
		return

	if _is_user_gesture(e):
		_done = true
		# Browsers only allow this after a user gesture:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _is_user_gesture(e: InputEvent) -> bool:
	# Keep these as separate ifs to avoid line-break + `or` parser issues.
	if e is InputEventMouseButton and e.pressed:
		return true
	if e is InputEventKey and e.pressed:
		return true
	if e is InputEventJoypadButton and e.pressed:
		return true
	if e is InputEventScreenTouch and e.pressed:
		return true
	return false
