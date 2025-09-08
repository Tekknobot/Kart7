extends Control

@export var lb_title: Label 
@export var lb_next: Label 
@export var header: HBoxContainer
@export var rows: VBoxContainer
@export var btn: Button

func _ready() -> void:
	var gp = MidnightGrandPrix
	var race_no = gp.current_index + 1
	var total = gp.tracks.size()
	lb_title.text = "Grand Prix Standings — Race %d / %d" % [race_no, total]

	# Next track label
	if gp.current_index + 1 < total:
		lb_next.text = "Next: " + _nice_track_name(gp.tracks[gp.current_index + 1])
	else:
		lb_next.text = "Final results"

	# Build header labels
	_add_header_col("Pos", 40)
	_add_header_col("Racer", 220)
	_add_header_col("Pts", 60)
	_add_header_col("+Race", 80)
	_add_header_col("Wins", 60)
	_add_header_col("Best Lap", 120)

	# Populate rows — highlight ONLY the player row by name match
	var data: Array = gp.standings_rows()
	var player_name_sn: StringName = Globals.selected_racer
	for r: Dictionary in data:
		var row_name: String = String(r.get("name", ""))
		var is_player: bool = StringName(row_name) == player_name_sn
		_add_row(r, is_player)

	# Button text + make it controller-friendly
	btn.text = ("Continue" if gp.current_index + 1 < total else "Finish")
	btn.focus_mode = Control.FOCUS_ALL
	btn.grab_focus()

	# Listen for A/Enter via unhandled input
	set_process_unhandled_input(true)
	btn.pressed.connect(_on_continue)

func _unhandled_input(event: InputEvent) -> void:
	# Enter/Space/A if mapped to ui_accept in your project
	if event.is_action_pressed("ui_accept"):
		btn.emit_signal("pressed")
		var vp := get_viewport()
		if vp != null: vp.set_input_as_handled()
		return

	# Explicit gamepad A (aka "south" button) — works even if ui_accept isn't mapped
	if event is InputEventJoypadButton and event.is_pressed():
		var jb := event as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_A:  # SDL "south" button (A / Cross)
			btn.emit_signal("pressed")
			var vp2 := get_viewport()
			if vp2 != null: vp2.set_input_as_handled()

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
