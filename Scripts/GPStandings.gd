extends Control

@export var lb_title: Label 
@export var lb_next: Label 
@export var header: HBoxContainer
@export var rows: VBoxContainer
@export var btn: Button

func _ready() -> void:
	_ensure_input_map()

	var gp = MidnightGrandPrix
	var total = gp.race_count

	# Use the race that JUST finished, not whatever current_index happens to be.
	var race_no = gp.current_index + 1
	if gp.last_race_index >= 0:
		race_no = gp.last_race_index + 1

	# Title + "next" text depend on whether this was a replay
	if gp.last_race_was_replay:
		lb_title.text = "Grand Prix Standings — Replay: Race %d / %d (no points)" % [race_no, total]
		lb_next.text = "Return to map"
	else:
		lb_title.text = "Grand Prix Standings — Race %d / %d" % [race_no, total]
		if gp.current_index + 1 < total:
			lb_next.text = "Next: " + _nice_track_name(gp.world_map_scene)
		else:
			lb_next.text = "Final results"

	# Build header
	_add_header_col("Pos", 40)
	_add_header_col("Racer", 220)
	_add_header_col("Pts", 60)
	_add_header_col("+Race", 80)
	_add_header_col("Wins", 60)
	_add_header_col("Best Lap", 120)

	# Rows (highlight only player)
	var data: Array = gp.standings_rows()
	var player_name_sn: StringName = Globals.selected_racer
	for r: Dictionary in data:
		var row_name: String = String(r.get("name", ""))
		var is_player: bool = StringName(row_name) == player_name_sn
		_add_row(r, is_player)

	# Button label: for a replay we’re just heading back to the map
	if gp.last_race_was_replay:
		btn.text = "Back to Map"
	else:
		if gp.current_index + 1 < total:
			btn.text = "Continue"
		else:
			btn.text = "Finish"

	btn.focus_mode = Control.FOCUS_ALL
	btn.grab_focus()

	set_process_unhandled_input(true)
	btn.pressed.connect(_on_continue)

	RenderingServer.set_default_clear_color(Color(0,0,0))

func _ensure_input_map() -> void:
	# Ensure standard UI actions exist with sensible deadzones
	_ensure_action("ui_accept", 0.25)
	_ensure_action("ui_cancel", 0.25)
	_ensure_action("ui_up", 0.25)
	_ensure_action("ui_down", 0.25)
	_ensure_action("ui_left", 0.25)
	_ensure_action("ui_right", 0.25)

	# Buttons (XInput on Windows): A/B + D-pad
	_bind_joy_button_if_missing("ui_accept", JOY_BUTTON_A)
	_bind_joy_button_if_missing("ui_cancel", JOY_BUTTON_B)
	_bind_joy_button_if_missing("ui_up", JOY_BUTTON_DPAD_UP)
	_bind_joy_button_if_missing("ui_down", JOY_BUTTON_DPAD_DOWN)
	_bind_joy_button_if_missing("ui_left", JOY_BUTTON_DPAD_LEFT)
	_bind_joy_button_if_missing("ui_right", JOY_BUTTON_DPAD_RIGHT)

	# Left stick half-axes (so either D-pad or stick works)
	_bind_joy_axis_if_missing("ui_up", JOY_AXIS_LEFT_Y, -1.0)
	_bind_joy_axis_if_missing("ui_down", JOY_AXIS_LEFT_Y, 1.0)
	_bind_joy_axis_if_missing("ui_left", JOY_AXIS_LEFT_X, -1.0)
	_bind_joy_axis_if_missing("ui_right", JOY_AXIS_LEFT_X, 1.0)

func _ensure_action(action: StringName, deadzone: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_set_deadzone(action, deadzone)

func _bind_joy_button_if_missing(action: StringName, button_index: int) -> void:
	var events := InputMap.action_get_events(action)
	var i := 0
	var found := false
	while i < events.size():
		var e := events[i]
		if e is InputEventJoypadButton:
			var jb := e as InputEventJoypadButton
			if jb.button_index == button_index:
				found = true
		i += 1
	if not found:
		var ev := InputEventJoypadButton.new()
		ev.button_index = button_index
		InputMap.action_add_event(action, ev)

func _bind_joy_axis_if_missing(action: StringName, axis: int, axis_value: float) -> void:
	var events := InputMap.action_get_events(action)
	var i := 0
	var found := false
	while i < events.size():
		var e := events[i]
		if e is InputEventJoypadMotion:
			var jm := e as InputEventJoypadMotion
			var same_dir := (jm.axis_value > 0.0 and axis_value > 0.0) or (jm.axis_value < 0.0 and axis_value < 0.0)
			if jm.axis == axis and same_dir:
				found = true
		i += 1
	if not found:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axis
		ev.axis_value = axis_value
		InputMap.action_add_event(action, ev)

func _unhandled_input(event: InputEvent) -> void:
	# Enter/Space/A if mapped to ui_accept in your project
	if event.is_action_pressed("ui_accept"):
		btn.emit_signal("pressed")
		return

func _add_header_col(text: String, minw: int) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = minw
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(l)

func _add_row(r: Dictionary, highlight: bool) -> void:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_add_cell(hb, str(r["place"]), 40, highlight)
	_add_cell(hb, String(r["name"]), 220, highlight)
	_add_cell(hb, str(r["pts"]), 60, highlight)

	var gain := int(r["gain"])
	var gain_txt := "+%d" % gain if gain > 0 else "+0"
	_add_cell(hb, gain_txt, 80, highlight)

	_add_cell(hb, str(r["wins"]), 60, highlight)
	_add_cell(hb, _fmt_ms(int(r["best_ms"])), 120, highlight)

	rows.add_child(hb)

func _add_cell(container: HBoxContainer, text: String, minw: int, highlight: bool) -> void:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = minw
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if highlight:
		l.add_theme_color_override("font_color", Color(0.9, 1.0, 0.4)) # player row text color
	container.add_child(l)

func _on_continue() -> void:
	MidnightGrandPrix.continue_from_standings()

func _fmt_ms(ms: int) -> String:
	if ms < 0:
		return "--"
	var m := ms / 60000
	var s := (ms % 60000) / 1000
	var mm := ms % 1000
	return "%d'%02d\"%03d" % [m, s, mm]

func _nice_track_name(path: String) -> String:
	var fname := path.get_file().get_basename()
	return fname.replace("_", " ")
