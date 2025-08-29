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

@export var hop_stream: AudioStream
@export var bump_stream: AudioStream

@export var hop_volume_db: float = -8.0
@export var bump_volume_db: float = -6.0
@export var hop_pitch: float = 1.0
@export var bump_pitch: float = 1.0

var _wired := false

@export var sfx_bus_name: String = "SFX_Karts"  # the bus this script will use/create
@export var sfx_bus_volume_db: float = -6.0     # set the bus volume from the inspector

var _bus_index: int = -1
var _last_bus_volume_db: float = 9999.0

@export var engine_start_speed: float = 5.0     # u/s needed before engines start
@export var engine_fade_in_time: float = 0.50   # seconds for fade-in
@export var idle_target_db: float = -18.0       # target levels when fully faded in
@export var mid_target_db: float  = -10.0
@export var high_target_db: float = -8.0

var _engines_started: bool = false
var _engine_gain: float = 0.0   # 0..1 fade factor

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

	if idle != null:   idle.volume_db = -80.0
	if mid != null:    mid.volume_db  = -80.0
	if high != null:   high.volume_db = -80.0
	
	if drift != null:
		drift.stop()
	if offroad != null:
		offroad.stop()
	if one_shot != null:
		one_shot.stop()

	set_process(true)

func _process(_dt: float) -> void:
	if not _wired or player == null:
		return
	if not player.has_method("ReturnMovementSpeed"):
		return

	var spd: float = float(player.call("ReturnMovementSpeed"))

	_start_engines_if_needed(spd)
	_update_engine_fade(_dt)
	_apply_engine_mix(spd)

	var pitch = lerp(0.8, 1.5, clamp(spd / 150.0, 0.0, 1.0))
	if mid != null:
		mid.pitch_scale = pitch
	if high != null:
		high.pitch_scale = pitch * 1.2

	if idle != null:
		idle.volume_db = lerp(-6.0, -30.0, clamp(spd / 20.0, 0.0, 1.0))
	if mid != null:
		mid.volume_db = lerp(-24.0, 0.0, clamp(spd / 120.0, 0.0, 1.0))
	if high != null:
		high.volume_db = lerp(-30.0, -3.0, clamp((spd - 90.0) / 100.0, 0.0, 1.0))

	var drifting := false
	if player.has_method("ReturnIsDrifting"):
		drifting = player.call("ReturnIsDrifting")

	if drift != null:
		if drifting and not drift.playing:
			drift.play()
		elif (not drifting) and drift.playing:
			drift.stop()

	var rt := -1
	if player.has_method("ReturnOnRoadType"):
		rt = int(player.call("ReturnOnRoadType"))

	var on_rough := false
	if rt == Globals.RoadType.GRAVEL or rt == Globals.RoadType.OFF_ROAD:
		on_rough = true

	if offroad != null and offroad_stream != null:
		if on_rough:
			if not offroad.playing:
				offroad.play()
			offroad.volume_db = lerp(-18.0, -6.0, clamp(spd / 160.0, 0.0, 1.0))
		else:
			if offroad.playing:
				offroad.stop()

func play_boost():
	if one_shot != null and boost_stream != null:
		one_shot.stream = boost_stream
		one_shot.play()

func play_spin():
	if one_shot != null and spin_stream != null:
		one_shot.stream = spin_stream
		one_shot.play()

func play_collision():
	if one_shot != null and collision_stream != null:
		one_shot.stream = collision_stream
		one_shot.play()

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
	# Find or create the bus
	var idx := AudioServer.get_bus_index(sfx_bus_name)
	if idx == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		idx = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, sfx_bus_name)
	# Optionally send this bus into Master (safe default)
	if AudioServer.get_bus_send(idx) != "Master":
		AudioServer.set_bus_send(idx, "Master")
	_bus_index = idx

func _assign_players_to_bus() -> void:
	if idle != null:     idle.bus = sfx_bus_name
	if mid != null:      mid.bus = sfx_bus_name
	if high != null:     high.bus = sfx_bus_name
	if drift != null:    drift.bus = sfx_bus_name
	if offroad != null:  offroad.bus = sfx_bus_name
	if one_shot != null: one_shot.bus = sfx_bus_name
	if hop_shot != null: hop_shot.bus = sfx_bus_name
	if bump_shot != null: bump_shot.bus = sfx_bus_name

func _apply_bus_volume() -> void:
	if _bus_index < 0:
		return
	# Only set if changed, to avoid redundant calls
	if _last_bus_volume_db != sfx_bus_volume_db:
		AudioServer.set_bus_volume_db(_bus_index, sfx_bus_volume_db)
		_last_bus_volume_db = sfx_bus_volume_db

func _start_engines_if_needed(spd: float) -> void:
	# optionally also gate on race_can_drive if you have Globals in this scene
	var can_drive := true
	if "Globals" in Engine:
		can_drive = true  # keep simple; if you want, check Globals.race_can_drive
	if not _engines_started and can_drive and spd >= engine_start_speed:
		if idle != null: idle.play()
		if mid  != null: mid.play()
		if high != null: high.play()
		_engines_started = true
		_engine_gain = 0.0  # begin fade-in

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
	# Pitch still scales with speed
	var pitch = lerp(0.8, 1.5, clamp(spd / 150.0, 0.0, 1.0))
	if mid != null:
		mid.pitch_scale = pitch
	if high != null:
		high.pitch_scale = pitch * 1.2

	# Base crossfade (speed) -> then multiply by fade-in gain
	var idle_x = clamp(spd / 20.0, 0.0, 1.0)         # 0..1
	var mid_x  = clamp(spd / 120.0, 0.0, 1.0)
	var high_x = clamp((spd - 90.0) / 100.0, 0.0, 1.0)

	# Compute target dB first (quieter than before), then lerp with fade-in
	if idle != null:
		var target_idle = lerp(idle_target_db, -60.0, idle_x)  # idle gets quieter as speed rises
		idle.volume_db = lerp(-80.0, target_idle, _engine_gain)
	if mid != null:
		var target_mid = lerp(-60.0, mid_target_db, mid_x)
		mid.volume_db = lerp(-80.0, target_mid, _engine_gain)
	if high != null:
		var target_high = lerp(-60.0, high_target_db, high_x)
		high.volume_db = lerp(-80.0, target_high, _engine_gain)

func play_hop() -> void:
	# Prefer the dedicated hop_shot player if present, else fall back to the generic one-shot helper
	if hop_shot != null and hop_stream != null:
		hop_shot.stop()
		hop_shot.stream = hop_stream
		hop_shot.volume_db = hop_volume_db
		hop_shot.pitch_scale = hop_pitch
		hop_shot.bus = sfx_bus_name
		hop_shot.play()

func play_bump() -> void:
	# Prefer the dedicated bump_shot player if present; fall back to one_shot
	if bump_shot != null and bump_stream != null:
		bump_shot.stop()
		bump_shot.stream = bump_stream
		bump_shot.volume_db = bump_volume_db
		bump_shot.pitch_scale = bump_pitch
		bump_shot.bus = sfx_bus_name
		bump_shot.play()
	elif one_shot != null and bump_stream != null:
		one_shot.stop()
		one_shot.stream = bump_stream
		one_shot.volume_db = bump_volume_db
		one_shot.pitch_scale = bump_pitch
		one_shot.bus = sfx_bus_name
		one_shot.play()
