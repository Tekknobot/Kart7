extends Node2D
class_name PostRaceController

@export var race_manager_path: NodePath
@export var leaderboard_path: NodePath

# EITHER point to an existing prompt node...
@export var prompt_node_path: NodePath
# ...OR provide a prefab and where to put it:
@export var prompt_scene: PackedScene
@export var ui_parent_path: NodePath   # e.g. a CanvasLayer/Control; if empty, it parents under this node

@export var delay_seconds: float = 5.0
@export var handle_actions_locally := true   # if true: Continue/Retry reload scene, Quit closes app

signal continue_pressed
signal retry_pressed
signal quit_pressed

var _rm: Node
var _leaderboard: Node
var _prompt: Node
var _delay_timer: Timer
var _lock_input := false

func _ready() -> void:
	_rm = get_node_or_null(race_manager_path)
	_leaderboard = get_node_or_null(leaderboard_path)

	# Resolve or instance the prompt prefab
	_prompt = get_node_or_null(prompt_node_path)
	if _prompt == null and prompt_scene != null:
		var parent_node := get_node_or_null(ui_parent_path)
		if parent_node == null:
			parent_node = self
		_prompt = prompt_scene.instantiate()
		parent_node.add_child(_prompt)

	# Visibility defaults
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

	# Hook race end
	if _rm != null and _rm.has_signal("race_finished"):
		_rm.connect("race_finished", Callable(self, "_on_race_finished"))

	# Wire prefab signals/buttons
	_connect_prompt_controls()

	# Swallow gameplay input during ladder
	set_process_unhandled_input(true)

func _connect_prompt_controls() -> void:
	if _prompt == null:
		return

	# Case A: prefab script emits signals
	if _prompt.has_signal("continue_pressed"):
		_prompt.connect("continue_pressed", Callable(self, "_on_continue"))
	if _prompt.has_signal("retry_pressed"):
		_prompt.connect("retry_pressed", Callable(self, "_on_retry"))
	if _prompt.has_signal("quit_pressed"):
		_prompt.connect("quit_pressed", Callable(self, "_on_quit"))

	# Case B: prefab has buttons by name
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
	# 3) Reveal prompt and focus default
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
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_up"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_down"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_left"):
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_right"):
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
