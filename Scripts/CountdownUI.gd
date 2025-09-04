extends Control
class_name CountdownUI

signal go()   # emitted when GO happens

@export var word_lbl: Label
@export var show_seconds_ready: float = 0.9
@export var show_seconds_set: float   = 0.9
@export var show_seconds_go: float    = 0.8

@export var pseudo3d_path: NodePath   # drag your Pseudo3D node here

# Optional beeps (hook if added in the scene)
@export var beep: AudioStreamPlayer2D
@export var go_sfx: AudioStreamPlayer2D

# Try to grab nodes by path if exports aren't set (adjust names if yours differ)
@onready var _container: CanvasItem = get_node_or_null("CenterContainer")
@onready var _word_fallback: Label = get_node_or_null("CenterContainer/Word")

# Color palette (SNES-y vibes)
var ready_color := Color8(255, 235, 59)   # yellow
var set_color   := Color8(255, 87,  34)   # orange
var go_color    := Color8(76,  175, 80)   # green

# Top-level, file-scope:
static var __ui_bus_ready := false

# --- NEW: outline + width controls ------------------------------------------------
@export_group("Text Appearance")
@export var outline_enabled: bool = true
@export_range(0, 64, 1) var outline_size: int = 6
@export var outline_color: Color = Color(0, 0, 0, 1.0)
@export var base_font_color: Color = Color(1, 1, 1, 1.0)

@export_range(8, 256, 1) var font_size: int = 96   # NEW: base font size
@export var max_text_width: int = 0

# --- UI SFX (READY/SET/GO) -------------------------------------------------
@export_group("SFX")
@export var beep_stream: AudioStream         # short blip for READY/SET
@export var go_stream: AudioStream           # stronger blip for GO
@export var sfx_bus_name: String = "SFX"
@export var beep_volume_db: float = -6.0
@export var go_volume_db: float = -3.0
@export var beep_pitch_ready: float = 1.00
@export var beep_pitch_set:   float = 1.15
@export var go_pitch:         float = 1.00
@export var auto_create_players: bool = true  # if true, makes players if missing
@export var delay: int = 4  # if true, makes players if missing

var _bus_idx: int = -1

# If > 0, the label will use this width and autowrap smartly (useful if you ever
# show longer text than READY/SET/GO)
# ----------------------------------------------------------------------------------

func _ready() -> void:		
	# Fallback wiring if the export wasn't assigned in the Inspector
	if word_lbl == null and _word_fallback != null:
		word_lbl = _word_fallback

	# Apply outline + width settings once the label is known
	_apply_label_style()

	visible = true
	Globals.race_can_drive = false

	var pseudo := get_node_or_null(pseudo3d_path)
	# If there is an intro spin, wait for it to finish, THEN start the countdown (after your delay)
	if pseudo != null and pseudo.has_signal("intro_spin_finished") and pseudo.get("intro_spin_enabled"):
		# wait for cinematic 360 to end
		await pseudo.intro_spin_finished
		# optional extra delay after spin, if you still want it
		if delay > 0:
			await get_tree().create_timer(delay).timeout
		start_countdown()

func start_countdown() -> void:
	await _show_word("READY", ready_color, show_seconds_ready)
	await _show_word("SET",   set_color,   show_seconds_set)
	await _show_word("GO!",   go_color,    show_seconds_go, true)
	await _fade_out_and_hide(0.25)
	queue_free()

func _apply_label_style() -> void:
	if word_lbl == null:
		return
	if word_lbl.label_settings == null:
		word_lbl.label_settings = LabelSettings.new()
	var ls := word_lbl.label_settings

	ls.font_size = font_size          # << new line
	ls.font_color = base_font_color
	ls.outline_size = outline_size if outline_enabled else 0
	ls.outline_color = outline_color

	# Optional width constraint + smart wrapping
	if max_text_width > 0:
		word_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		word_lbl.custom_minimum_size.x = float(max_text_width)
	else:
		word_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		word_lbl.custom_minimum_size.x = 0.0

	# Center alignment works well with the wobble/scale
	word_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	word_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

# Optional: tiny debounce so the same word can't retrigger within its duration
var _ui_last_play_ms: int = -99999
@export var ui_min_gap_ms: int = 80

func _show_word(txt: String, col: Color, dur: float, is_go: bool = false) -> void:
	if word_lbl == null:
		push_warning("CountdownUI: 'word_lbl' is not set and fallback wasn't found.")
		return

	# Don’t beep during intro spin (cinematic)
	var pseudo := get_node_or_null(pseudo3d_path)
	var intro_active = (pseudo != null and pseudo.get("_intro_mode") == true)

	# ---- SFX (single, guarded trigger — no ternary) ----
	if not intro_active:
		var now := Time.get_ticks_msec()
		if now - _ui_last_play_ms >= ui_min_gap_ms:
			_ui_last_play_ms = now
			if is_go:
				if is_instance_valid(go_sfx) and go_stream != null:
					go_sfx.stream = go_stream
					go_sfx.pitch_scale = go_pitch
					go_sfx.volume_db = go_volume_db
					go_sfx.play()
			else:
				if is_instance_valid(beep) and beep_stream != null:
					var p := beep_pitch_ready
					if txt == "SET":
						p = beep_pitch_set
					beep.stream = beep_stream
					beep.pitch_scale = p
					beep.volume_db = beep_volume_db
					beep.play()

	# ---- Visuals (unchanged) ----
	_apply_label_style()
	word_lbl.text = txt
	word_lbl.scale = Vector2(0.2, 0.2)

	var tw := create_tween()
	var up = tw.tween_property(word_lbl, "scale", Vector2(1.15, 1.15), 0.18)
	if up != null: up.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var settle = tw.tween_property(word_lbl, "scale", Vector2(1.0, 1.0), 0.12)
	if settle != null: settle.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	var t := 0.0
	var base_h: float = col.h
	while t < dur:
		var dt := get_process_delta_time()
		t += dt
		var wob := 0.02 * sin(TAU * (t / max(0.001, dur)) * 2.0)
		var h := fposmod(base_h + wob, 1.0)
		if word_lbl.label_settings != null:
			word_lbl.label_settings.font_color = Color.from_hsv(h, 1.0, 1.0, 1.0)
		else:
			word_lbl.modulate = Color.from_hsv(h, 1.0, 1.0, 1.0)
		await get_tree().process_frame

	if is_go:
		Globals.race_can_drive = true
		emit_signal("go")

func _fade_out_and_hide(time: float) -> void:
	# Fade a CanvasItem (Label or container), not the CanvasLayer
	var target: CanvasItem = _container if _container != null else word_lbl
	if target == null:
		return

	var tw := create_tween()
	var fade = tw.tween_property(target, "modulate:a", 0.0, time)
	if fade != null:
		fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	visible = false

func _ensure_sfx_players() -> void:
	# If you already dragged players in the Inspector, we just configure them.
	# Otherwise (auto_create_players), we create them as children.
	if beep == null and auto_create_players:
		beep = AudioStreamPlayer2D.new()
		beep.name = "Beep"
		add_child(beep)
	if go_sfx == null and auto_create_players:
		go_sfx = AudioStreamPlayer2D.new()
		go_sfx.name = "GoSFX"
		add_child(go_sfx)

	# Assign streams if provided
	if beep != null and beep_stream != null:
		beep.stream = beep_stream
	if go_sfx != null and go_stream != null:
		go_sfx.stream = go_stream

	# Route to UI bus and set default levels
	if beep != null:
		beep.bus = sfx_bus_name
		beep.volume_db = beep_volume_db
	if go_sfx != null:
		go_sfx.bus = sfx_bus_name
		go_sfx.volume_db = go_volume_db

# Waits until the named bus exists (and yields a frame to let the graph settle)
func _await_bus_ready(bus_name: String) -> void:
	var tries := 0
	while AudioServer.get_bus_index(bus_name) == -1 and tries < 1200:
		await get_tree().process_frame
		tries += 1
	# one extra frame to let effects/graph settle
	await get_tree().process_frame
