extends Node

@export var racer_path: NodePath
@export var engine_node: NodePath = ^"EngineLoop"
@export var tire_node:   NodePath = ^"TireLoop"
@export var turbo_node:  NodePath = ^"TurboSFX"

@export_range(0.25, 3.0, 0.01) var min_pitch := 0.85
@export_range(0.25, 3.0, 0.01) var max_pitch := 1.95

@export_range(-60.0, 12.0, 0.1) var min_engine_db := -12.0
@export_range(-60.0, 12.0, 0.1) var max_engine_db := 0.0

@export_range(-60.0, 12.0, 0.1) var base_tire_db := -30.0
@export_range(-60.0, 12.0, 0.1) var steer_gain_db := 8.0
@export_range(-60.0, 12.0, 0.1) var drift_gain_db := 12.0

@export_range(0.0, 1.0, 0.01) var pan_amount := 0.35
@export_range(0.0, 0.3, 0.01) var ramp_time := 0.06

var _racer: Node = null
var _engine: AudioStreamPlayer
var _tire: AudioStreamPlayer
var _turbo: AudioStreamPlayer

var _prev_drifting := false
var _prev_turbo_active := false
var _engine_target_db := -80.0
var _tire_target_db := -80.0
var _engine_target_pitch := 1.0
var _pan_target := 0.0

func _ready() -> void:
	_racer = get_node_or_null(racer_path)
	_engine = get_node_or_null(engine_node) as AudioStreamPlayer
	_tire   = get_node_or_null(tire_node) as AudioStreamPlayer
	_turbo  = get_node_or_null(turbo_node) as AudioStreamPlayer

	if _engine != null:
		if _engine.stream != null:
			# Force loop on supported stream types
			if _engine.stream is AudioStreamWAV:
				var w := _engine.stream as AudioStreamWAV
				w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			elif _engine.stream.has_method("set_loop"):
				_engine.stream.loop = true
			_engine.play()
		_engine.volume_db = -80.0
		_engine.pitch_scale = min_pitch

	if _tire != null:
		if _tire.stream != null:
			if _tire.stream is AudioStreamWAV:
				var w2 := _tire.stream as AudioStreamWAV
				w2.loop_mode = AudioStreamWAV.LOOP_FORWARD
			elif _tire.stream.has_method("set_loop"):
				_tire.stream.loop = true
			_tire.play()
		_tire.volume_db = -80.0
		_tire.pitch_scale = 1.0

	if _turbo != null:
		_turbo.stop()

func _process(delta: float) -> void:
	if _racer == null:
		return

	# --- read game state ---
	var speed := 0.0
	var max_speed := 1.0
	var steer := 0.0
	var drifting := false
	var turbo_active := false

	if _racer.has_method("ReturnMovementSpeed"):
		speed = float(_racer.ReturnMovementSpeed())

	if _racer.has_method("get"):
		var ms = _racer.get("_maxMovementSpeed")
		if ms != null:
			max_speed = max(1.0, float(ms))

	if _racer.has_method("ReturnPlayerInput"):
		var v: Vector2 = _racer.ReturnPlayerInput()
		steer = clamp(v.x, -1.0, 1.0)

	if _racer.has_method("get"):
		var d = _racer.get("_is_drifting")
		if d != null:
			drifting = bool(d)
		var tt = _racer.get("_turbo_timer")
		if tt != null:
			turbo_active = float(tt) > 0.0

	var speed_ratio = clamp(speed / max_speed, 0.0, 1.0)
	var steer_abs = abs(steer)

	# --- targets ---
	_engine_target_pitch = lerp(min_pitch, max_pitch, speed_ratio)
	_engine_target_db = lerp(min_engine_db, max_engine_db, speed_ratio)

	var tire_db := base_tire_db
	var steer_factor = clamp((steer_abs - 0.3) / 0.7, 0.0, 1.0)
	tire_db += steer_gain_db * steer_factor
	if drifting:
		tire_db += drift_gain_db
	_tire_target_db = tire_db

	_pan_target = clamp(steer * pan_amount, -1.0, 1.0)

	if turbo_active and not _prev_turbo_active:
		if _turbo != null and _turbo.stream != null:
			_turbo.stop()
			_turbo.play()
	_prev_turbo_active = turbo_active
	_prev_drifting = drifting

	# --- apply with smoothing ---
	var t := 1.0
	if ramp_time > 0.0:
		t = clamp(delta / ramp_time, 0.0, 1.0)

	if _engine != null:
		_engine.pitch_scale = lerp(_engine.pitch_scale, _engine_target_pitch, t)
		_engine.volume_db  = lerp(_engine.volume_db,  _engine_target_db,   t)

	if _tire != null:
		_tire.volume_db = lerp(_tire.volume_db, _tire_target_db, t)

	# To do actual pan with AudioStreamPlayer2D: parent those nodes as 2D and animate their x-position.
	# This script leaves panning neutral for plain AudioStreamPlayer.
