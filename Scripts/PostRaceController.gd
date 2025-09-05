extends Node2D

@export var race_manager_path: NodePath
@export var leaderboard_path: NodePath

@export var delay_seconds: float = 5.0
@export var arm_after_seconds: float = 2.0   # fallback arm if no start signal

@export_file("*.tscn") var title_scene_path: String = "res://Scenes/title.tscn"
@export var fader_path: NodePath   # <- drag your ScreenFader (ColorRect) here

signal leaderboard_shown
signal leaderboard_done

var _rm: Node
var _leaderboard: Node
var _delay_timer: Timer
var _lock_input := false
var _armed := false
var _auto_arm_timer
var _fader: Node  # we'll duck-type; just need fade_to_scene()

func _enter_tree() -> void:
	# Pre-hide to avoid flicker
	var lb := get_node_or_null(leaderboard_path)
	if lb != null and lb is CanvasItem:
		(lb as CanvasItem).visible = false

func _ready() -> void:
	_rm = get_node_or_null(race_manager_path)
	_leaderboard = get_node_or_null(leaderboard_path)

	# Find ScreenFader
	_fader = get_node_or_null(fader_path)
	if _fader == null:
		_fader = get_node_or_null(^"Transition")
	if _fader == null:
		_fader = get_node_or_null("Transition")

	# Timer
	_delay_timer = get_node_or_null("PostRaceDelay") as Timer
	if _delay_timer == null:
		_delay_timer = Timer.new()
		_delay_timer.name = "PostRaceDelay"
		add_child(_delay_timer)
	_delay_timer.one_shot = true

	# Finish event (ignored until armed)
	if _rm != null and _rm.has_signal("race_finished"):
		_rm.connect("race_finished", Callable(self, "_on_race_finished"))

	# Arm when race starts (or auto after short delay)
	_try_connect_start_signal()
	_schedule_auto_arm_if_needed()

	set_process_unhandled_input(true)

func _try_connect_start_signal() -> void:
	if _rm == null:
		return
	for sig in ["race_started", "go", "countdown_finished", "race_began"]:
		if _rm.has_signal(sig):
			_rm.connect(sig, Callable(self, "arm"))
			return

func _schedule_auto_arm_if_needed() -> void:
	if arm_after_seconds <= 0.0:
		return
	_auto_arm_timer = get_tree().create_timer(arm_after_seconds, false)
	_auto_arm_timer.timeout.connect(Callable(self, "_on_auto_arm_timeout"))

func _on_auto_arm_timeout() -> void:
	if not _armed:
		arm()

# Public: call when the race truly begins
func arm() -> void:
	_armed = true

func _on_race_finished(results: Array) -> void:
	# Ignore early finishes until we’re armed
	if not _armed:
		return

	_lock_input = true

	# Show leaderboard + pass results if supported
	if _leaderboard != null:
		if _leaderboard is CanvasItem:
			(_leaderboard as CanvasItem).visible = true
		if _leaderboard.has_method("show_results"):
			_leaderboard.call("show_results", results)

	emit_signal("leaderboard_shown")

	# Start delay, then hide + fade -> title
	if delay_seconds < 0.0:
		delay_seconds = 0.0
	_delay_timer.wait_time = delay_seconds
	if _delay_timer.is_connected("timeout", Callable(self, "_after_leaderboard_delay")):
		_delay_timer.disconnect("timeout", Callable(self, "_after_leaderboard_delay"))
	_delay_timer.connect("timeout", Callable(self, "_after_leaderboard_delay"))
	_delay_timer.start()

func _after_leaderboard_delay() -> void:
	# Hide leaderboard first
	if _leaderboard != null and _leaderboard is CanvasItem:
		(_leaderboard as CanvasItem).visible = false
	_lock_input = false
	emit_signal("leaderboard_done")

	# Fade to black then go to title using ScreenFader
	if _fader != null and _fader.has_method("fade_to_scene"):
		await _fader.fade_to_scene(title_scene_path, false)
	else:
		var err := get_tree().change_scene_to_file(title_scene_path)
		if err != OK:
			push_error("PostRaceController: Could not load title: %s" % title_scene_path)

func _unhandled_input(event: InputEvent) -> void:
	# While the board is showing, swallow confirm/nav so gameplay doesn't react
	if not _lock_input:
		return
	if event.is_action_pressed("ui_accept") \
	or event.is_action_pressed("ui_up") \
	or event.is_action_pressed("ui_down") \
	or event.is_action_pressed("ui_left") \
	or event.is_action_pressed("ui_right"):
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()
