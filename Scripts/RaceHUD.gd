extends Control
class_name RaceHUD

# ---- data sources ----
@export var race_manager_path: NodePath
@export var player_path: NodePath
@export var total_laps: int = 5
@export var show_kmh: bool = false
@export var speed_label: String = "SPD"
@export var updates_per_second: float = 20.0

# ---- DIRECT LABEL REFERENCES (drag & drop these in the Inspector) ----
@export var time_lbl: Label
@export var lap_lbl: Label
@export var place_lbl: Label
@export var speed_lbl: Label
@export var last_lbl: Label
# NEW: separate gap labels
@export var ahead_lbl: Label
@export var behind_lbl: Label

var _rm: Node = null
var _player: Node = null
var _timer := 0.0
var _update_dt := 0.05

@export var nitro_bar_path: NodePath
@export var color_active:  Color = Color(0.40, 0.90, 1.00, 1.0)  # cyan glow-ish
@export var color_low:     Color = Color(1.00, 0.70, 0.25, 1.0)  # orange
@export var color_empty:   Color = Color(1.00, 0.25, 0.25, 1.0)  # red
@export var color_fill:    Color = Color(0.45, 0.70, 1.00, 1.0)  # blue-ish while refilling
@export var color_full:    Color = Color(0.35, 1.00, 0.55, 1.0)  # green when topped off

var _bar: ProgressBar

# --- Add these exports near the top ---
@export_group("Fonts · Defaults")
@export var default_font: Font
@export var default_size: int = 18
@export var outline_size: int = 2
@export var outline_color: Color = Color(0, 0, 0, 0.75)

@export_group("Fonts · Per-Label (optional)")
@export var time_font: Font
@export var time_size: int = -1
@export var lap_font: Font
@export var lap_size: int = -1
@export var place_font: Font
@export var place_size: int = -1
@export var speed_font: Font
@export var speed_size: int = -1
@export var last_font: Font
@export var last_size: int = -1
@export var best_font: Font
@export var best_size: int = -1

@export var place_gain_color := Color(0.1, 1.0, 0.2)
@export var place_loss_color := Color(1.0, 0.25, 0.25)
@export var place_anim_time  := 0.35
var _last_place: int = 0
var _place_arrow: Label

# --- HUD lap clock (fallback if RaceManager doesn't provide one) ---
var _lap_seen: int = -1
var _lap_start_clock_ms: int = 0

func _ready() -> void:
	_update_dt = max(0.01, 1.0 / updates_per_second)

	# Try an initial bind, but do NOT stop processing if missing
	_rm = get_node_or_null(race_manager_path)
	_player = get_node_or_null(player_path)

	_apply_fonts()

	# Defaults
	if time_lbl:  time_lbl.text  = "TIME 0'00\"000"
	if lap_lbl:   lap_lbl.text   = "LAP 0/%d" % total_laps
	if place_lbl: place_lbl.text = "--"
	if speed_lbl: speed_lbl.text = "%s --" % speed_label
	if last_lbl:  last_lbl.text  = "LAP TIME --"

	if ahead_lbl:
		ahead_lbl.text = "AHEAD --"
		ahead_lbl.modulate = place_gain_color
	if behind_lbl:
		behind_lbl.text = "BEHIND --"
		behind_lbl.modulate = place_loss_color

	add_to_group("race_hud")

	# Create arrow once (font style copied later if labels not ready yet)
	_place_arrow = Label.new()
	_place_arrow.text = ""
	_place_arrow.visible = false
	add_child(_place_arrow)

	_lap_seen = -1
	_lap_start_clock_ms = Time.get_ticks_msec()

	set_process(true)
	
func _process(delta: float) -> void:
	# Lazy bind until both are ready
	if _rm == null or _player == null or not _bound_once:
		_bind_if_needed()

	_timer += delta
	if _timer >= _update_dt:
		_timer = 0.0
		_refresh()

func _refresh() -> void:
	if _rm == null or _player == null:
		return
	if not _rm.has_method("GetCurrentStandings"):
		return

	var board: Array = _rm.call("GetCurrentStandings")
	if board.is_empty():
		return

	var my_id := _player.get_instance_id()
	var me: Dictionary = {}
	for it in board:
		if it.get("node", null) and it["node"].get_instance_id() == my_id:
			me = it
			break
	if me.is_empty():
		return

	var total_ms: int = int(me.get("total_ms", 0))
	time_lbl.text = "TIME " + _fmt_ms(total_ms)

	var my_lap: int = int(me.get("lap", 0))
	lap_lbl.text = "LAP %d/%d" % [clamp(my_lap, 0, total_laps), total_laps]

	var place: int = int(me.get("place", 0))
	place_lbl.text = _ordinal_big(place)

	# --- place change animation ---
	if _last_place != 0 and place != _last_place:
		var improved := place < _last_place

		# pick color based on improvement
		var from_col := place_lbl.modulate
		var to_col: Color
		if improved:
			to_col = place_gain_color
		else:
			to_col = place_loss_color

		# color flash + punch scale
		var tw := create_tween()
		place_lbl.scale = Vector2(1,1)
		tw.tween_property(place_lbl, "scale", Vector2(1.25, 1.25), place_anim_time * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(place_lbl, "modulate", to_col, place_anim_time * 0.5)
		await tw.finished

		var tw2 := create_tween()
		tw2.tween_property(place_lbl, "scale", Vector2(1.0, 1.0), place_anim_time * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw2.parallel().tween_property(place_lbl, "modulate", from_col, place_anim_time * 0.5)

		# arrow nudge
		if improved:
			_place_arrow.text = "↑"
		else:
			_place_arrow.text = "↓"

		_place_arrow.modulate = to_col
		_place_arrow.visible = true
		_place_arrow.global_position = place_lbl.global_position + Vector2(place_lbl.size.x + 6, 0)

		var tw3 := create_tween()
		var start := _place_arrow.global_position
		var end: Vector2
		if improved:
			end = start + Vector2(0, -8)
		else:
			end = start + Vector2(0, 8)

		tw3.tween_property(_place_arrow, "global_position", end, place_anim_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw3.parallel().tween_property(_place_arrow, "modulate:a", 0.0, place_anim_time)
		await tw3.finished

		_place_arrow.visible = false
		_place_arrow.modulate.a = 1.0

	_last_place = place


	# --- speed readout ---
	var spd: float = float(me.get("cur_speed", 0.0))
	if show_kmh:
		speed_lbl.text = "%s %d kmh" % [speed_label, int(round(spd))]
	else:
		speed_lbl.text = "%s %d" % [speed_label, int(round(spd))]

	# --- current lap time (prefer manager; fallback to HUD clock) ---
	var lap_ms := -1

	# Prefer RaceManager helpers if available
	if _rm.has_method("GetCurrentLapMsFor"):
		lap_ms = int(_rm.call("GetCurrentLapMsFor", _player))
	elif _rm.has_method("GetCurrentLapMs"):
		lap_ms = int(_rm.call("GetCurrentLapMs", _player))

	# If manager doesn't provide, maintain a simple HUD-side clock
	if lap_ms < 0:
		# Start/reset the HUD lap clock whenever the lap value changes to a new >0 lap
		if my_lap != _lap_seen and my_lap > 0:
			_lap_seen = my_lap
			_lap_start_clock_ms = Time.get_ticks_msec()

		# Only show a time once we've started a real lap (my_lap > 0)
		if my_lap > 0:
			lap_ms = max(0, Time.get_ticks_msec() - _lap_start_clock_ms)

	last_lbl.text = "LAP TIME " + ( _fmt_ms(lap_ms) if lap_ms >= 0 else "--" )
	last_lbl.modulate = place_gain_color  # green

	# --- gaps: ahead / behind (plain text on separate labels) ---
	var loop_len_px := 0.0
	if _rm.has_method("GetLoopLengthPx"):
		loop_len_px = float(_rm.call("GetLoopLengthPx"))

	var ahead_txt := "AHEAD --"
	var behind_txt := "BEHIND --"

	var my_index := place - 1  # place is 1-indexed

	# gap to the car AHEAD (positive => you are behind)
	if my_index > 0:
		var ahead = board[my_index - 1]
		var gt := _gap_time_s(me, ahead, loop_len_px)
		if not is_nan(gt):
			ahead_txt = "AHEAD +%0.2fs" % gt

	# gap to the car BEHIND (positive => they are behind you)
	if my_index < board.size() - 1:
		var behind = board[my_index + 1]
		var gt2 := _gap_time_s(behind, me, loop_len_px)
		if not is_nan(gt2):
			behind_txt = "BEHIND -%0.2fs" % gt2

	if ahead_lbl:
		ahead_lbl.text = ahead_txt
		ahead_lbl.modulate = place_gain_color   # green

	if behind_lbl:
		behind_lbl.text = behind_txt
		behind_lbl.modulate = place_loss_color  # red



func _rgb_hex(c: Color) -> String:
	return "%02x%02x%02x" % [int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0)]

# Signed time gap in seconds from racer A to racer B (B - A), by distance / avg speed
func _gap_time_s(a: Dictionary, b: Dictionary, loop_len_px: float) -> float:
	if loop_len_px <= 0.0:
		return NAN
	var sa := float(a.get("s_px", 0.0)) + float(a.get("lap", 0)) * loop_len_px
	var sb := float(b.get("s_px", 0.0)) + float(b.get("lap", 0)) * loop_len_px
	var dpx := sb - sa  # + means b is ahead of a

	var va := float(a.get("cur_speed", 0.0))
	var vb := float(b.get("cur_speed", 0.0))
	var v  = max(10.0, (va + vb) * 0.5)  # keep stable at low speeds

	return dpx / v

# ----- helpers -----

func _check_wiring() -> bool:
	var missing := []
	if time_lbl == null:  missing.append("time_lbl")
	if lap_lbl == null:   missing.append("lap_lbl")
	if place_lbl == null: missing.append("place_lbl")
	if speed_lbl == null: missing.append("speed_lbl")
	if last_lbl == null:  missing.append("last_lbl")
	if _rm == null:       missing.append("race_manager_path")
	if _player == null:   missing.append("player_path")

	if missing.size() > 0:
		push_error("RaceHUD wiring issue: " + ", ".join(missing) + ". Drag the nodes into the exported fields in the Inspector.")
		return false
	return true

func _fmt_ms(ms: int) -> String:
	var m := ms / 60000
	var s := (ms % 60000) / 1000
	var mm := ms % 1000
	return "%d'%02d\"%03d" % [m, s, mm]

func _ordinal_big(n: int) -> String:
	if n <= 0:
		return "--"
	var suf := "TH"
	var d := n % 10
	var dd := n % 100
	if dd < 11 or dd > 13:
		if d == 1: suf = "ST"
		elif d == 2: suf = "ND"
		elif d == 3: suf = "RD"
	return "%d%s" % [n, suf]

func _apply_fonts() -> void:
	# global outline for readability (SMK vibe)
	var labels := [time_lbl, lap_lbl, place_lbl, speed_lbl, last_lbl, ahead_lbl, behind_lbl]
	for l in labels:
		if l == null: continue
		if outline_size > 0:
			l.add_theme_color_override("font_outline_color", outline_color)
			l.add_theme_constant_override("outline_size", outline_size)

	# per-label font + size (falls back to default_* if blank / -1)
	_apply_font_to(time_lbl,  time_font,  time_size)
	_apply_font_to(lap_lbl,   lap_font,   lap_size)
	_apply_font_to(place_lbl, place_font, place_size)
	_apply_font_to(speed_lbl, speed_font, speed_size)
	_apply_font_to(last_lbl,  last_font,  last_size)
	_apply_font_to(ahead_lbl,  best_font,  best_size)
	_apply_font_to(behind_lbl,  best_font,  best_size)
	
func _apply_font_to(label: Label, f: Font, sz: int) -> void:
	if label == null: return
	var chosen_font: Font = f if f != null else default_font
	if chosen_font != null:
		label.add_theme_font_override("font", chosen_font)
	var size_to_use := sz if sz > 0 else default_size
	if size_to_use > 0:
		label.add_theme_font_size_override("font_size", size_to_use)

# level: 0..1, active: true while nitro is engaged (held/latched)
func SetNitro(level: float, active: bool) -> void:
	if _bar == null:
		return
	level = clamp(level, 0.0, 1.0)
	_bar.value = level

	# Simple color logic
	if level <= 0.01:
		_bar.modulate = color_empty
	elif level <= 0.22:
		_bar.modulate = (color_active if active else color_low)
	elif level >= 0.999:
		_bar.modulate = color_full
	else:
		_bar.modulate = (color_active if active else color_fill)

var _bound_once := false

func BindSources(player: Node, rm: Node) -> void:
	_player = player
	_rm = rm
	_try_finish_first_bind()

func _bind_if_needed() -> void:
	# Try to fill from the exported paths first
	if _rm == null and race_manager_path != NodePath():
		_rm = get_node_or_null(race_manager_path)
	if _player == null and player_path != NodePath():
		_player = get_node_or_null(player_path)

	# Fallbacks for prefabs (World tags the player with "player" group)
	if _player == null:
		_player = get_tree().get_first_node_in_group("player")
	if _rm == null:
		_rm = get_tree().get_first_node_in_group("race_manager")
	if _rm == null:
		_rm = get_node_or_null(^"RaceManager") # common name in your tree

	_try_finish_first_bind()

func _try_finish_first_bind() -> void:
	if _bound_once:
		return
	if _rm == null or _player == null:
		return

	# We’re ready: fonts, arrow, nitro bar can be finalized now too
	if _place_arrow == null:
		_place_arrow = Label.new()
		_place_arrow.text = ""
		_place_arrow.visible = false
		_place_arrow.add_theme_font_override("font", place_lbl.get_theme_font("font"))
		_place_arrow.add_theme_font_size_override("font_size", place_lbl.get_theme_font_size("font_size"))
		add_child(_place_arrow)
		_place_arrow.global_position = place_lbl.global_position + Vector2(place_lbl.size.x + 8, 0)

	if _bar == null and nitro_bar_path != NodePath():
		_bar = get_node_or_null(nitro_bar_path) as ProgressBar
		if _bar:
			_bar.min_value = 0.0
			_bar.max_value = 1.0
			_bar.value = 1.0
			_bar.modulate = color_full

	_bound_once = true
