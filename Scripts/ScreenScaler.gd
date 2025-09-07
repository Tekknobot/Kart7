extends Node
const BASE: Vector2i = Vector2i(640, 360) # or Vector2i(480, 270)

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	ProjectSettings.set_setting("physics/common/physics_ticks_per_second", 60)
	await get_tree().process_frame
	_apply_fullscreen_integer()

func _apply_fullscreen_integer() -> void:
	var screen_id := DisplayServer.window_get_current_screen()
	var screen_px: Vector2i = DisplayServer.screen_get_size(screen_id)

	# Largest whole-number multiple that fits
	var k = max(1, min(screen_px.x / BASE.x, screen_px.y / BASE.y))
	var target: Vector2i = BASE * k

	var base_aspect := float(BASE.x) / float(BASE.y)
	var screen_aspect := float(screen_px.x) / float(screen_px.y)
	var same_aspect = abs(screen_aspect - base_aspect) < 0.01

	if same_aspect:
		# Perfect 16:9 panel (e.g., 1920x1080, 3840x2160): fill exactly.
		DisplayServer.window_set_size(target)
		if OS.get_name() == "Windows":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN) # borderless on mac
	else:
		# Non-16:9 laptop: go borderless fullscreen at native res.
		# Bars vs. “more world” is controlled by Project Settings: Aspect = Keep or Expand.
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	print("Screen:", screen_px, " target:", target, " x", k, " same_aspect:", same_aspect)
