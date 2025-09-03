extends Node

@export var player: Node    # drag Player/Opponent here

@export var idle_stream: AudioStream
@export var mid_stream: AudioStream
@export var high_stream: AudioStream
@export var drift_stream: AudioStream
@export var boost_stream: AudioStream
@export var spin_stream: AudioStream
@export var collision_stream: AudioStream
@export var offroad_stream: AudioStream

@onready var idle: AudioStreamPlayer2D      = get_node_or_null(^"idle_loop")
@onready var mid: AudioStreamPlayer2D       = get_node_or_null(^"mid_loop")
@onready var high: AudioStreamPlayer2D      = get_node_or_null(^"high_loop")
@onready var drift: AudioStreamPlayer2D     = get_node_or_null(^"drift_loop")
@onready var one_shot: AudioStreamPlayer2D  = get_node_or_null(^"one_shots")
@onready var offroad: AudioStreamPlayer2D   = get_node_or_null(^"offroad_loop")
@onready var hop_shot: AudioStreamPlayer2D   = get_node_or_null(^"hop_shot")
@onready var bump_shot: AudioStreamPlayer2D   = get_node_or_null(^"bump_shot")
@onready var spin_shot: AudioStreamPlayer2D   = get_node_or_null(^"spin_shot")

@export var hop_stream: AudioStream
@export var bump_stream: AudioStream

@export var hop_volume_db: float = -8.0
@export var bump_volume_db: float = -6.0
@export var hop_pitch: float = 1.0
@export var bump_pitch: float = 1.0

var _wired := false

@export var sfx_bus_name: String = "SFX"  # the bus this script will use/create
@export var sfx_bus_volume_db: float = -6.0     # set the bus volume from the inspector

@export var oneshot_min_gap_ms: int = 80
var _oneshot_last_ms: int = -99999

@export var speed_half_life_s: float = 0.06
var _spd_smooth: float = 0.0

var _bus_index: int = -1
var _last_bus_volume_db: float = 9999.0

@export var engine_start_speed: float = 5.0     # u/s needed before engines start
@export var engine_fade_in_time: float = 0.50   # seconds for fade-in
@export var idle_target_db: float = -18.0       # target levels when fully faded in
@export var mid_target_db: float  = -10.0
@export var high_target_db: float = -8.0

var _engines_started: bool = false
var _engine_gain: float = 0.0   # 0..1 fade factor

@export var loop_fade_ms: float = 24.0   # tiny fade for loop start/stop
var _drift_gain: float = 0.0             # linear 0..1
var _offroad_gain: float = 0.0

@export var engine_slew_db_per_s: float = 160.0  # max dB change per second

@export var sfx_grace_after_go_s: float = 1
var _go_seen := false
var _since_go_s := 0.0
var _drift_on: bool = false

@export var drift_target_db: float = 24.0     # where the drift loop sits when active
@export var drift_off_db: float = -80.0        # fully muted level
@export var drift_fade_ms: float = 40.0        # quick fade to avoid clicks

func _ready() -> void:
	_wired = _check_wiring()
	if not _wired:
		set_process(false)
		return

	_ensure_bus()
	_assign_players_to_bus()
	_apply_bus_volume()

	if idle != null and idle_stream != null:
		idle.stream = idle_stream
	if mid != null and mid_stream != null:
		mid.stream = mid_stream
	if high != null and high_stream != null:
		high.stream = high_stream
	if drift != null and drift_stream != null:
		drift.stream = drift_stream
	if offroad != null and offroad_stream != null:
		offroad.stream = offroad_stream

	if drift_stream is AudioStreamWAV:
		(drift_stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif drift_stream is AudioStreamOggVorbis:
		(drift_stream as AudioStreamOggVorbis).loop = true

	if idle != null:   idle.volume_db = -80.0
	if mid != null:    mid.volume_db  = -80.0
	if high != null:   high.volume_db = -80.0

	if one_shot != null:
		one_shot.stop()

	set_process(true)

func _process(_dt: float) -> void:
	if not _wired or player == null:
		return
	if not player.has_method("ReturnMovementSpeed"):
		return

	var spd: float = float(player.call("ReturnMovementSpeed"))

	# smooth the speed a touch to avoid zipper noise into the limiter
	var a_spd := 1.0 - pow(0.5, _dt / max(0.0001, speed_half_life_s))
	_spd_smooth += (spd - _spd_smooth) * a_spd

	_start_engines_if_needed(_spd_smooth)
	_update_engine_fade(_dt)
	_apply_engine_mix(_spd_smooth)   # sets pitch & engine vols (slew-limited)

	var fade_a := 1.0 - pow(0.001, _dt / max(0.001, loop_fade_ms / 1000.0))

	# --- DRIFT loop gain ---
	var want_drift := false
	if player.has_method("ReturnIsDrifting"):
		want_drift = bool(player.call("ReturnIsDrifting"))

	var drift_target := 0.0
	if want_drift:
		drift_target = 1.0

	_drift_gain = _drift_gain + (drift_target - _drift_gain) * fade_a

	if drift != null:
		# ensure it’s running when needed
		if want_drift and not drift.playing:
			if drift.stream == null and drift_stream != null:
				drift.stream = drift_stream
			# (loop flags are already set in _ready())
			drift.play()
		# apply level
		var drift_db = lerp(drift_off_db, drift_target_db, clamp(_drift_gain, 0.0, 1.0))
		drift.volume_db = drift_db
		# stop once we’ve fully faded out (prevents start/stop clicks)
		if (not want_drift) and drift.playing and _drift_gain <= 0.01:
			drift.stop()

	# --- OFF-ROAD loop gain (compute target -> smooth -> map to dB) ---
	var rt: int = -1
	if player.has_method("ReturnOnRoadType"):
		rt = int(player.call("ReturnOnRoadType"))

	var on_rough := (rt == Globals.RoadType.GRAVEL or rt == Globals.RoadType.OFF_ROAD)
	var off_target := 0.0
	if on_rough:
		off_target = 1.0
	_offroad_gain += (off_target - _offroad_gain) * fade_a

	if offroad and offroad_stream:
		var off_db = lerp(-60.0, -16.0, clamp(_offroad_gain, 0.0, 1.0))
		offroad.volume_db = off_db

	if "race_can_drive" in Globals and Globals.race_can_drive:
		if not _go_seen:
			_go_seen = true
			_since_go_s = 0.0
		else:
			_since_go_s += _dt
			
func play_boost():
	_play_oneshot(one_shot, boost_stream, 0.0, 1.0)

func play_spin() -> void:
	if not _sfx_ok(): 
		return
	if spin_shot != null and bump_stream != null:
		spin_shot.stream = spin_stream
		spin_shot.volume_db = bump_volume_db
		spin_shot.pitch_scale = bump_pitch
		spin_shot.bus = sfx_bus_name
		spin_shot.seek(0.0)
		spin_shot.play()
	elif one_shot != null and spin_stream != null:
		_play_oneshot(one_shot, spin_stream, bump_volume_db, bump_pitch)

func play_collision():
	_play_oneshot(one_shot, collision_stream, -6.0, 1.0)

func _check_wiring() -> bool:
	var missing := []
	if idle == null:
		missing.append("idle_loop")
	if mid == null:
		missing.append("mid_loop")
	if high == null:
		missing.append("high_loop")
	if drift == null:
		missing.append("drift_loop")
	if one_shot == null:
		missing.append("one_shots")
	if offroad_stream != null and offroad == null:
		missing.append("offroad_loop")
	if player == null:
		missing.append("player")

	if missing.size() > 0:
		push_error("KartSFX wiring issue: " + ", ".join(missing))
		return false
	return true

func _ensure_bus() -> void:
	_bus_index = AudioServer.get_bus_index(sfx_bus_name)
	if _bus_index == -1:
		# Create the bus so routing never goes to a ghost bus
		AudioServer.add_bus(AudioServer.get_bus_count())
		_bus_index = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(_bus_index, sfx_bus_name)
		AudioServer.set_bus_send(_bus_index, "Master")  # parent into Master

func _assign_players_to_bus() -> void:
	if idle != null:     idle.bus = sfx_bus_name
	if mid != null:      mid.bus = sfx_bus_name
	if high != null:     high.bus = sfx_bus_name
	if drift != null:    drift.bus = sfx_bus_name
	if offroad != null:  offroad.bus = sfx_bus_name
	if one_shot != null: one_shot.bus = sfx_bus_name
	if hop_shot != null: hop_shot.bus = sfx_bus_name
	if bump_shot != null: bump_shot.bus = sfx_bus_name
	if spin_shot != null: spin_shot.bus = sfx_bus_name

func _apply_bus_volume() -> void:
	if _bus_index < 0:
		return
	# Only set if changed, to avoid redundant calls
	if _last_bus_volume_db != sfx_bus_volume_db:
		AudioServer.set_bus_volume_db(_bus_index, sfx_bus_volume_db)
		_last_bus_volume_db = sfx_bus_volume_db

func _start_engines_if_needed(spd: float) -> void:
	var can_drive := true
	# Only allow loop start after GO
	if Engine.has_singleton("Globals"):
		can_drive = Globals.race_can_drive

	if not _engines_started and can_drive and spd >= engine_start_speed:
		if idle != null: idle.play()
		if mid  != null: mid.play()
		if high != null: high.play()
		_engines_started = true

func _update_engine_fade(dt: float) -> void:
	if not _engines_started:
		return
	if engine_fade_in_time <= 0.0:
		_engine_gain = 1.0
	else:
		var a := dt / engine_fade_in_time
		if a < 0.0:
			a = 0.0
		if a > 1.0:
			a = 1.0
		_engine_gain = lerp(_engine_gain, 1.0, a)

func _apply_engine_mix(spd: float) -> void:
	# pitch by speed (write once)
	var pitch = lerp(0.8, 1.5, clamp(spd / 150.0, 0.0, 1.0))
	if mid != null:
		mid.pitch_scale = pitch
	if high != null:
		high.pitch_scale = pitch * 1.2

	# crossfades (0..1), then apply fade-in gain and slew the dB
	var idle_x = clamp(spd / 20.0, 0.0, 1.0)
	var mid_x  = clamp(spd / 120.0, 0.0, 1.0)
	var high_x = clamp((spd - 90.0) / 100.0, 0.0, 1.0)

	if idle != null:
		var target_idle = lerp(idle_target_db, -60.0, idle_x)
		var goal_idle   = lerp(-80.0, target_idle, _engine_gain)
		idle.volume_db  = _slew_db(idle.volume_db, goal_idle, get_process_delta_time(), engine_slew_db_per_s)

	if mid != null:
		var target_mid = lerp(-60.0, mid_target_db, mid_x)
		var goal_mid   = lerp(-80.0, target_mid, _engine_gain)
		mid.volume_db  = _slew_db(mid.volume_db, goal_mid, get_process_delta_time(), engine_slew_db_per_s)

	if high != null:
		var target_high = lerp(-60.0, high_target_db, high_x)
		var goal_high   = lerp(-80.0, target_high, _engine_gain)
		high.volume_db  = _slew_db(high.volume_db, goal_high, get_process_delta_time(), engine_slew_db_per_s)

func _sfx_ok() -> bool:
	return _go_seen and _since_go_s >= sfx_grace_after_go_s

func play_hop() -> void:
	if hop_shot != null and hop_stream != null:
		hop_shot.stream = hop_stream
		hop_shot.volume_db = hop_volume_db
		hop_shot.pitch_scale = hop_pitch
		hop_shot.bus = sfx_bus_name
		hop_shot.seek(0.0)     # restart cleanly
		hop_shot.play()

func play_bump() -> void:
	if not _sfx_ok(): 
		return
	if bump_shot != null and bump_stream != null:
		bump_shot.stream = bump_stream
		bump_shot.volume_db = bump_volume_db
		bump_shot.pitch_scale = bump_pitch
		bump_shot.bus = sfx_bus_name
		bump_shot.seek(0.0)
		bump_shot.play()
	elif one_shot != null and bump_stream != null:
		_play_oneshot(one_shot, bump_stream, bump_volume_db, bump_pitch)

func _slew_db(cur_db: float, tgt_db: float, dt: float, rate_db_per_s: float) -> float:
	var max_step := rate_db_per_s * dt
	var delta := tgt_db - cur_db
	if delta >  max_step: return cur_db + max_step
	if delta < -max_step: return cur_db - max_step
	return tgt_db

# Waits until the named bus exists (and yields a frame to let the graph settle)
func _await_bus_ready(bus_name: String) -> void:
	var tries := 0
	while AudioServer.get_bus_index(bus_name) == -1 and tries < 8:
		await get_tree().process_frame
		tries += 1
	# one extra frame to let effects/graph settle
	await get_tree().process_frame

func _play_oneshot(n: AudioStreamPlayer2D, s: AudioStream, vol_db: float, pitch: float) -> void:
	if n == null or s == null:
		return
	var now := Time.get_ticks_msec()
	if now - _oneshot_last_ms < oneshot_min_gap_ms:
		return
	_oneshot_last_ms = now
	n.stream = s
	n.volume_db = vol_db
	n.pitch_scale = pitch
	n.seek(0.0)
	n.play()

func _ensure_loop_playing(p: AudioStreamPlayer2D, s: AudioStream) -> void:
	if p == null:
		return
	# If the stream wasn't wired from the Inspector, grab it now.
	if p.stream == null and s != null:
		p.stream = s
	# Force the resource to loop (covers WAV & OGG).
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif s is AudioStreamOggVorbis:
		s.loop = true
	# If the player got stopped for any reason, restart it.
	if not p.playing:
		p.play()

func set_drift_active(on: bool) -> void:
	if drift == null:
		return
	# make sure the stream is set & looping
	if drift.stream == null and drift_stream != null:
		drift.stream = drift_stream
	if drift.stream is AudioStreamWAV:
		(drift.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	elif drift.stream is AudioStreamOggVorbis:
		(drift.stream as AudioStreamOggVorbis).loop = true
	# play/stop on edge
	if on:
		if not drift.playing:
			drift.play()
	else:
		if drift.playing:
			drift.stop()
