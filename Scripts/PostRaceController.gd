extends Node2D
class_name PostRaceController

@export var race_manager_path: NodePath
@export var leaderboard_path: NodePath

@export var prompt_node_path: NodePath
@export var prompt_scene: PackedScene
@export var ui_parent_path: NodePath

@export var delay_seconds: float = 5.0
@export var handle_actions_locally := true

# NEW: time-based arming to avoid early “finish” from spawn positions
@export var arm_after_seconds: float = 2.0

signal continue_pressed
signal retry_pressed
signal quit_pressed

var _rm: Node
var _leaderboard: Node
var _prompt: Node
var _delay_timer: Timer
var _lock_input := false
var _armed := false
var _auto_arm_timer: SceneTreeTimer

func _enter_tree() -> void:
	# Hide any UI immediately to prevent pre-ready flicker
	var lb := get_node_or_null(leaderboard_path)
	if lb != null and lb is CanvasItem:
		(lb as CanvasItem).visible = false
	var pr := get_node_or_null(prompt_node_path)
	if pr != null and pr is CanvasItem:
		(pr as CanvasItem).visible = false

func _ready() -> void:
	_rm = get_node_or_null(race_manager_path)
	_leaderboard = get_node_or_null(leaderboard_path)

	# Resolve or instance the prompt prefab (ensure it's hidden BEFORE adding)
	_prompt = get_node_or_null(prompt_node_path)
	if _prompt == null and prompt_scene != null:
		var parent_node := get_node_or_null(ui_parent_path)
		if parent_node == null:
			parent_node = self
		_prompt = prompt_scene.instantiate()
		if _prompt is CanvasItem:
			(_prompt as CanvasItem).visible = false
		parent_node.add_child(_prompt)

	# Reinforce hidden
	if _leaderboard != null and _leaderboard is CanvasItem:
		(_leaderboard as CanvasItem).visible = false
	if _prompt != null and _prompt is CanvasItem:
		(_prompt as CanvasItem).visible = false

	# Timer
	_delay_timer = get_node_or_null("PostRaceDelay") as Timer
	if _delay_timer == null:
		_delay_timer = Timer.new()
		_delay_timer.name = "PostRaceDelay"
		add_child(_delay_timer)
	_delay_timer.one_shot = true

	# Finish event (ignored until _armed)
	if _rm != null and _rm.has_signal("race_finished"):
		_rm.connect("race_finished", Callable(self, "_on_race_finished"))

	# Try to arm on a start signal; otherwise auto-arm after a delay
	_try_connect_start_signal()
	_schedule_auto_arm_if_needed()

	# Wire prefab signals/buttons
	_connect_prompt_controls()

	set_process_unhandled_input(true)

func _try_connect_start_signal() -> void:
	if _rm == null:
		return
	for sig in ["race_started", "go", "countdown_finished", "race_began"]:
		if _rm.has_signal(sig):
			_rm.connect(sig, Callable(self, "arm"))
			return

# NEW: auto-arm fallback
func _schedule_auto_arm_if_needed() -> void:
	if arm_after_seconds <= 0.0:
		return
	_auto_arm_timer = get_tree().create_timer(arm_after_seconds, false)
	_auto_arm_timer.timeout.connect(Callable(self, "_on_auto_arm_timeout"))

func _on_auto_arm_timeout() -> void:
	if not _armed:
		arm()

# Public: manually arm when race begins
func arm() -> void:
	_armed = true

func _connect_prompt_controls() -> void:
	if _prompt == null:
		return
	if _prompt.has_signal("continue_pressed"):
		_prompt.connect("continue_pressed", Callable(self, "_on_continue"))
	if _prompt.has_signal("retry_pressed"):
		_prompt.connect("retry_pressed", Callable(self, "_on_retry"))
	if _prompt.has_signal("quit_pressed"):
		_prompt.connect("quit_pressed", Callable(self, "_on_quit"))

	var cont_btn := _prompt.get_node_or_null("ContinueBtn") as Button
	if cont_btn != null:
		cont_btn.pressed.connect(Callable(self, "_on_continue"))
	var retry_btn := _prompt.get_node_or_null("RetryBtn") as Button
	if retry_btn != null:
		retry_btn.pressed.connect(Callable(self, "_on_retry"))
	var quit_btn := _prompt.get_node_or_null("QuitBtn") as Button
	if quit_btn != null:
		quit_btn.pressed.connect(Callable(self, "_on_quit"))

func _on_race_finished(results: Array) -> void:
	# Ignore any end events until we’re armed (either via start signal or time-based auto-arm)
	if not _armed:
		return

	# 1) Show ladder, hide prompt, lock gameplay input
	_lock_input = true

	if _leaderboard != null:
		if _leaderboard is CanvasItem:
			(_leaderboard as CanvasItem).visible = true
		if _leaderboard.has_method("show_results"):
			_leaderboard.call("show_results", results)

	if _prompt != null and _prompt is CanvasItem:
		(_prompt as CanvasItem).visible = false

	# 2) Start the delay
	if delay_seconds < 0.0:
		delay_seconds = 0.0
	_delay_timer.wait_time = delay_seconds
	if _delay_timer.is_connected("timeout", Callable(self, "_show_prompt")):
		_delay_timer.disconnect("timeout", Callable(self, "_show_prompt"))
	_delay_timer.connect("timeout", Callable(self, "_show_prompt"))
	_delay_timer.start()

func _show_prompt() -> void:
	_lock_input = false
	if _prompt == null:
		return

	if _prompt.has_method("show_prompt"):
		_prompt.call("show_prompt")
	else:
		if _prompt is CanvasItem:
			(_prompt as CanvasItem).visible = true

	var btn := _prompt.get_node_or_null("ContinueBtn") as Button
	if btn != null:
		btn.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not _lock_input:
		return
	if event.is_action_pressed("ui_accept") \
	or event.is_action_pressed("ui_up") \
	or event.is_action_pressed("ui_down") \
	or event.is_action_pressed("ui_left") \
	or event.is_action_pressed("ui_right"):
		get_viewport().set_input_as_handled()

# --- Button / prompt callbacks ---
func _on_continue() -> void:
	emit_signal("continue_pressed")
	if handle_actions_locally:
		get_tree().reload_current_scene()

func _on_retry() -> void:
	emit_signal("retry_pressed")
	if handle_actions_locally:
		get_tree().reload_current_scene()

func _on_quit() -> void:
	emit_signal("quit_pressed")
	if handle_actions_locally:
		get_tree().quit()
