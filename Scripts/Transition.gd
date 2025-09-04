extends ColorRect
class_name ScreenFader

@export var fade_color: Color = Color(0, 0, 0, 1.0) # base color; alpha is driven by tween
@export var fade_in_time:  float = 0.40
@export var fade_out_time: float = 0.35
@export var auto_fade_in:  bool  = true

var _busy := false

func _ready() -> void:
	# Make sure the overlay covers the whole screen and starts opaque
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = true
	color = fade_color
	color.a = 1.0
	# Fade in after one frame so the node is fully on top
	if auto_fade_in:
		await get_tree().process_frame
		await fade_in()

func fade_in() -> void:
	if _busy:
		return
	_busy = true
	visible = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "color:a", 0.0, fade_in_time)
	await tw.finished
	visible = false
	_busy = false

func fade_out() -> void:
	if _busy:
		return
	_busy = true
	visible = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "color:a", 1.0, fade_out_time)
	await tw.finished
	_busy = false

func fade_to_scene(path: String, unpause_before_change: bool = false) -> void:
	# Fade to black, optionally unpause, then change scene
	if _busy:
		return
	await fade_out()
	if unpause_before_change:
		get_tree().paused = false
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("ScreenFader: Could not load scene: %s" % path)

func fade_then(callable: Callable) -> void:
	# Generic: fade out, then run any callable you pass in
	if _busy:
		return
	await fade_out()
	if callable.is_valid():
		callable.call()
