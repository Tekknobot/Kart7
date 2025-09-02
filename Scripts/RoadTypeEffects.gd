extends Node2D
class_name RoadEffects

@export var player_path: NodePath
@export var follow_player_sprite: bool = true
@export var follow_offset_px: Vector2 = Vector2.ZERO
@export var gravel_speed_threshold: float = 12.0
@export var sparks_min_speed: float = 80.0

# Optional explicit paths; if empty we’ll auto-find children by name
@export var dust_path:   NodePath
@export var drift_path:  NodePath
@export var splash_path: NodePath
@export var sparks_path: NodePath

# NEW: per-wheel particle nodes (GPUParticles2D)
@export var right_wheel_path:         NodePath
@export var right_wheel_special_path: NodePath
@export var left_wheel_path:          NodePath
@export var left_wheel_special_path:  NodePath

var _player: Node = null
var _sprnode: Node2D = null

var _dust: Node = null       # AnimatedSprite2D or GPUParticles2D
var _drift: Node = null
var _splash: Node = null
var _sparks: Node = null

# NEW: actual wheel particle refs (GPUParticles2D)
var _rw: GPUParticles2D = null
var _rws: GPUParticles2D = null
var _lw: GPUParticles2D = null
var _lws: GPUParticles2D = null

var _last_rt: int = -999

func _ready() -> void:
	_wire_all()
	_hide_all()
	set_process(true)

func _wire_all() -> void:
	_player = get_node_or_null(player_path)
	# auto find effect nodes if paths not provided
	_dust   = _get_fx_node(dust_path,   "Dust")
	_drift  = _get_fx_node(drift_path,  "Drift")
	_splash = _get_fx_node(splash_path, "Splash")
	_sparks = _get_fx_node(sparks_path, "Sparks")

	# NEW: find wheel particle nodes
	_rw  = _get_fx_node(right_wheel_path,         "RightWheel")         as GPUParticles2D
	_rws = _get_fx_node(right_wheel_special_path, "RightWheelSpecial")  as GPUParticles2D
	_lw  = _get_fx_node(left_wheel_path,          "LeftWheel")          as GPUParticles2D
	_lws = _get_fx_node(left_wheel_special_path,  "LeftWheelSpecial")   as GPUParticles2D

	if follow_player_sprite and _player and _player.has_method("ReturnSpriteGraphic"):
		var gi = _player.call("ReturnSpriteGraphic")
		if gi is Node2D:
			_sprnode = gi

func _get_fx_node(path: NodePath, fallback_name: String) -> Node:
	if path != NodePath():
		return get_node_or_null(path)
	var n := get_node_or_null(NodePath(fallback_name))
	if n == null:
		# try deep search once
		n = find_child(fallback_name, true, false)
	return n

func _process(_dt: float) -> void:
	if _player == null:
		_wire_all()
		return
	if not _player.has_method("ReturnOnRoadType"):
		return

	_follow_player_sprite()

	var rt: int = int(_player.call("ReturnOnRoadType"))
	var spd: float = 0.0
	if _player.has_method("ReturnMovementSpeed"):
		spd = float(_player.call("ReturnMovementSpeed"))
	var drifting := (_player.has_method("ReturnIsDrifting") and bool(_player.call("ReturnIsDrifting")))

	_update_effects(rt, spd, drifting)

func _follow_player_sprite() -> void:
	if not follow_player_sprite or _sprnode == null:
		return
	global_position = _sprnode.global_position + follow_offset_px
	z_index = _sprnode.z_index + 1
	scale = _sprnode.global_scale

# ---------------- state driving ----------------

func _update_effects(rt: int, spd: float, drifting: bool) -> void:
	var use_wheel_fx := (_rw != null or _lw != null or _rws != null or _lws != null)

	# enter SINK → one-shot splash, hide everything else (wheel emitters off too)
	if rt == Globals.RoadType.SINK:
		if _last_rt != Globals.RoadType.SINK:
			_play_once(_splash, "SinkSplash")
		# turn off per-wheel emitters during sink
		_set_visible(_rw,  false)
		_set_visible(_lw,  false)
		_set_visible(_rws, false)
		_set_visible(_lws, false)
		# also silence legacy continuous effects
		_set_visible(_dust,  false)
		_set_visible(_drift, false)
		_set_visible(_sparks,false)
		_last_rt = rt
		return

	# DRIFT effects (no walls/sink)
	if drifting and rt != Globals.RoadType.WALL:
		var drift_speed_scale = clamp(spd / 120.0, 0.6, 2.0)
		# legacy drift sprite/particles (fallback)
		_play_loop(_drift, "Drift", drift_speed_scale)
		# per-wheel special (e.g. sparks)
		if use_wheel_fx and spd >= sparks_min_speed:
			_play_loop(_rws, "", 1.0) # GPUParticles2D ignores anim string
			_play_loop(_lws, "", 1.0)
		else:
			_set_visible(_rws, false)
			_set_visible(_lws, false)
		# optional legacy sparks
		if _sparks and spd >= sparks_min_speed and not use_wheel_fx:
			_play_loop(_sparks, "Sparks", 1.0)
		else:
			_set_visible(_sparks, false)
	else:
		_set_visible(_drift, false)
		_set_visible(_sparks, false)
		_set_visible(_rws,   false)
		_set_visible(_lws,   false)

	# SURFACE dust (prefer per-wheel if available)
	if rt == Globals.RoadType.GRAVEL:
		if spd >= gravel_speed_threshold:
			var ss = clamp(spd / 100.0, 0.8, 2.2)
			if use_wheel_fx:
				_play_loop(_rw, "", ss)
				_play_loop(_lw, "", ss)
			else:
				_play_loop(_dust, "Gravel", ss)
		else:
			_set_visible(_rw,  false)
			_set_visible(_lw,  false)
			if not use_wheel_fx:
				_set_visible(_dust, false)
	elif rt == Globals.RoadType.OFF_ROAD:
		var ss = clamp(spd / 60.0, 0.7, 1.8)
		if use_wheel_fx:
			_play_loop(_rw, "", ss)
			_play_loop(_lw, "", ss)
		else:
			var anim: String
			if spd < 1.0:
				anim = "OffRoadIdle"
			else:
				anim = "OffRoadDrive"

			_play_loop(_dust, anim, ss)
	else:
		_set_visible(_rw,  false)
		_set_visible(_lw,  false)
		if not use_wheel_fx:
			_set_visible(_dust, false)

	_last_rt = rt

# ---------------- helpers that work for AnimatedSprite2D or GPUParticles2D ----------------

func _hide_all() -> void:
	_set_visible(_dust,  false)
	_set_visible(_drift, false)
	_set_visible(_splash,false)
	_set_visible(_sparks,false)
	# NEW: per-wheel
	_set_visible(_rw,  false)
	_set_visible(_lw,  false)
	_set_visible(_rws, false)
	_set_visible(_lws, false)

func _set_visible(n: Node, on: bool) -> void:
	if n == null: return
	if n is AnimatedSprite2D:
		var a := n as AnimatedSprite2D
		a.visible = on
		if not on and a.is_playing(): a.stop()
	elif n is GPUParticles2D:
		var p := n as GPUParticles2D
		p.visible = on
		p.emitting = on

func _play_loop(n: Node, anim: String, speed_scale: float = 1.0) -> void:
	if n == null: return
	if n is AnimatedSprite2D:
		var a := n as AnimatedSprite2D
		if a.sprite_frames and a.sprite_frames.has_animation(anim):
			if a.animation != anim: a.animation = anim
			a.speed_scale = max(0.01, speed_scale)
			if not a.is_playing(): a.play()
			a.visible = true
	elif n is GPUParticles2D:
		var p := n as GPUParticles2D
		p.one_shot = false
		p.speed_scale = max(0.01, speed_scale)
		p.emitting = true
		p.visible = true

func _play_once(n: Node, anim: String = "") -> void:
	if n == null: return
	if n is AnimatedSprite2D:
		var a := n as AnimatedSprite2D
		if anim != "" and a.sprite_frames and a.sprite_frames.has_animation(anim):
			a.animation = anim
		a.visible = true
		a.speed_scale = 1.0
		a.play()
		if not a.is_connected("animation_finished", Callable(self, "_on_anim_finished").bind(a)):
			a.connect("animation_finished", Callable(self, "_on_anim_finished").bind(a))
	elif n is GPUParticles2D:
		var p := n as GPUParticles2D
		p.one_shot = true
		p.visible = true
		p.restart()

func _on_anim_finished(a: AnimatedSprite2D) -> void:
	a.stop()
	a.visible = false
