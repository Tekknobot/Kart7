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
@export var best_lbl: Label

var _rm: Node = null
var _player: Node = null
var _timer := 0.0
var _update_dt := 0.05

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

func _ready() -> void:
	_update_dt = max(0.01, 1.0 / updates_per_second)

	_rm = get_node_or_null(race_manager_path)
	_player = get_node_or_null(player_path)

	# Guard: make sure everything is wired
	if not _check_wiring():
		set_process(false)
		return

	_apply_fonts()  # <<< apply your chosen fonts/sizes here

	# Defaults (safe now because labels are guaranteed)
	time_lbl.text  = "TIME 0'00\"000"
	lap_lbl.text   = "LAP 0/%d" % total_laps
	place_lbl.text = "--"
	speed_lbl.text = "%s --" % speed_label
	last_lbl.text  = "LAST --"
	best_lbl.text  = "BEST --"

	set_process(true)

func _process(delta: float) -> void:
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

	var spd: float = float(me.get("cur_speed", 0.0))
	if show_kmh:
		# TODO: apply your px/s -> km/h conversion if you have one
		speed_lbl.text = "%s %d km/h" % [speed_label, int(round(spd))]
	else:
		speed_lbl.text = "%s %d" % [speed_label, int(round(spd))]

	var last_ms: int = int(me.get("last_ms", 0))
	var best_ms: int = int(me.get("best_ms", 0))
	last_lbl.text = "LAST " + ( _fmt_ms(last_ms) if last_ms > 0 else "--" )
	best_lbl.text = "BEST " + ( _fmt_ms(best_ms) if best_ms > 0 else "--" )

# ----- helpers -----

func _check_wiring() -> bool:
	var missing := []
	if time_lbl == null:  missing.append("time_lbl")
	if lap_lbl == null:   missing.append("lap_lbl")
	if place_lbl == null: missing.append("place_lbl")
	if speed_lbl == null: missing.append("speed_lbl")
	if last_lbl == null:  missing.append("last_lbl")
	if best_lbl == null:  missing.append("best_lbl")
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
	var labels := [time_lbl, lap_lbl, place_lbl, speed_lbl, last_lbl, best_lbl]
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
	_apply_font_to(best_lbl,  best_font,  best_size)

func _apply_font_to(label: Label, f: Font, sz: int) -> void:
	if label == null: return
	var chosen_font: Font = f if f != null else default_font
	if chosen_font != null:
		label.add_theme_font_override("font", chosen_font)
	var size_to_use := sz if sz > 0 else default_size
	if size_to_use > 0:
		label.add_theme_font_size_override("font_size", size_to_use)
