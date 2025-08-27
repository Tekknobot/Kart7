extends CanvasLayer
class_name CountdownUI

signal go()   # emitted when GO happens

@export var word_lbl: Label
@export var show_seconds_ready: float = 0.9
@export var show_seconds_set: float   = 0.9
@export var show_seconds_go: float    = 0.8

# Optional beeps (hook if added in the scene)
@export var beep: AudioStreamPlayer
@export var go_sfx: AudioStreamPlayer

# Try to grab nodes by path if exports aren't set (adjust names if yours differ)
@onready var _container: CanvasItem = get_node_or_null("CenterContainer")
@onready var _word_fallback: Label = get_node_or_null("CenterContainer/Word")

# Color palette (SNES-y vibes)
var ready_color := Color8(255, 235, 59)   # yellow
var set_color   := Color8(255, 87,  34)   # orange
var go_color    := Color8(76,  175, 80)   # green

func _ready() -> void:
	# Fallback wiring if the export wasn't assigned in the Inspector
	if word_lbl == null and _word_fallback != null:
		word_lbl = _word_fallback

	visible = true
	Globals.race_can_drive = false
	start_countdown()

func start_countdown() -> void:
	await _show_word("READY", ready_color, show_seconds_ready)
	await _show_word("SET",   set_color,   show_seconds_set)
	await _show_word("GO!",   go_color,    show_seconds_go, true)
	await _fade_out_and_hide(0.25)
	queue_free()

func _show_word(txt: String, col: Color, dur: float, is_go: bool = false) -> void:
	if word_lbl == null:
		push_warning("CountdownUI: 'word_lbl' is not set and fallback wasn't found.")
		return

	word_lbl.text = txt
	word_lbl.modulate = col
	word_lbl.scale = Vector2(0.2, 0.2)

	# optional sounds
	if is_instance_valid(beep) and not is_go:
		beep.play()
	elif is_instance_valid(go_sfx) and is_go:
		go_sfx.play()

	# punchy scale + slight wobble (guard tween steps)
	var tw := create_tween()

	var up = tw.tween_property(word_lbl, "scale", Vector2(1.15, 1.15), 0.18)
	if up != null:
		up.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var settle = tw.tween_property(word_lbl, "scale", Vector2(1.0, 1.0), 0.12)
	if settle != null:
		settle.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# light hue shift over duration (no to_hsv)
	var t := 0.0
	var base_h: float = col.h
	while t < dur:
		var dt := get_process_delta_time()
		t += dt
		var wob := 0.02 * sin(TAU * (t / max(0.001, dur)) * 2.0)
		var h := fposmod(base_h + wob, 1.0)
		word_lbl.modulate = Color.from_hsv(h, 1.0, 1.0, 1.0)
		await get_tree().process_frame

	# On GO: release the racers right away
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
