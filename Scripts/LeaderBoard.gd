extends Control
class_name Leaderboard

# ---------------- Scene refs ----------------
@export var race_manager_path: NodePath
@export var player_path: NodePath

# ---------------- Layout ----------------
@export var max_rows: int = 8
@export var row_height: int = 32
@export var animate_time: float = 0.22

# Column widths
@export var col_place_w: int = 20
@export var col_arrow_w: int = 20
@export var col_name_w:  int = 60
@export var col_lap_w:   int = 30
@export var col_speed_w: int = 40
@export var col_gap_w:   int = 40
@export var col_last_w:  int = 70
@export var col_best_w:  int = 70
@export var col_total_w:  int = 70


# Colors
@export var color_gain := Color(0.30, 1.00, 0.45, 0.90)
@export var color_loss := Color(1.00, 0.40, 0.40, 0.90)
@export var color_player_bg := Color(0.95, 0.90, 0.20, 0.20)
@export var color_row_even := Color(0.20, 0.20, 0.20, 0.35)
@export var color_row_odd  := Color(0.12, 0.12, 0.12, 0.35)

@export var arrow_flash_frames: int = 30   # ~0.5s if standings update ~60fps
var _arrow_frames_left := {}               # racer_id -> int frames
var _arrow_dir := {}                       # racer_id -> int (+1 up / -1 down)

# ---------------- internals ----------------
var _rm: Node = null
var _player: Node = null
var _loop_len_px: float = 0.0

var _header: HBoxContainer
var _rows_holder: Control

# Per-racer row storage
var _row_for_id := {}             # racer_id -> {holder,bg,place,arrow,name,lap,speed,gap}
var _tweens_by_id := {}           # racer_id -> Tween
var _prev_place_for_id := {}      # racer_id -> int

# Leader snapshot (used for GAP calc)
var _leader_id := 0
var _leader_lap := 0
var _leader_s_px := 0.0

@export var highlight_seconds: float = -1.0  # -1 = use animate_time
var _highlight_until := {}                   # racer_id -> time(s) when highlight ends
var _bg_tween_by_id := {}                    # racer_id -> Tween for BG fade (killed on refresh)

@export var lock_on_finish: bool = true
var _locked: bool = false
var _locked_ids := {}   # racer_id -> true after that racer finishes

# ---------------- lifecycle ----------------
func _ready() -> void:
	_build_ui_once()

	_rm = get_node_or_null(race_manager_path)
	_player = get_node_or_null(player_path)

	if _rm and _rm.has_signal("standings_changed"):
		if not _rm.is_connected("standings_changed", Callable(self, "_on_standings_changed")):
			_rm.connect("standings_changed", Callable(self, "_on_standings_changed"))

	# NEW: lock on final results
	if _rm and _rm.has_signal("race_finished"):
		if not _rm.is_connected("race_finished", Callable(self, "_on_race_finished")):
			_rm.connect("race_finished", Callable(self, "_on_race_finished"))

	if _rm and _rm.has_method("GetCurrentStandings"):
		_update_loop_len()
		var board: Array = _rm.call("GetCurrentStandings")
		if not board.is_empty():
			_apply_leader_snapshot(board)
			_update_rows(board)

	set_process(false)

func _exit_tree() -> void:
	for k in _tweens_by_id.keys():
		var tw: Tween = _tweens_by_id[k]
		if tw:
			tw.kill()
	_tweens_by_id.clear()

# ---------------- signals ----------------
func _on_standings_changed(board: Array) -> void:
	if board.is_empty():
		return
	if lock_on_finish and _locked:
		return
	_update_loop_len()
	_apply_leader_snapshot(board)
	_update_rows(board)

# ---------------- helpers ----------------
func _update_loop_len() -> void:
	if _rm and _rm.has_method("GetLoopLengthPx"):
		_loop_len_px = float(_rm.call("GetLoopLengthPx"))

func _apply_leader_snapshot(board: Array) -> void:
	# board[0] is expected to include: node, lap, s_px (RaceManager now supplies s_px again)
	var top: Dictionary = board[0]
	_leader_id  = (top["node"] as Node).get_instance_id()
	_leader_lap = int(top.get("lap", 0))
	_leader_s_px= float(top.get("s_px", 0.0))

# ---------------- UI construction ----------------
func _build_ui_once() -> void:
	var v := VBoxContainer.new()
	v.name = "VBox"
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(v)

	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.size_flags_horizontal = SIZE_EXPAND_FILL
	_header.size_flags_vertical = SIZE_FILL
	_header.custom_minimum_size.y = 8
	_header.add_theme_constant_override("separation", 6)
	v.add_child(_header)

	var hp := _make_label("POS", col_place_w, HORIZONTAL_ALIGNMENT_RIGHT)
	var ha := _make_label("CHG", col_arrow_w, HORIZONTAL_ALIGNMENT_CENTER)
	var hn := _make_label("DRIVER", col_name_w, HORIZONTAL_ALIGNMENT_LEFT) # fixed width
	hn.name = "HDR_NAME"

	var hl := _make_label("LAP",   col_lap_w, HORIZONTAL_ALIGNMENT_CENTER)
	var hlast := _make_label("LAST",  col_last_w,  HORIZONTAL_ALIGNMENT_RIGHT)
	var hbest := _make_label("BEST",  col_best_w,  HORIZONTAL_ALIGNMENT_RIGHT)
	var htotal := _make_label("TOTAL", col_total_w, HORIZONTAL_ALIGNMENT_RIGHT) # NEW
	var hs := _make_label("CUR",   col_speed_w, HORIZONTAL_ALIGNMENT_RIGHT)
	var hg := _make_label("GAP/LAP", col_gap_w, HORIZONTAL_ALIGNMENT_RIGHT)

	_header.add_child(hp)
	_header.add_child(ha)
	_header.add_child(hn)
	_header.add_child(hl)
	_header.add_child(hlast)
	_header.add_child(hbest)
	_header.add_child(htotal) # NEW
	_header.add_child(hs)
	_header.add_child(hg)

	var div := ColorRect.new()
	div.name = "Divider"
	div.color = Color(1, 1, 1, 0.15)
	div.custom_minimum_size = Vector2(0, 2)
	v.add_child(div)

	_rows_holder = Control.new()
	_rows_holder.name = "Rows"
	_rows_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows_holder.size_flags_vertical = SIZE_EXPAND_FILL
	_rows_holder.clip_contents = true
	v.add_child(_rows_holder)

	if not _rows_holder.is_connected("resized", Callable(self, "_on_rows_holder_resized")):
		_rows_holder.connect("resized", Callable(self, "_on_rows_holder_resized"))

func _make_label(text: String, min_w: int, align: int) -> Label:
	var L := Label.new()
	L.text = text
	L.horizontal_alignment = align
	if min_w > 0:
		L.custom_minimum_size.x = min_w
	return L

func _make_row_widget(racer_id: int) -> Dictionary:
	var row := {}

	var holder := Control.new()
	holder.name = "Row_%d" % racer_id
	holder.position = Vector2(0, 0)
	holder.size = Vector2(_rows_holder.size.x, row_height)
	holder.size_flags_horizontal = SIZE_EXPAND_FILL
	holder.visible = false
	_rows_holder.add_child(holder)

	var bg := ColorRect.new()
	bg.name = "BG"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.size_flags_horizontal = SIZE_EXPAND_FILL
	bg.size_flags_vertical = SIZE_EXPAND_FILL
	bg.color = color_row_even
	holder.add_child(bg)

	var H := HBoxContainer.new()
	H.name = "H"
	H.anchor_right = 1.0
	H.anchor_bottom = 1.0
	H.size_flags_horizontal = SIZE_EXPAND_FILL
	H.size_flags_vertical = SIZE_EXPAND_FILL
	H.add_theme_constant_override("separation", 6)
	holder.add_child(H)

	# Fixed-width columns
	var L_place := _make_label("", col_place_w, HORIZONTAL_ALIGNMENT_RIGHT)
	var L_arrow := _make_label(".", col_arrow_w, HORIZONTAL_ALIGNMENT_CENTER)

	# DRIVER column: fixed width via col_name_w
	var L_name := _make_label("", col_name_w, HORIZONTAL_ALIGNMENT_LEFT)
	L_name.name = "NAME"
	L_name.clip_text = true
	L_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	L_name.size_flags_horizontal = 0

	var L_lap   := _make_label("", col_lap_w, HORIZONTAL_ALIGNMENT_CENTER)
	var L_last  := _make_label("", col_last_w,  HORIZONTAL_ALIGNMENT_RIGHT)
	var L_best  := _make_label("", col_best_w,  HORIZONTAL_ALIGNMENT_RIGHT)
	var L_total := _make_label("", col_total_w, HORIZONTAL_ALIGNMENT_RIGHT) # NEW
	var L_speed := _make_label("", col_speed_w, HORIZONTAL_ALIGNMENT_RIGHT)
	var L_gap   := _make_label("", col_gap_w,   HORIZONTAL_ALIGNMENT_RIGHT)

	H.add_child(L_place)
	H.add_child(L_arrow)
	H.add_child(L_name)
	H.add_child(L_lap)
	H.add_child(L_last)
	H.add_child(L_best)
	H.add_child(L_total) # NEW
	H.add_child(L_speed)
	H.add_child(L_gap)

	row["holder"] = holder
	row["bg"]     = bg
	row["place"]  = L_place
	row["arrow"]  = L_arrow
	row["name"]   = L_name
	row["lap"]    = L_lap
	row["last"]   = L_last
	row["best"]   = L_best
	row["total"]  = L_total # NEW
	row["speed"]  = L_speed
	row["gap"]    = L_gap

	return row

func _get_or_make_row_for(id: int) -> Dictionary:
	if _row_for_id.has(id):
		return _row_for_id[id]
	var row := _make_row_widget(id)
	_row_for_id[id] = row
	return row

# ---------------- UI updates ----------------
func _update_rows(board: Array) -> void:
	var count = min(max_rows, board.size())
	var visible_ids := {}

	var now_s := Time.get_ticks_msec() / 1000.0
	var hl_sec := animate_time  # how long the green/red stays

	for i in range(count):
		var it: Dictionary = board[i]
		var racer: Node = it["node"]
		var id := racer.get_instance_id()
		visible_ids[id] = true

		var finished := bool(it.get("finished", false))
		var just_finished := finished and not _locked_ids.has(id)
		var row_locked := finished and _locked_ids.has(id)

		var row := _get_or_make_row_for(id)
		var holder: Control = row["holder"]
		holder.visible = true

		# target slot & z
		var target_y := float(i * row_height)
		holder.z_index = i

		# row move: allow one final move when they finish, then freeze
		var needs_move = abs(holder.position.y - target_y) >= 0.5
		if needs_move and (not row_locked or just_finished):
			if _tweens_by_id.has(id):
				var old: Tween = _tweens_by_id[id]
				if old:
					old.kill()
			var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(holder, "position:y", target_y, animate_time)
			_tweens_by_id[id] = tw
		else:
			holder.position.y = target_y

		# base striping unless highlight active
		var bg: ColorRect = row["bg"]
		var hl_until := float(bg.get_meta("hl_until")) if bg.has_meta("hl_until") else 0.0
		var is_highlighting := hl_until > now_s
		if not is_highlighting:
			if _player != null and racer == _player:
				bg.color = color_player_bg
			else:
				bg.color = color_row_even if (i % 2) == 0 else color_row_odd

		# labels
		var place := int(it.get("place", i + 1))
		var lap := int(it.get("lap", 0))
		var s_px := float(it.get("s_px", 0.0))

		var L_name: Label = row["name"]
		var display_name := ""
		if racer.has_method("ReturnDriverName"):
			display_name = str(racer.call("ReturnDriverName"))
		elif racer.has_meta("display_name"):
			display_name = str(racer.get_meta("display_name"))
		else:
			display_name = racer.name
		L_name.text = display_name

		var L_place: Label = row["place"]
		var prev_place = _prev_place_for_id.get(id, 0)
		_prev_place_for_id[id] = place
		L_place.text = str(place)

		# arrow + highlight; disable after finished
		var L_arrow: Label = row["arrow"]
		if not row_locked and prev_place != 0 and prev_place != place:
			var gained = place < prev_place
			L_arrow.text = "^" if gained else "v"

			bg.set_meta("hl_until", now_s + hl_sec)

			if bg.has_meta("hl_tw"):
				var old_tw: Tween = bg.get_meta("hl_tw")
				if old_tw: old_tw.kill()
				bg.set_meta("hl_tw", null)

			bg.color = color_gain if gained else color_loss
			var tw2 := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw2.tween_property(bg, "color:a", 0.0, hl_sec).from(0.90)
			tw2.tween_callback(func ():
				var now2 := Time.get_ticks_msec() / 1000.0
				var still_until := float(bg.get_meta("hl_until")) if bg.has_meta("hl_until") else 0.0
				if still_until <= now2:
					if _player != null and racer == _player:
						bg.color = color_player_bg
					else:
						bg.color = color_row_even if (i % 2) == 0 else color_row_odd
					bg.set_meta("hl_tw", null)
			)
			bg.set_meta("hl_tw", tw2)
		else:
			L_arrow.text = "."

		# lap / speed / times / gap
		var L_lap: Label = row["lap"]
		L_lap.text = "Lap " + str(lap)

		var cur_speed := float(it.get("cur_speed", 0.0))
		var speed := 0.0
		if cur_speed > 0.0:
			speed = cur_speed
		elif racer.has_method("ReturnMovementSpeed"):
			speed = float(racer.call("ReturnMovementSpeed"))

		var last_ms := int(it.get("last_ms", 0))
		var best_ms := int(it.get("best_ms", 0))
		var total_ms := int(it.get("total_ms", 0)) # NEW

		var L_last: Label = row["last"]
		var L_best: Label = row["best"]
		var L_total: Label = row["total"] # NEW

		L_last.text = _fmt_ms(last_ms)
		L_best.text = _fmt_ms(best_ms)
		L_total.text = _fmt_ms(total_ms)  # NEW

		var L_speed: Label = row["speed"]
		L_speed.text = _fmt_speed(speed)

		var L_gap: Label = row["gap"]
		L_gap.text = _format_gap_text(id, lap, s_px, speed)

		# mark locked after we processed this frame
		if finished:
			_locked_ids[id] = true

	# hide rows not in top N
	for id_key in _row_for_id.keys():
		if not visible_ids.has(id_key):
			var r = _row_for_id[id_key]
			var h := r["holder"] as Control
			h.visible = false

func _fmt_ms(ms: int) -> String:
	if ms <= 0:
		return "--"
	var total_ms := ms
	var minutes := total_ms / 60000
	var seconds := (total_ms % 60000) / 1000
	var millis := total_ms % 1000
	return str(minutes, ":", str(seconds).pad_zeros(2), ".", str(millis).pad_zeros(3))

func _fmt_speed(u: float) -> String:
	return String.num(u, 0) + " u/s"

# Builds the GAP column text: "—" for leader, "+1L/2L" if lapped, otherwise "+Xs"
func _format_gap_text(id: int, lap: int, s_px: float, speed: float) -> String:
	if id == _leader_id or _loop_len_px <= 0.0:
		return "--"

	var laps_behind: int = _lap_deficit_to_leader(lap, s_px)
	if laps_behind > 0:
		return "+%dL" % laps_behind

	var gap_s: float = _gap_seconds_for(id, lap, s_px, speed)
	return "--" if gap_s <= 0.01 else "+" + String.num(gap_s, 2) + "s"


func _gap_seconds_for(id: int, lap: int, s_px: float, speed: float) -> float:
	if id == _leader_id or _loop_len_px <= 0.0:
		return 0.0
	var dlaps := _leader_lap - lap
	var dpx := (_leader_s_px - s_px) + float(dlaps) * _loop_len_px
	var denom = max(speed, 1.0)
	return abs(dpx) / denom

func _on_rows_holder_resized() -> void:
	for id_key in _row_for_id.keys():
		var row = _row_for_id[id_key]
		var holder: Control = row["holder"]
		holder.size.x = _rows_holder.size.x
		holder.size.y = row_height

# Returns how many laps this entry is behind the current leader (0 = on the same lap or ahead)
func _lap_deficit_to_leader(lap: int, s_px: float) -> int:
	if _loop_len_px <= 0.0:
		return 0
	# Explicitly-typed locals to satisfy GDScript's type checker
	var leader_prog: float = float(_leader_lap) * _loop_len_px + _leader_s_px
	var my_prog: float     = float(lap)         * _loop_len_px + s_px
	var delta: float       = leader_prog - my_prog
	# Number of whole loop lengths behind (never negative)
	var laps_behind: int = int(floor(delta / _loop_len_px + 0.000001))
	return max(0, laps_behind)

func _on_race_finished(board: Array) -> void:
	_update_loop_len()
	_apply_leader_snapshot(board)
	_locked = true if lock_on_finish else false
	_update_rows(board)  # final paint

	# stop any ongoing tweens/highlights
	for k in _tweens_by_id.keys():
		var tw: Tween = _tweens_by_id[k]
		if tw: tw.kill()
	_tweens_by_id.clear()

	for id_key in _row_for_id.keys():
		var bg: ColorRect = _row_for_id[id_key]["bg"]
		if bg.has_meta("hl_tw"):
			var old_tw: Tween = bg.get_meta("hl_tw")
			if old_tw: old_tw.kill()
			bg.set_meta("hl_tw", null)
		bg.set_meta("hl_until", 0.0)
