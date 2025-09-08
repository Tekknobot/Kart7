# Scripts/World Elements/Racers/Opponent.gd  (perf-tuned)
extends "res://Scripts/World Elements/Racers/Racer.gd"

@onready var _sfx_ai: Node = get_node_or_null(^"Audio")
var _hit_sfx_cd: float = 0.0

# Only NEW settings here; everything else comes from Racer.gd
@export var player_ref: NodePath

# Grid / Lane
@export var start_index: int = 0
@export var start_offset_px: float = 0.0
@export var lane_offset_px: float = 0.0

# AI tuning
@export var target_speed: float = 110.0
@export var accel: float = 180.0
@export var max_turn_rate: float = 3.0      # rad/sec
@export var lookahead_px: float = 120.0
@export var steer_gain: float = 1.0
@export var speed_damper_on_curve: float = 0.65

# --- speed tuning (add under your existing AI exports) ---
@export var max_speed_override: float = 320.0
@export var catchup_gain_speed: float = 380.0
@export var catchup_deadzone_uv: float = 0.02
@export var min_ratio_vs_player: float = 1.05

# ---------------- visuals ----------------
@export var angle_offset_deg: float = 0.0
@export var clockwise: bool = true
@export var frame0_is_front: bool = true

# --- Nitro (opponent) ---
@export var AI_NITRO_MIN_FRAC := 0.35        # need ≥35% to engage & stay on
@export var AI_NITRO_CAPACITY_S := 3.0       # seconds of continuous nitro
@export var AI_NITRO_REFILL_S   := 2.4       # seconds from 0→1
@export var AI_NITRO_MULT       := 1.002     # same tiny bump as player
@export var AI_NITRO_COOLDOWN_S := 1.0       # delay after nitro drops below threshold
@export var AI_NITRO_LOOKAHEAD_PX := 360.0   # how far we examine the path
@export var AI_NITRO_MIN_STRAIGHT_PX := 260.0# minimum “straight runway” needed
@export var AI_NITRO_DOT := 0.985            # cos(10°); higher = stricter straight

var _nitro_charge: float = 1.0    # 0..1 gauge
var _nitro_latched: bool = false  # AI’s “hold nitro” switch
var _nitro_timer: float = 0.0     # >0 = visuals ON this frame
var _nitro_cd: float = 0.0        # cooldown before re-arming

# nitro shader (same as Player)
@export var nitro_shader_path: String = "res://Scripts/Shaders/OpponentNitroPulse.gdshader"
@export var nitro_glow_color: Color = Color(0.55, 0.9, 1.0, 1.0)
@export var nitro_outline_px: float = 2.0
@export var nitro_chroma_max_px: float = 3.0
@export var nitro_intensity_max: float = 1.0
var _nitro_mat: ShaderMaterial = null
var _nitro_prev_material: Material = null

# --- perf toggles ---
@export var debug_log_ai_sprite: bool = false
@export var visual_update_stride: int = 2 # update sprite/depth every N frames

# Internals unique to Opponent
var _cum_len_px: PackedFloat32Array = PackedFloat32Array()  # alias of _path_len
var _total_len_px: float = 0.0
var _s_px: float = 0.0

# Cached nodes (avoid per-frame get_node calls)
var _pn: Node = null
var _p3d: Node = null
var _pl: Node = null
var _angle_sprite: Node = null

# Cached path data
var _seg_tan: PackedVector2Array = PackedVector2Array()  # per-vertex unit tangents

var _spawn_locked: bool = false

# Store base uniforms for restoration
var _prev_uniforms: Dictionary = {}

# --- DIFFICULTY SCALING ---
@export var race_manager_ref: NodePath

# Use player's lap to scale difficulty; set false to use race leader's lap
@export var diff_use_player_lap: bool = true

# Lap index at which difficulty begins (0 = from the grid, 1 = only after first crossing)
@export var diff_start_lap: int = 1

# Per-lap increments (tune to taste)
@export var diff_speed_per_lap: float = 6.0          # +u/s to base target_speed each lap
@export var diff_max_speed_per_lap: float = 4.0      # +u/s to _maxMovementSpeed cap each lap
@export var diff_catchup_gain_per_lap: float = 20.0  # increases catchup pressure each lap
@export var diff_min_ratio_per_lap: float = 0.01     # min_ratio_vs_player grows each lap
@export var diff_turn_per_lap: float = 0.05          # +rad/sec to max_turn_rate each lap
@export var diff_corner_penalty_decay: float = 0.02  # reduce corner slowdown each lap

# Caps / safety
@export var diff_max_speed_cap: float = 420.0        # hard ceiling for _maxMovementSpeed
@export var diff_min_corner_penalty: float = 0.40    # never drop below this (0..1)
@export var diff_max_min_ratio: float = 1.40         # never require >+40% over player

# Cached RaceManager
var _rm: Node = null

# Baselines (original values to scale from)
var _base_target_speed: float
var _base_max_speed: float
var _base_catchup_gain: float
var _base_min_ratio: float
var _base_max_turn_rate: float
var _base_corner_penalty: float

# --- add near the top with other internals ---
var _view_M: Basis = Basis()       # latest world->view (same as shader)
var _view_scr: Vector2 = Vector2.ZERO
var _view_valid: bool = false

# ===== Traffic awareness / passing =====
@export var avoid_enabled: bool = true
@export var avoid_lookahead_s: float = 0.75      # predict ~0.75s ahead
@export var avoid_width_px: float = 22.0         # half-width "lane" of a kart
@export var lane_candidates_px := PackedFloat32Array([-16.0, 0.0, 16.0])
@export var lane_lerp_hz: float = 6.0            # smooth lane changes (higher = snappier)

@export var pass_bias_outer_on_turn: float = 0.20  # prefer outside of upcoming corner
@export var pass_cooldown_s: float = 0.60          # stick to a side long enough to be readable
@export var block_slow_mult: float = 0.82          # soft brake when boxed in

@export var draft_enabled: bool = true
@export var draft_dist_px: float = 55.0          # behind distance for slipstream
@export var draft_lateral_px: float = 10.0       # how centered behind target
@export var draft_speed_bonus: float = 12.0      # +u/s while drafting

# internals

# ===== Humanization (subtle wandering on straights) =====
@export var humanize_enabled: bool = true
@export var humanize_amp_px: float = 6.0        # max lateral wander in pixels
@export var humanize_freq_hz: float = 0.55      # base sway frequency
@export var humanize_noise_hz: float = 0.35     # slow drift of the phase
@export var humanize_corner_fade: float = 0.40  # how quickly wander fades in corners (0..1)
@export var humanize_nearby_fade_px: float = 48.0  # fade wander when others are within this

var _hum_phase: float = 0.0
var _hum_noise: float = 0.0
var _hum_rng := RandomNumberGenerator.new()

# ---- Path following smoothers (anti-snap) ----
@export var lookahead_px_base: float = 140.0   # base look-ahead distance (px)
@export var lookahead_px_min:  float = 80.0    # clamp low
@export var lookahead_px_max:  float = 260.0   # clamp high
@export var lookahead_curv_boost: float = 180.0  # +px on straights (curvature≈0)

@export var desired_yaw_half_life_s: float = 0.10   # ease target heading (seconds to half)
@export var heading_rate_limit:     float = 2.6     # rad/s cap (softer than max_turn_rate)

var _desired_yaw: float = 0.0   # smoothed target yaw (radians)

# --- add near other exports ---
@export var anti_snap_window_px: float = 28.0   # half-window in px for smoothing (20–40 feels good)
# OPTIONAL: smooth "right" over time to completely eliminate micro-flips
var _right_smooth: Vector2 = Vector2.RIGHT
@export var right_half_life_s: float = 0.06

@export var merge_time_s: float = 1   # time to glide from grid -> path after GO

var _merge_armed: bool = false
var _merging: bool = false
var _merge_t: float = 0.0
var _merge_start_uv: Vector2 = Vector2.ZERO
var _was_go: bool = false

@export_group("Randomize")
@export var randomize_on_ready: bool = false   # set true if you want self-randomization without the manager
@export var random_seed: int = 0               # 0 = time+id; otherwise reproducible
@export var assume_player_target_speed: float = 150.0  # used only if manager doesn't pass a value
@export var bump_debug: bool = true   # flip OFF to silence

@export_group("Speed Tag")
@export var show_speed_tag: bool = true
@export var speed_tag_font: FontFile        # assign a TTF/OTF in the inspector
@export var speed_tag_font_size: int = 16
@export var speed_tag_color: Color = Color(1,1,1,1)
@export var speed_tag_outline_color: Color = Color(0,0,0,0.7)
@export var speed_tag_offset_px: float = 6.0  # gap above the sprite
@export var speed_tag_units: int = 0          # 0=px/s, 1=km/h, 2=mph
@export var speed_tag_round: bool = true
var _speed_tag: Label = null

# --- Drift (AI) ---
@export var DRIFT_MIN_SPEED: float = 60.0
@export var DRIFT_CURV_START: float = 0.12
@export var DRIFT_CURV_STOP: float  = 0.06
@export var DRIFT_SPEED_MULT: float = 0.93
@export var DRIFT_SLIP_MAX: float   = 40.0
@export var DRIFT_SLIP_ACCEL: float = 90.0
@export var DRIFT_RELEASE_S: float  = 0.20
@export var DRIFT_CURV_ALPHA: float = 0.20   # smoothing factor for curvature [0..1]
@export var DRIFT_SIGN_SAMPLE_PX: float = 48.0   # half-window for signed curvature

var _is_drifting: bool = false
var _drift_linger: float = 0.0
var _drift_slip: float = 0.0
var _drift_sign: float = 0.0      # +1 left turn, -1 right turn

var _last_fwd: Vector2 = Vector2.RIGHT
var _curv_ema: float = 0.0

@export var skid_parent_path: NodePath

func _bname(n: Node) -> String:
	return (n.name if n != null and "name" in n else str(n.get_instance_id()))

func _bprint(msg: String) -> void:
	if bump_debug:
		print("[AI-BUMP] ", msg)

# --- helper: smoothed frame at arc length s ---
func _uv_and_tangent_smooth(s_px: float, window_px: float = anti_snap_window_px) -> Dictionary:
	if _total_len_px <= 0.0:
		return {"uv": Vector2.ZERO, "tan": Vector2.RIGHT}

	# Clamp to a reasonable window
	var w = clamp(window_px, 4.0, 80.0)

	# Central-difference samples
	var s0 = s_px - w
	var s1 = s_px + w

	var p0: Vector2 = _uv_at_distance(s0)
	var p1: Vector2 = _uv_at_distance(s1)

	var t: Vector2 = p1 - p0
	var t_len := t.length()
	if t_len > 0.00001:
		t /= t_len
	else:
		# Fallback: current segment tangent
		t = _tangent_at_distance(s_px)

	# Return current position plus smoothed tangent
	return {"uv": _uv_at_distance(s_px), "tan": t}

func _exp_smooth_vec(prev: Vector2, target: Vector2, dt: float, half_life: float) -> Vector2:
	var hl = max(half_life, 0.0001)
	var a := 1.0 - pow(0.5, dt / hl)
	return (prev + (target - prev) * a)
		
func set_world_and_screen(M: Basis, scr: Vector2) -> void:
	_view_M = M
	_view_scr = scr
	_view_valid = true

# Apply a spawn directly from a path index (and optional lane px), and lock it so _ready() won't overwrite it.
func ApplySpawnFromPathIndex(idx: int, lane_px: float = 0.0) -> void:
	_try_cache_nodes()
	_cache_path()
	if _uv_points.size() < 2 or _total_len_px <= 0.0:
		push_warning("Opponent.ApplySpawnFromPathIndex: path not ready; deferring.")
		# best-effort: cache index to use once path is ready
		start_index = idx
		lane_offset_px = lane_px
		return

	start_index = clamp(idx, 0, max(0, _uv_points.size() - 2)) # -2 because last is a dup of the first
	lane_offset_px = lane_px

	_s_px = _arc_at_index(start_index) + max(0.0, start_offset_px)
	_s_px = fposmod(_s_px, _total_len_px)

	# --- OUTPUT boost multiplier (does NOT change max-cap) ---
	var out_mult := 1.0
	if _nitro_timer > 0.0:
		out_mult = max(out_mult, AI_NITRO_MULT)

	# (optionally include drafting, release boosts, items, etc. here too)
	SetOutputSpeedMultiplier(out_mult)

	_heading = _tangent_angle_at_distance(_s_px)

	var cur_uv: Vector2 = _uv_at_distance(_s_px)
	var tan: Vector2 = _tangent_at_distance(_s_px)
	var right: Vector2 = Vector2(-tan.y, tan.x)
	var final_uv: Vector2 = cur_uv + (lane_offset_px / _pos_scale_px()) * right

	var px: Vector2 = final_uv * _pos_scale_px()
	SetMapPosition(Vector3(px.x, 0.0, px.y))

	# allow faster AI if needed
	if _maxMovementSpeed < max_speed_override:
		_maxMovementSpeed = max_speed_override

	_spawn_locked = true
	
	call_deferred("_ensure_skid_painter_for_me")

# ---------------- convenience ----------------
func _path_node() -> Node:
	return _pn

func _p3d_node() -> Node:
	return _p3d

func _player() -> Node:
	return _pl

func _angle_sprite_node() -> Node:
	return _angle_sprite

func _try_cache_nodes() -> void:
	if _pn == null:
		_pn = get_node_or_null(path_ref)
	if _p3d == null:
		_p3d = get_node_or_null(pseudo3d_ref)
	if _pl == null:
		_pl = get_node_or_null(player_ref)
	if _angle_sprite == null and angle_sprite_path != NodePath():
		_angle_sprite = get_node_or_null(angle_sprite_path)
	if _angle_sprite == null and has_node(^"GFX/AngleSprite"):
		_angle_sprite = get_node_or_null(^"GFX/AngleSprite")
	if _rm == null:
		_rm = get_node_or_null(race_manager_ref)

		
var DEFAULT_POINTS: PackedVector2Array = PackedVector2Array([
	Vector2(920, 584),
	Vector2(950, 607),
	Vector2(920, 631),
	Vector2(950, 655),
	Vector2(920, 679),
	Vector2(950, 703),
	Vector2(920, 727),
	Vector2(950, 751)
])

# ---------------- lifecycle ----------------
func _ready() -> void:
	_last_fwd = Vector2.RIGHT.rotated(rotation)
	
	if _sfx_ai != null:
		# Make sure the SFX script knows who to poll (speed, drift, road type)
		if "player" in _sfx_ai:
			_sfx_ai.player = self
	
	add_to_group("racers")
	add_to_group("opponent")
	
	_hum_rng.randomize()
	_hum_phase = _hum_rng.randf_range(0.0, TAU)
	_hum_noise = _hum_rng.randf_range(0.0, TAU)
		
	_try_cache_nodes()
	_cache_path()

	call_deferred("_ensure_wheel_anchors")
	call_deferred("_ensure_skid_painter_for_me")

	if ReturnSpriteGraphic() == null and has_node(^"GFX/AngleSprite"):
		sprite_graphic_path = ^"GFX/AngleSprite"

	if _uv_points.size() < 2:
		push_error("Opponent: path has < 2 points.")
		return

	# If external code already spawned us, keep it.
	if _spawn_locked:
		# still ensure AI max speed
		if _maxMovementSpeed < max_speed_override:
			_maxMovementSpeed = max_speed_override
		return

	# Original self-placement (only when not externally spawned)
	_s_px = _arc_at_index(start_index) + max(0.0, start_offset_px)
	_s_px = fposmod(_s_px, _total_len_px)

	_heading = _tangent_angle_at_distance(_s_px)

	var uv: Vector2 = _uv_at_distance(_s_px)
	var px: Vector2 = uv * _pos_scale_px()
	SetMapPosition(Vector3(px.x, 0.0, px.y))

	if _maxMovementSpeed < max_speed_override:
		_maxMovementSpeed = max_speed_override
		
	# ---- difficulty baselines ----
	_base_target_speed  = target_speed
	_base_max_speed     = _maxMovementSpeed
	_base_catchup_gain  = catchup_gain_speed
	_base_min_ratio     = min_ratio_vs_player
	_base_max_turn_rate = max_turn_rate
	_base_corner_penalty= speed_damper_on_curve

	if randomize_on_ready:
		var s: int
		if random_seed != 0:
			s = random_seed
		else:
			s = int(Time.get_unix_time_from_system()) ^ get_instance_id()
		ApplyRandomProfile(s, assume_player_target_speed)

func _pos_px_from_mappos(p3: Vector3) -> Vector2i:
	var x := p3.x
	var z := p3.z
	# If values look like UV, convert to pixels
	if abs(x) <= 2.0 and abs(z) <= 2.0:
		var S := _pos_scale_px()
		x *= S
		z *= S
	return Vector2i(int(round(x)), int(round(z)))

func _road_speed_mult(rt: int) -> float:
	match rt:
		Globals.RoadType.ROAD:     return mult_road
		Globals.RoadType.GRAVEL:   return mult_gravel
		Globals.RoadType.OFF_ROAD: return mult_offroad
		Globals.RoadType.SINK:     return mult_sink
		_:                         return 1.0

func _process(delta: float) -> void:
	if _uv_points.is_empty():
		return
	_try_cache_nodes()

	var my3: Vector3 = ReturnMapPosition()
	var pos_px_i := _pos_px_from_mappos(my3)
	var rt_cur := Globals.RoadType.ROAD
	if _has_collision_api():
		rt_cur = _collisionHandler.ReturnCurrentRoadType(pos_px_i)
	var terr_mult := _road_speed_mult(rt_cur)

	# === GO edge-detect (start merge the first frame after GO) ===
	var go_now := Globals.race_can_drive
	if go_now and not _was_go and _merge_armed:
		_merging = true
		_merge_t = 0.0
		_merge_armed = false
	_was_go = go_now

	# === LOCK AI UNTIL "GO" ===
	if not Globals.race_can_drive:
		_movementSpeed = 0.0
		var spf := Engine.get_process_frames()
		if visual_update_stride <= 1 or (spf % visual_update_stride) == 0:
			_update_angle_sprite_fast()
			_update_depth_sort_fast()
		return
	# === /LOCK ===

	var f := Engine.get_process_frames()
	if visual_update_stride <= 1 or (f % visual_update_stride) == 0:
		_update_angle_sprite_fast()
		_update_depth_sort_fast()
		_update_speed_tag()   # <—— add this

	_apply_dynamic_difficulty()

	# === smoothed local frame (gives fwd + right) ===
	var frame_now := _uv_and_tangent_smooth(_s_px)
	var p_uv: Vector2 = frame_now["uv"]
	var fwd_smooth: Vector2 = frame_now["tan"]
	var right_now: Vector2 = Vector2(-fwd_smooth.y, fwd_smooth.x)

	_right_smooth = _exp_smooth_vec(_right_smooth, right_now, delta, right_half_life_s)
	var right: Vector2 = _right_smooth.normalized()

	# --- steering target using smoothed lookahead ---
	# 0 = tight, 1 = straight
	var t0 := _tangent_at_distance(_s_px)
	var t1 := _tangent_at_distance(_s_px + 80.0)
	var straightness = clamp((t0.dot(t1) + 1.0) * 0.5, 0.0, 1.0)  # [-1..1] -> [0..1]
	var L = clamp(lookahead_px_base + lookahead_curv_boost * straightness,
				   lookahead_px_min, lookahead_px_max)
	var tgt := _uv_and_tangent_smooth(_s_px + L)

	var to_t = (tgt["uv"] - p_uv)
	var to_t_len = to_t.length()
	if to_t_len > 0.00001:
		to_t /= to_t_len
	var desired_angle: float = atan2(to_t.y, to_t.x)

	_desired_yaw = _exp_smooth_angle(_desired_yaw, desired_angle, delta, desired_yaw_half_life_s)
	var yaw_err := wrapf(_desired_yaw - _heading, -PI, PI) * steer_gain
	var yaw_step = clamp(yaw_err, -heading_rate_limit * delta, heading_rate_limit * delta)
	yaw_step = clamp(yaw_step, -max_turn_rate * delta, max_turn_rate * delta)
	_heading = wrapf(_heading + yaw_step, -PI, PI)

	# --- curvature proxy using smoothed tangents (no snap) ---
	var dot_raw: float = clamp(t0.dot(t1), -1.0, 1.0)
	var curv_approx: float = 1.0 - max(dot_raw, -1.0)

	# --- desired speed base ---
	var desired_speed: float = target_speed

	if _is_drifting:
		desired_speed *= DRIFT_SPEED_MULT
		
	# --- apply nitro boost ---
	if _nitro_timer > 0.0:
		desired_speed *= AI_NITRO_MULT

	# --- catch-up vs player (do this before corner/terrain clamps) ---
	var pl := _player()
	if pl != null:
		var pl_speed: float = 0.0
		if pl.has_method("ReturnMovementSpeed"):
			pl_speed = float(pl.call("ReturnMovementSpeed"))

		var p3d := _p3d_node()
		var cam_f: Vector2 = Vector2(0, 1)
		if p3d != null and p3d.has_method("get_camera_forward_map"):
			cam_f = (p3d.call("get_camera_forward_map") as Vector2)
			var c_len := cam_f.length()
			if c_len > 0.00001:
				cam_f /= c_len

		var pl_pos3: Vector3 = (pl.call("ReturnMapPosition") as Vector3)
		var fwd_gap: float = (Vector2(pl_pos3.x - my3.x, pl_pos3.z - my3.z)).dot(cam_f)

		if fwd_gap > catchup_deadzone_uv:
			var eff_gap: float = fwd_gap - catchup_deadzone_uv
			desired_speed += eff_gap * catchup_gain_speed

		var min_over: float = pl_speed * min_ratio_vs_player
		if desired_speed < min_over:
			desired_speed = min_over

	# --- corner damping ---
	var curv_u = clamp(curv_approx / 0.6, 0.0, 1.0)
	var corner_mult: float = lerp(1.0, speed_damper_on_curve, curv_u)
	desired_speed *= corner_mult

	# --- terrain slow-down & cap (like player) ---
	desired_speed *= terr_mult
	desired_speed = min(desired_speed, _maxMovementSpeed * terr_mult)

	# --- accel/decel toward desired (optionally scale accel by surface grip) ---
	var accel_eff: float = accel * lerp(1.0, terr_mult, accel_surface_gain)
	
	if _movementSpeed < desired_speed:
		_movementSpeed = min(desired_speed, _movementSpeed + accel_eff * delta)
	else:
		_movementSpeed = max(desired_speed, _movementSpeed - accel_eff * delta)

	# advance along path
	_s_px = fposmod(_s_px + _movementSpeed * delta, _total_len_px)

	# compute current & target UVs for lane/humanization
	var cur_uv: Vector2 = _uv_at_distance(_s_px)
	var lane_px_now: float = lane_offset_px
	var target_uv: Vector2 = cur_uv + (lane_px_now / _pos_scale_px()) * right

	# during merge, blend the target UV, but still move through the physics pipe
	if _merging:
		_merge_t += delta / max(0.0001, merge_time_s)
		if _merge_t >= 1.0:
			_merge_t = 1.0
			_merging = false
		var target_uv_blend: Vector2 = _merge_start_uv.lerp(target_uv, _merge_t)
		_physics_step_like_player(cur_uv, right, target_uv_blend, delta)
	else:
		_physics_step_like_player(cur_uv, right, target_uv, delta)

	# collisions / visuals
	if _isPushedBack:
		ApplyCollisionBump()

	if visual_update_stride <= 1 or (f % visual_update_stride) == 0:
		_update_angle_sprite_fast()
		_update_depth_sort_fast()

	if debug_log_ai_sprite and (f % 60 == 0):
		var sp := ReturnSpriteGraphic()
		prints("AI sprite:", sp, " path:", str(get("sprite_graphic_path")))

	if _hit_sfx_cd > 0.0:
		_hit_sfx_cd = max(0.0, _hit_sfx_cd - delta)
		
	# === Drift sensing (central, smoothed, signed) ===
	var ta: Vector2 = (_uv_and_tangent_smooth(_s_px - DRIFT_SIGN_SAMPLE_PX)["tan"] as Vector2)
	var tb: Vector2 = (_uv_and_tangent_smooth(_s_px + DRIFT_SIGN_SAMPLE_PX)["tan"] as Vector2)

	# signed turn: >0 = left, <0 = right
	var drift_turn_sin: float = ta.x * tb.y - ta.y * tb.x
	var drift_turn_sign: float = signf(drift_turn_sin)

	# curvature magnitude in [0..~1], smoothed for stability
	var drift_curv_raw: float = 1.0 - clampf(ta.dot(tb), -1.0, 1.0)
	_curv_ema = lerpf(_curv_ema, drift_curv_raw, DRIFT_CURV_ALPHA)
	var drift_curv: float = _curv_ema

	# hysteresis gates
	var want_drift: bool = (
		drift_curv >= DRIFT_CURV_START
		and _movementSpeed >= DRIFT_MIN_SPEED
		and drift_turn_sign != 0.0
	)

	if want_drift:
		_is_drifting = true
		_drift_linger = DRIFT_RELEASE_S
		_drift_sign = drift_turn_sign
		var target_slip: float = DRIFT_SLIP_MAX * clampf(drift_curv, 0.0, 1.0)
		_drift_slip = move_toward(_drift_slip, target_slip, DRIFT_SLIP_ACCEL * delta)
	else:
		_drift_linger = maxf(0.0, _drift_linger - delta)
		if drift_curv <= DRIFT_CURV_STOP and _drift_linger <= 0.0:
			_is_drifting = false
		_drift_slip = move_toward(_drift_slip, 0.0, DRIFT_SLIP_ACCEL * delta)

	# option A: wall-clock throttle (every ~250 ms)
	if want_drift and int(Time.get_ticks_msec() / 250) % 2 == 0:
		prints(name, "drift_curv=", String.num(drift_curv, 3), "speed=", int(_movementSpeed))

	
func _apply_dynamic_difficulty() -> void:
	# Determine lap driving the difficulty
	var lap_for_diff := 0
	if _rm != null:
		if diff_use_player_lap and _rm.has_method("GetPlayerLap"):
			lap_for_diff = int(_rm.call("GetPlayerLap"))
		elif _rm.has_method("GetLeaderLap"):
			lap_for_diff = int(_rm.call("GetLeaderLap"))

	# How many laps into the difficulty window are we?
	var laps_into = max(0, lap_for_diff - diff_start_lap)
	if laps_into <= 0:
		# Reset to baselines if we're before the start lap
		target_speed = _base_target_speed
		_maxMovementSpeed = _base_max_speed
		catchup_gain_speed = _base_catchup_gain
		min_ratio_vs_player = _base_min_ratio
		max_turn_rate = _base_max_turn_rate
		speed_damper_on_curve = _base_corner_penalty
		return

	# Scale knobs
	var new_target = _base_target_speed + laps_into * diff_speed_per_lap
	var new_maxcap = min(_base_max_speed + laps_into * diff_max_speed_per_lap, diff_max_speed_cap)
	var new_catchup = _base_catchup_gain + laps_into * diff_catchup_gain_per_lap
	var new_min_ratio = min(_base_min_ratio + laps_into * diff_min_ratio_per_lap, diff_max_min_ratio)
	var new_turn = _base_max_turn_rate + laps_into * diff_turn_per_lap
	var new_corner = clamp(_base_corner_penalty + laps_into * diff_corner_penalty_decay, diff_min_corner_penalty, 1.0)

	# Apply
	target_speed = new_target
	_maxMovementSpeed = new_maxcap
	catchup_gain_speed = new_catchup
	min_ratio_vs_player = new_min_ratio
	max_turn_rate = new_turn
	speed_damper_on_curve = new_corner

# ---- visuals (fast paths) ----
func _update_angle_sprite_fast() -> void:
	var sp := _angle_sprite_node()
	if sp == null:
		return
	var p3d := _p3d_node()
	if p3d == null:
		return

	var cam_f: Vector2 = (p3d.call("get_camera_forward_map") as Vector2)
	var cam_yaw: float = atan2(cam_f.y, cam_f.x)

	var theta_cam: float = wrapf(_heading - cam_yaw, -PI, PI)
	var deg: float = rad_to_deg(theta_cam)

	deg = wrapf(deg + angle_offset_deg, -180.0, 180.0)
	if not clockwise:
		deg = -deg

	var left_side := deg > 0.0
	var absdeg: float = clamp(abs(deg), 0.0, 179.999)
	var step: float = 180.0 / float(DIRECTIONS)
	var idx: int = int(floor((absdeg + step * 0.5) / step))
	if idx >= DIRECTIONS:
		idx = DIRECTIONS - 1

	if frame0_is_front:
		idx = (DIRECTIONS - 1) - idx

	if sp is Sprite2D:
		var s := sp as Sprite2D
		if s.hframes != DIRECTIONS:
			s.hframes = DIRECTIONS
			s.vframes = 1
		s.frame = idx
		s.flip_h = left_side
	elif sp.has_method("set_frame"):
		sp.frame = idx
		if "flip_h" in sp:
			sp.flip_h = left_side

func _update_depth_sort_fast() -> void:
	var p3d := _p3d_node()
	var pl := _player()
	if p3d == null or pl == null:
		return

	var cam_f: Vector2 = p3d.call("get_camera_forward_map") as Vector2
	var c_len := cam_f.length()
	if c_len > 0.00001:
		cam_f /= c_len

	var my_pos: Vector3 = ReturnMapPosition()
	var pl_pos: Vector3 = pl.call("ReturnMapPosition") as Vector3
	var depth: float = Vector2(my_pos.x - pl_pos.x, my_pos.z - pl_pos.z).dot(cam_f)

	# Sort only; no hard cull here
	visible = true
	z_index = int(depth * 100000.0)


# ---------------- path helpers (use inherited arrays) ----------------
func _pos_scale_px() -> float:
	var pn := _path_node()
	if pn != null and ("pos_scale_px" in pn):
		return float(pn.pos_scale_px)
	return 1024.0

func _cache_path() -> void:
	_uv_points = PackedVector2Array()
	_path_len = PackedFloat32Array()
	_path_tan = PackedVector2Array()
	_seg_tan = PackedVector2Array()
	_path_ready = false

	_try_cache_nodes()
	var pn := _path_node()
	if pn == null:
		return

	if pn.has_method("get_path_points_uv_transformed"):
		_uv_points = pn.call("get_path_points_uv_transformed")
	elif pn.has_method("get_path_points_uv"):
		_uv_points = pn.call("get_path_points_uv")
	else:
		return

	if _uv_points.size() < 2:
		return

	# --- ensure true UVs (same logic) ---
	var min_v := Vector2(1e30, 1e30)
	var max_v := Vector2(-1e30, -1e30)
	for p in _uv_points:
		if p.x < min_v.x: min_v.x = p.x
		if p.y < min_v.y: min_v.y = p.y
		if p.x > max_v.x: max_v.x = p.x
		if p.y > max_v.y: max_v.y = p.y
	var ext := max_v - min_v
	var scale_px := _pos_scale_px()

	if ext.x > 2.0 or ext.y > 2.0:
		for i in range(_uv_points.size()):
			_uv_points[i] /= scale_px
	elif ext.x < 0.01 and ext.y < 0.01:
		for i in range(_uv_points.size()):
			_uv_points[i] *= scale_px

	if _uv_points[0] != _uv_points[_uv_points.size() - 1]:
		_uv_points.append(_uv_points[0])

	# Build cumulative length in pixels + per-segment tangents
	_path_len.resize(_uv_points.size())
	_path_len[0] = 0.0
	var total: float = 0.0

	_seg_tan.resize(max(1, _uv_points.size() - 1))
	for i in range(1, _uv_points.size()):
		var d_uv := _uv_points[i] - _uv_points[i - 1]
		var d_len_px := d_uv.length() * scale_px
		total += d_len_px
		_path_len[i] = total

		# segment tangent (unit in UV space) – reused often
		var t: Vector2 = d_uv
		var t_len := t.length()
		_seg_tan[i - 1] = (t / (t_len if t_len > 0.00001 else 1.0))

	_total_len_px = total
	_cum_len_px = _path_len
	_path_ready = true

# Binary search helper: returns segment index i such that s is in [len[i], len[i+1]]
func _find_segment(s_px: float) -> int:
	if _path_len.is_empty():
		return 0
	var s := fposmod(s_px, _total_len_px)
	var lo := 0
	var hi := _path_len.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) >> 1
		if _path_len[mid] <= s:
			lo = mid
		else:
			hi = mid
	return lo

func _arc_at_index(i: int) -> float:
	if _path_len.is_empty(): return 0.0
	i = clamp(i, 0, _path_len.size() - 1)
	return _path_len[i]

func _uv_at_distance(s_px: float) -> Vector2:
	if _path_len.is_empty(): return Vector2.ZERO
	var s := fposmod(s_px, _total_len_px)
	var i: int = _find_segment(s)
	var a: Vector2 = _uv_points[i]
	var b: Vector2 = _uv_points[i + 1]
	var seg0: float = _path_len[i]
	var seg1: float = _path_len[i + 1]
	var denom = max(seg1 - seg0, 0.0001)
	var t: float = (s - seg0) / denom
	return a.lerp(b, t)

func _tangent_at_distance(s_px: float) -> Vector2:
	if _uv_points.size() < 2:
		return Vector2.RIGHT
	var s := fposmod(s_px, _total_len_px)
	var i: int = _find_segment(s)
	# Use precomputed segment tangent
	return _seg_tan[i]

func _tangent_angle_at_distance(s_px: float) -> float:
	var t: Vector2 = _tangent_at_distance(s_px)
	return atan2(t.y, t.x)

func update_screen_transform(camera_pos: Vector2) -> void:
	# Let base place us (uses pseudo.get_camera_forward_map(), which flips in rear view)
	super(camera_pos)

	# Optional: your near/far scale blending stays
	var pl := _player()
	if pl == null or not (pl is Node2D):
		return

	var my3: Vector3 = ReturnMapPosition()
	var pl3: Vector3 = pl.call("ReturnMapPosition") as Vector3
	var d_uv := Vector2(my3.x, my3.z).distance_to(Vector2(pl3.x, pl3.z))

	var spr := ReturnSpriteGraphic()
	var h_px := 32.0
	if spr != null and "region_rect" in spr and spr.region_rect.size.y > 0.0:
		h_px = spr.region_rect.size.y

	var tex_w: float = 1024.0
	if "_pseudo" in self and _pseudo != null:
		var p3d_fb := _pseudo as Sprite2D
		if p3d_fb != null and p3d_fb.texture != null:
			tex_w = float(p3d_fb.texture.get_size().x)

	var uv_footprint = h_px / max(tex_w, 1.0)
	var R = uv_footprint * 6.0
	var snap_threshold = R * 0.6

	var pl_sc := (pl as Node2D).scale.x
	var my_sc := scale.x
	var target: float
	if d_uv <= snap_threshold:
		target = pl_sc
	else:
		var w = R / (R + d_uv)
		target = lerp(my_sc, pl_sc, clamp(w, 0.0, 1.0))

	var dt := get_process_delta_time()
	var near_hl := 0.04
	var far_hl  := 0.10
	var hl = lerp(near_hl, far_hl, clamp(d_uv / (R * 2.0), 0.0, 1.0))
	var sm := _smooth_scalar(my_sc, target, dt, hl)
	scale = Vector2(sm, sm)

func DefaultCount() -> int:
	return DEFAULT_POINTS.size()

# Spawn at DEFAULT_POINTS[idx] (pixels), then follow the current path smoothly.
func ApplySpawnFromDefaultIndex(idx: int, lane_px: float = 0.0) -> void:
	_try_cache_nodes()
	_cache_path()
	if _uv_points.size() < 2 or _total_len_px <= 0.0 or DEFAULT_POINTS.size() == 0:
		push_warning("Opponent.ApplySpawnFromDefaultIndex: path/defaults not ready; deferring.")
		start_index = clamp(idx, 0, max(0, _uv_points.size() - 2))
		lane_offset_px = lane_px
		return

	# 1) Clamp index and read the pixel point
	var di = clamp(idx, 0, max(0, DEFAULT_POINTS.size() - 1))
	var spawn_px: Vector2 = DEFAULT_POINTS[di]

	# 2) Place EXACTLY at that pixel (respecting lane offset along path tangent once we know it)
	var scale_px := _pos_scale_px()
	var spawn_uv := spawn_px / scale_px

	# 3) Project spawn_uv to nearest path segment -> compute _s_px (arc) and heading
	var best_i := 0
	var best_t := 0.0
	var best_d := 1e30
	for i in range(_uv_points.size() - 1):
		var a: Vector2 = _uv_points[i]
		var b: Vector2 = _uv_points[i + 1]
		var ab := b - a
		var ab_len2 := ab.length_squared()
		if ab_len2 < 1e-9:
			continue
		var t := (spawn_uv - a).dot(ab) / ab_len2
		if t < 0.0:
			t = 0.0
		if t > 1.0:
			t = 1.0
		var p := a.lerp(b, t)
		var d := (spawn_uv - p).length_squared()
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t

	var seg0_px := _path_len[best_i]
	var seg1_px := _path_len[best_i + 1]
	_s_px = fposmod(seg0_px + (seg1_px - seg0_px) * best_t, _total_len_px)
	_heading = _tangent_angle_at_distance(_s_px)

	# 4) Apply lane offset (perpendicular to path tangent)
	var tan: Vector2 = _tangent_at_distance(_s_px)
	var right: Vector2 = Vector2(-tan.y, tan.x) # unit
	var final_uv: Vector2 = spawn_uv + (lane_px / scale_px) * right

	# 5) Write final pixel position and lock
	var final_px: Vector2 = final_uv * scale_px
	SetMapPosition(Vector3(final_px.x, 0.0, final_px.y))

	if _maxMovementSpeed < max_speed_override:
		_maxMovementSpeed = max_speed_override

	_spawn_locked = true

func _neighbors_ahead(max_dist_px: float) -> Array:
	# Return [ {pos3, vel3, uv, lane_sep_px, forward_sep_px, node}, ... ] for racers in front cone.
	var out: Array = []
	var me3: Vector3 = ReturnMapPosition()
	var me_fwd: Vector2 = _tangent_at_distance(_s_px) # map forward (unit)

	var right: Vector2 = Vector2(-me_fwd.y, me_fwd.x)
	var racers := get_tree().get_nodes_in_group("racers")
	for n in racers:
		if n == self: continue
		if not is_instance_valid(n): continue
		if not n.has_method("ReturnMapPosition"): continue
		var p3 = n.ReturnMapPosition()
		var dp := Vector2(p3.x - me3.x, p3.z - me3.z)
		var fsep := dp.dot(me_fwd)
		if fsep < -10.0 or fsep > max_dist_px: # behind or too far
			continue
		var lsep := dp.dot(right)
		var vel3 := Vector3.ZERO
		if n.has_method("ReturnVelocity"):
			var vv = n.call("ReturnVelocity")
			if vv is Vector3: vel3 = vv
		out.append({
			"pos3": p3,
			"vel3": vel3,
			"uv": Vector2(p3.x, p3.z),
			"forward_sep_px": fsep,
			"lateral_sep_px": lsep,
			"node": n
		})
	return out

func _predict_pos(p3: Vector3, v3: Vector3, t: float) -> Vector2:
	var q := p3 + v3 * t
	return Vector2(q.x, q.z)

func _upcoming_turn_sign() -> float:
	# crude curvature sign using two tangents ahead
	var t0 := _tangent_at_distance(_s_px)
	var t1 := _tangent_at_distance(_s_px + lookahead_px)
	# 2D cross product z-component: >0 left turn, <0 right turn
	return sign(t0.x * t1.y - t0.y * t1.x)

func _score_lane(candidate_px: float, ahead: Array, dt: float) -> float:
	# higher score = better lane
	var me3: Vector3 = ReturnMapPosition()
	var me_uv := Vector2(me3.x, me3.z)
	var fwd := _tangent_at_distance(_s_px)
	var right := Vector2(-fwd.y, fwd.x)

	var T := avoid_lookahead_s
	var safety: float = 1.0
	var clearance_min := 1e9
	var blocked := false

	for e in ahead:
		var p3: Vector3 = e["pos3"]
		var v3: Vector3 = e["vel3"]
		# predict their future pos along our horizon
		var q_uv := _predict_pos(p3, v3, T)
		# our future center in this lane
		var my_uv_future = me_uv + fwd * (min(_movementSpeed, _maxMovementSpeed) * T)
		my_uv_future += right * candidate_px

		var d = (q_uv - my_uv_future)
		var fsep = d.dot(fwd)
		var lsep = abs(d.dot(right))

		clearance_min = min(clearance_min, lsep)
		if (fsep > -avoid_width_px) and (fsep < avoid_width_px*2.0) and (lsep < (avoid_width_px*1.1)):
			blocked = true
			safety -= 0.5

	# prefer outside of upcoming turn
	var turn_sig := _upcoming_turn_sign() # +1 left, -1 right
	var outer_bias := 0.0
	if turn_sig != 0.0:
		# left turn: outer is +right; right turn: outer is +left
		var want_right := (turn_sig > 0.0)
		if (want_right and candidate_px > 0.0) or (not want_right and candidate_px < 0.0):
			outer_bias = pass_bias_outer_on_turn

	# distance from current lane to reduce thrash
	var change_penalty = abs(candidate_px - lane_offset_px) * 0.003

	# reward clearance, penalize blocked, add small bias for outside on turn
	var clearance_term = clamp(clearance_min / (avoid_width_px * 2.0), 0.0, 1.0)

	var blocked_penalty: float
	if blocked:
		blocked_penalty = 0.35
	else:
		blocked_penalty = 0.0

	return safety + clearance_term + outer_bias - change_penalty - blocked_penalty

func _exp_smooth_angle(prev: float, target: float, dt: float, half_life: float) -> float:
	var hl = max(half_life, 0.0001)
	var a := 1.0 - pow(0.5, dt / hl)
	var d := wrapf(target - prev, -PI, PI)
	return wrapf(prev + d * a, -PI, PI)

# Arm a glide from an off-path grid UV to the on-path target after GO (no snap).
func ArmMergeFromGrid(start_uv: Vector2, path_idx: int, lane_px: float = 0.0) -> void:
	_try_cache_nodes()
	_cache_path()
	if _uv_points.size() < 2 or _total_len_px <= 0.0:
		# cache intent; we'll still be locked so _ready() won't re-place us
		start_index = clamp(path_idx, 0, max(0, _uv_points.size() - 2))
		lane_offset_px = lane_px
		_spawn_locked = true
		return

	start_index = clamp(path_idx, 0, max(0, _uv_points.size() - 2))
	lane_offset_px = lane_px

	# set internal path arc & heading (target we will glide toward)
	_s_px = _arc_at_index(start_index) + max(0.0, start_offset_px)
	_s_px = fposmod(_s_px, _total_len_px)
	_heading = _tangent_angle_at_distance(_s_px)

	# HOLD the visual at the grid UV for pre-GO countdown
	var scale_px := _pos_scale_px()
	_merge_start_uv = start_uv
	var hold_px := _merge_start_uv * scale_px
	SetMapPosition(Vector3(hold_px.x, 0.0, hold_px.y))

	# arm the merge for GO
	_merge_armed = true
	_spawn_locked = true

	# speed headroom like other spawns
	if _maxMovementSpeed < max_speed_override:
		_maxMovementSpeed = max_speed_override

func _rf(rng: RandomNumberGenerator, a: float, b: float) -> float:
	return rng.randf_range(a, b)

func _pick_i(rng: RandomNumberGenerator, arr: Array) -> int:
	if arr.is_empty(): return 0
	return arr[rng.randi_range(0, arr.size() - 1)]

# Public API: call this to (re)roll an opponent. Pass the player's target speed (150 now).
func ApplyRandomProfile(seed: int = 0, player_speed: float = -1.0) -> void:
	var rng := RandomNumberGenerator.new()
	if seed == 0:
		rng.randomize()
	else:
		rng.seed = seed

	var pspd: float
	if player_speed > 0.0:
		pspd = player_speed
	else:
		pspd = assume_player_target_speed

	# ---- choose an archetype (weighted) ----
	var archetypes := ["Balanced", "Sprinter", "Cornerer", "Rubberband", "Human"]
	var weights := [0.36, 0.18, 0.18, 0.16, 0.12]  # must sum ~1
	var r := rng.randf()
	var acc := 0.0
	var arche := "Balanced"
	for i in weights.size():
		acc += weights[i]
		if r <= acc:
			arche = archetypes[i]
			break

	# ---- base rolls (soft, then arche tweaks) ----
	var speed_factor := _rf(rng, 0.90, 1.15)     # vs player speed
	if rng.randf() < 0.12:                       # rare "hot" rival
		speed_factor = _rf(rng, 1.18, 1.23)

	target_speed = pspd * speed_factor
	accel        = _rf(rng, 150.0, 240.0)
	max_turn_rate = _rf(rng, 2.2, 4.0)           # rad/s
	steer_gain    = _rf(rng, 0.85, 1.25)
	lookahead_px_base = _rf(rng, 110.0, 180.0)
	speed_damper_on_curve = _rf(rng, 0.50, 0.85) # 1=no slow, 0.5=more slow on corners

	catchup_gain_speed  = _rf(rng, 260.0, 440.0)
	min_ratio_vs_player = _rf(rng, 1.02, 1.18)

	# Smoothing / control feel
	desired_yaw_half_life_s = _rf(rng, 0.08, 0.16)
	heading_rate_limit       = _rf(rng, 2.1, 3.2)
	anti_snap_window_px      = _rf(rng, 20.0, 40.0)
	right_half_life_s        = _rf(rng, 0.05, 0.12)

	# Traffic / passing
	avoid_lookahead_s = _rf(rng, 0.60, 1.10)
	avoid_width_px    = _rf(rng, 18.0, 26.0)
	pass_bias_outer_on_turn = _rf(rng, 0.10, 0.28)
	pass_cooldown_s   = _rf(rng, 0.45, 0.90)
	block_slow_mult   = _rf(rng, 0.78, 0.90)
	lane_lerp_hz      = _rf(rng, 4.0, 8.0)
	lane_candidates_px = PackedFloat32Array([-16.0, -16.0, 0.0, 16.0, 16.0])

	# Drafting
	draft_enabled   = rng.randf() < 0.85
	draft_dist_px   = _rf(rng, 50.0, 68.0)
	draft_lateral_px= _rf(rng, 6.0, 14.0)
	draft_speed_bonus = _rf(rng, 8.0, 16.0)

	# Humanization
	humanize_enabled     = true
	humanize_amp_px      = _rf(rng, 3.0, 10.0)
	humanize_freq_hz     = _rf(rng, 0.45, 0.75)
	humanize_noise_hz    = _rf(rng, 0.25, 0.55)
	humanize_corner_fade = _rf(rng, 0.30, 0.60)
	humanize_nearby_fade_px = _rf(rng, 42.0, 64.0)

	# Lane preference (small personality nudge)
	var lane_pick := _pick_i(rng, [-28, 0, 28])
	lane_offset_px = float(lane_pick) + _rf(rng, -6.0, 6.0)

	# Archetype tweaks
	match arche:
		"Sprinter":
			accel *= _rf(rng, 1.15, 1.35)
			target_speed *= _rf(rng, 0.98, 1.03)
			speed_damper_on_curve = min(0.78, speed_damper_on_curve) # slows more in turns
		"Cornerer":
			max_turn_rate *= _rf(rng, 1.15, 1.35)
			steer_gain    *= _rf(rng, 1.05, 1.20)
			speed_damper_on_curve = max(0.75, speed_damper_on_curve) # keeps speed in turns
			lookahead_px_base     = _rf(rng, 150.0, 220.0)
		"Rubberband":
			target_speed *= _rf(rng, 0.94, 1.02)  # a tad lower base
			catchup_gain_speed = _rf(rng, 420.0, 520.0)
			min_ratio_vs_player = _rf(rng, 1.12, 1.22)
		"Human":
			humanize_amp_px   *= _rf(rng, 1.2, 1.6)
			humanize_freq_hz  *= _rf(rng, 0.9, 1.2)
			pass_cooldown_s   *= _rf(rng, 1.0, 1.4)
		_:
			pass # Balanced

	# Respect caps and give some headroom over target speed
	_maxMovementSpeed = min(diff_max_speed_cap, max_speed_override,
		target_speed + _rf(rng, 40.0, 90.0))

	# --- per-lap difficulty growth (kept modest, but varied) ---
	if rng.randf() < 0.35:
		diff_start_lap = 0
	else:
		diff_start_lap = 1

	diff_speed_per_lap          = _rf(rng, 4.0, 9.0)
	diff_max_speed_per_lap      = _rf(rng, 3.0, 6.0)
	diff_catchup_gain_per_lap   = _rf(rng, 12.0, 28.0)
	diff_min_ratio_per_lap      = _rf(rng, 0.005, 0.020)
	diff_turn_per_lap           = _rf(rng, 0.03, 0.08)
	diff_corner_penalty_decay   = _rf(rng, 0.010, 0.040)

	# Make sure the curve penalty never exceeds bounds
	diff_min_corner_penalty = 0.40
	diff_max_min_ratio      = 1.40
	diff_max_speed_cap      = 420.0

	# ---- lock baselines so your dynamic difficulty scales from this new profile ----
	_base_target_speed  = target_speed
	_base_max_speed     = _maxMovementSpeed
	_base_catchup_gain  = catchup_gain_speed
	_base_min_ratio     = min_ratio_vs_player
	_base_max_turn_rate = max_turn_rate
	_base_corner_penalty= speed_damper_on_curve

	# optional: remember we were randomized (helps avoid double-randomization)
	_spawn_locked = _spawn_locked  # no-op; here just to show we do not change merge/spawn state

# --- Opponent physics glue: move like Player (shared pipeline) ---

# How fast we’re allowed to slide laterally toward our lane (px/s)
@export var lane_chase_speed_px: float = 240.0

# Soft damping for the lateral controller
@export var lane_chase_damp: float = 6.0

var _lane_side_vel: float = 0.0  # px/s along "right" (signed)

func _physics_step_like_player(p_uv: Vector2, right: Vector2, target_uv: Vector2, dt: float) -> void:
	# ensure 'right' is unit length (it should be, but be safe)
	if right.length_squared() > 1.0001 or right.length_squared() < 0.9999:
		right = right.normalized()

	var scale_px := _pos_scale_px()

	# REAL current position in map pixels (❗️previously: p_uv*scale)
	var my_px := Vector2(_mapPosition.x, _mapPosition.z)

	# ideal target in map pixels
	var tgt_px := target_uv * scale_px

	# build a local frame at current heading
	var fwd := Vector2(cos(_heading), sin(_heading))      # unit
	var rgt := right                                      # unit (from smoothed path)

	# position error in world/map space
	var err_vec := tgt_px - my_px
	var err_side := err_vec.dot(rgt)                      # signed lateral px
	var err_fwd  := err_vec.dot(fwd)                      # forward/backward px (useful for pinch recovery)

	# --- lateral controller toward lane (critically-damped-ish) ---
	var want_side_vel = clamp(err_side * lane_lerp_hz, -lane_chase_speed_px, lane_chase_speed_px)
	_lane_side_vel = lerp(_lane_side_vel, want_side_vel, clamp(dt * lane_chase_damp, 0.0, 1.0))

	# soft nudge forward if we’re behind the target along the track (prevents “stick on inside wall”)
	var fwd_nudge := 0.0
	if err_fwd > 0.0:
		# small assist that diminishes with speed; tune 0.4..0.8
		fwd_nudge = min(0.0, err_fwd * 0.15)

	# compose intended velocity (px/s)
	var v_forward := fwd * (_movementSpeed + fwd_nudge)
	var v_side    := rgt * _lane_side_vel
	var v_total   := v_forward + v_side

	# Extra outward slide while drifting
	if _is_drifting:
		v_total += rgt * (_drift_slip * _drift_sign)
		
	# predict, axis-resolve like Player
	var nextPos := _mapPosition + Vector3(v_total.x, 0.0, v_total.y) * dt

	# axis-wise wall resolution (slide along the free axis)
	var hit_x := false
	var hit_z := false
	if _has_collision_api():
		hit_x = _collisionHandler.IsCollidingWithWall(Vector2i(ceil(nextPos.x), ceil(_mapPosition.z)))
		if hit_x:
			nextPos.x = _mapPosition.x
			SetCollisionBump(Vector3(-sign(v_total.x), 0.0, 0.0))
			if _hit_sfx_cd <= 0.0 and _sfx_ai != null and _sfx_ai.has_method("play_collision"):
				_sfx_ai.play_collision()
				_hit_sfx_cd = 0.12

		hit_z = _collisionHandler.IsCollidingWithWall(Vector2i(ceil(_mapPosition.x), ceil(nextPos.z)))
		if hit_z:
			nextPos.z = _mapPosition.z
			SetCollisionBump(Vector3(0.0, 0.0, -sign(v_total.y)))
			if _hit_sfx_cd <= 0.0 and _sfx_ai != null and _sfx_ai.has_method("play_collision"):
				_sfx_ai.play_collision()
				_hit_sfx_cd = 0.12
	# if handler is not ready yet, skip wall tests this frame

	# if an axis hit, damp side velocity to stop grinding
	if hit_x:
		_lane_side_vel *= 0.5
	if hit_z:
		_lane_side_vel *= 0.5

	# AI↔AI body collision (unchanged)
	nextPos = _ai_resolve_body_overlap(nextPos, dt)

	# terrain + finalize
	var nextPixelPos : Vector2i = Vector2i(ceil(nextPos.x), ceil(nextPos.z))
	var curr_rt := Globals.RoadType.ROAD
	if _has_collision_api():
		curr_rt = _collisionHandler.ReturnCurrentRoadType(nextPixelPos)
	HandleRoadType(nextPixelPos, curr_rt)

	SetMapPosition(nextPos)

	_ai_tick_nitro(get_process_delta_time())
	_apply_nitro_fx(Vector3(cos(_heading), 0.0, sin(_heading)))

	# UpdateMovementSpeed()   # keep this disabled for AI
	var mapForward := Vector3(fwd.x, 0.0, fwd.y)
	UpdateVelocity(mapForward)


func _ensure_nitro_material() -> void:
	if _nitro_mat != null:
		return
	var sh := load(nitro_shader_path)
	if sh == null:
		return
	_nitro_mat = ShaderMaterial.new()
	_nitro_mat.shader = sh
	# set shared nitro defaults
	_nitro_mat.set_shader_parameter("glow_color", nitro_glow_color)
	_nitro_mat.set_shader_parameter("outline_px", nitro_outline_px)
	_nitro_mat.set_shader_parameter("chroma_px", 0.0)
	_nitro_mat.set_shader_parameter("intensity", 0.0)
	_nitro_mat.set_shader_parameter("dir2", Vector2(1,0))
	# IMPORTANT: copy over base shader parameters
	var spr := ReturnSpriteGraphic()
	if spr != null and spr.material is ShaderMaterial:
		var base := spr.material as ShaderMaterial
		for p in base.shader.get_shader_uniform_list():
			_nitro_mat.set_shader_parameter(p.name, base.get_shader_parameter(p.name))
	spr.material = _nitro_mat

func _apply_nitro_fx(mapForward: Vector3) -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return

	var live := 1.0 if _nitro_timer > 0.0 else 0.0

	if live >= 0.0:
		_ensure_nitro_material()
		if _nitro_mat == null:
			return

		# First time swap: cache ALL uniforms from the original shader
		if spr.material != _nitro_mat:
			if _nitro_prev_material == null and spr.material is ShaderMaterial:
				_nitro_prev_material = spr.material.duplicate()  # duplicate ensures instance copy
				_prev_uniforms.clear()
				for u in (_nitro_prev_material.shader.get_shader_uniform_list()):
					var pname = u.name
					if _nitro_prev_material.shader.has_param(pname):
						_prev_uniforms[pname] = _nitro_prev_material.get_shader_parameter(pname)
			spr.material = _nitro_mat

		# Ease in nitro pulse
		var eased := pow(live, 0.5)
		var inten = clamp(eased * nitro_intensity_max, 0.0, 1.0)
		var chroma = nitro_chroma_max_px * inten

		var dir2 := Vector2(mapForward.x, mapForward.z)
		if dir2.length() > 0.00001:
			dir2 = dir2.normalized()
		else:
			dir2 = Vector2(1, 0)

		_nitro_mat.set_shader_parameter("intensity", inten)
		_nitro_mat.set_shader_parameter("chroma_px", chroma)
		_nitro_mat.set_shader_parameter("dir2", dir2)

	else:
		# Restore original shader with its saved uniforms
		if spr.material == _nitro_mat and _nitro_prev_material != null:
			spr.material = _nitro_prev_material

			# reapply saved uniforms (ensures car keeps its unique color)
			if _prev_uniforms.size() > 0 and spr.material is ShaderMaterial:
				for pname in _prev_uniforms.keys():
					if spr.material.shader.has_param(pname):
						spr.material.set_shader_parameter(pname, _prev_uniforms[pname])

		_nitro_prev_material = null
		_prev_uniforms.clear()

func OnBumped(other: Node, strength_pxps: float, overlap_uv: float) -> void:
	# lane shove (no ternary)
	var side: float = -1.0
	if randf() >= 0.5:
		side = 1.0
	lane_offset_px = clamp(
		lane_offset_px + side * min(16.0, 0.16 * strength_pxps),
		-16.0, 16.0
	)

	# small speed hit on hard bumps
	if strength_pxps > 80.0:
		_movementSpeed *= 0.90

	# quick flash so you can *see* it happened
	var spr := ReturnSpriteGraphic()
	if spr != null:
		var pre := spr.modulate
		var tw := create_tween()
		tw.tween_property(spr, "modulate", Color(1.0,0.65,0.25,1.0), 0.05)
		tw.tween_property(spr, "modulate", pre, 0.12)
		
	_bprint("%s OnBumped by %s  strength=%.1f  overlap_uv=%.5f  lane_px=%.1f"
		% [_bname(self), _bname(other), strength_pxps, overlap_uv, lane_offset_px])
		

func _ai_collision_radius_px() -> float:
	if has_method("ReturnCollisionRadiusUV"):
		return max(0.0, float(call("ReturnCollisionRadiusUV")) * _pos_scale_px())
	var s := ReturnSpriteGraphic()
	var h := 32.0
	if s != null and "region_rect" in s and s.region_rect.size.y > 0.0:
		h = s.region_rect.size.y
	return max(0.0, h * 0.20) # tiny fallback only

# Resolve overlap against nearby racers (AI and player) and add a small impulse
func _ai_resolve_body_overlap(next_pos: Vector3, dt: float) -> Vector3:
	var my_px := Vector2(next_pos.x, next_pos.z)
	var my_r  := _ai_collision_radius_px()

	# Quick spatial filter (cheap AABB before sqrt)
	var racers := get_tree().get_nodes_in_group("racers")
	for n in racers:
		if n == self: continue
		if not is_instance_valid(n): continue
		if not n.has_method("ReturnMapPosition"): continue

		var p3: Vector3 = n.ReturnMapPosition()
		var other_px := Vector2(p3.x, p3.z)
		# If the other racer reports UV (|value| <= 2), convert to pixels
		if abs(p3.x) <= 2.0 and abs(p3.z) <= 2.0:
			other_px *= _pos_scale_px()

		# other radius (prefer per-entity; otherwise small fallback)
		var orad := my_r
		if n.has_method("ReturnCollisionRadiusUV"):
			var ruv := float(n.call("ReturnCollisionRadiusUV"))
			orad = max(0.0, ruv * _pos_scale_px())
		else:
			var s = null
			if n.has_method("ReturnSpriteGraphic"):
				s = n.call("ReturnSpriteGraphic")
			if s != null and "region_rect" in s and s.region_rect.size.y > 0.0:
				orad = max(0.0, s.region_rect.size.y * 0.20)

		# broad-phase AABB padding (smaller)
		var pad := my_r + orad + 2.0    # <= was +8.0

		if abs(other_px.x - my_px.x) > pad or abs(other_px.y - my_px.y) > pad:
			continue

		# narrow-phase circle
		var d := other_px - my_px
		var L := d.length()
		if L <= 0.0001:
			d = Vector2(1, 0); L = 0.0001
		var need := my_r + orad
		if L < need:
			var nrm := d / L
			var overlap := need - L

			# push *me* back half the overlap; the other will do its half in its own step
			my_px -= nrm * (overlap * 0.5)

			# give both a visible shove (px/s scaled by overlap)
			var mag := (overlap * 18.0)  # tune feel
			SetCollisionBump(Vector3(-nrm.x, 0.0, -nrm.y) * mag)
			if n.has_method("SetCollisionBump"):
				n.call("SetCollisionBump", Vector3(nrm.x, 0.0, nrm.y) * mag)

			# lane nudge for the AI we touched (nice readability)
			if n.has_method("OnBumped"):
				n.call("OnBumped", self, mag, overlap / _pos_scale_px())
			if has_method("OnBumped"):
				OnBumped(n, mag, overlap / _pos_scale_px())

			_bprint("%s vs %s OVERLAP  uv=%.5f  L=%.2f  need=%.2f"
				% [_bname(self), _bname(n), (need - L) / _pos_scale_px(), L, need])
				
	return Vector3(my_px.x, next_pos.y, my_px.y)

func _ensure_speed_tag() -> void:
	if not show_speed_tag:
		if _speed_tag and is_instance_valid(_speed_tag):
			_speed_tag.queue_free()
			_speed_tag = null
		return

	if _speed_tag == null:
		_speed_tag = Label.new()
		_speed_tag.top_level = true                    # independent screen-space pos
		_speed_tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_speed_tag.z_as_relative = false
		_speed_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		add_child(_speed_tag)

		# theme overrides
		if speed_tag_font:
			_speed_tag.add_theme_font_override("font", speed_tag_font)
		if speed_tag_font_size > 0:
			_speed_tag.add_theme_font_size_override("font_size", speed_tag_font_size)
		_speed_tag.add_theme_color_override("font_color", speed_tag_color)
		_speed_tag.add_theme_color_override("font_outline_color", speed_tag_outline_color)
		_speed_tag.add_theme_constant_override("outline_size", 2)

func _update_speed_tag() -> void:
	_ensure_speed_tag()
	if _speed_tag == null:
		return

	var spr := ReturnSpriteGraphic()
	if spr == null:
		_speed_tag.visible = false
		return

	# speed text
	var v := _movementSpeed
	var mult := 1.0
	var unit := ""
	match speed_tag_units:
		1:
			mult = 3.6    # px/s → “km/h” (if your px == meters; tweak if not)
			unit = ""     # keep it clean: just the number
		2:
			mult = 2.23693629   # px/s → mph (same note as above)
			unit = ""
	var val := v * mult
	var txt: String
	if speed_tag_round:
		txt = str(int(round(val)))
	else:
		txt = String.num(val, 1)
		
	_speed_tag.text = txt + unit

	# position above sprite
	var h := 34.0
	if "region_rect" in spr and spr.region_rect.size.y > 0.0:
		h = spr.region_rect.size.y
	var sc := (spr as Node2D).global_scale.y
	var pos := (spr as Node2D).global_position + Vector2(0, -(h + speed_tag_offset_px) * sc)

	_speed_tag.global_position = pos
	_speed_tag.z_index = spr.z_index + 1
	_speed_tag.visible = spr.visible

func AI_CanNitro() -> bool:
	return _nitro_charge >= AI_NITRO_MIN_FRAC

func AI_SetNitroLatch(on: bool) -> void:
	_nitro_latched = on

func AI_IsNitroActive() -> bool:
	return _nitro_timer > 0.0

func _ai_straight_ahead_len(s_px: float) -> float:
	var total := 0.0
	var step := 24.0
	var last := _tangent_at_distance(s_px)
	while total < AI_NITRO_LOOKAHEAD_PX:
		var t := _tangent_at_distance(s_px + total)
		if last.dot(t) < AI_NITRO_DOT:   # bent too much → stop
			break
		total += step
		last = t
	return total

func _ai_tick_nitro(dt: float) -> void:
	# cooldown tick
	_nitro_cd = max(0.0, _nitro_cd - dt)

	# simple surface check: prefer ROAD (don’t waste nitro off-road)
	var pos_px_i := _pos_px_from_mappos(ReturnMapPosition())
	var rt_cur := Globals.RoadType.ROAD
	if _has_collision_api():
		rt_cur = _collisionHandler.ReturnCurrentRoadType(pos_px_i)
	var on_good_surface = (rt_cur == Globals.RoadType.ROAD)

	# --- NEW: require FULL gauge before considering nitro ---
	var full_ready := (_nitro_charge >= 0.999)

	# Decide whether to latch nitro ON this frame
	if _nitro_timer <= 0.0 and _nitro_cd <= 0.0 and on_good_surface and full_ready:
		var straight_px := _ai_straight_ahead_len(_s_px)
		# scale runway requirement a bit with speed (faster -> need more)
		var need = AI_NITRO_MIN_STRAIGHT_PX + clamp(_movementSpeed * 0.6, 0.0, 240.0)
		if straight_px >= need:
			_nitro_latched = true

	# Drain / refill and set visuals
	var drain = 1.0 / max(0.001, AI_NITRO_CAPACITY_S)
	var refill = 1.0 / max(0.001, AI_NITRO_REFILL_S)

	if _nitro_latched and _nitro_charge > 0.0:
		_nitro_charge = max(0.0, _nitro_charge - drain * dt)
		_nitro_timer = 1.0   # ON for shader this frame
		# auto-drop when we run out
		if _nitro_charge <= 0.0:
			_nitro_latched = false
			_nitro_cd = AI_NITRO_COOLDOWN_S
	else:
		_nitro_timer = 0.0
		_nitro_latched = false
		_nitro_charge = min(1.0, _nitro_charge + refill * dt)

	# --- OUTPUT boost multiplier (per frame) ---
	var out_mult := 1.0
	if _nitro_timer > 0.0:
		out_mult = max(out_mult, AI_NITRO_MULT)
	SetOutputSpeedMultiplier(out_mult)

func SetCollisionHandler(node: Node) -> void:
	_collisionHandler = node

func _has_collision_api() -> bool:
	return _collisionHandler != null \
		and _collisionHandler.has_method("IsCollidingWithWall") \
		and _collisionHandler.has_method("ReturnCurrentRoadType")

func ReturnIsDrifting() -> bool:
	return _is_drifting

func _ensure_wheel_anchors() -> void:
	var rte := get_node_or_null(^"Road Type Effects")
	if rte == null:
		rte = Node2D.new()
		rte.name = "Road Type Effects"
		add_child(rte)
	if rte.get_node_or_null("LeftWheel") == null:
		var lw := Node2D.new()
		lw.name = "LeftWheel"
		lw.position = Vector2(-26, 20)  # tweak later to match sprite
		rte.add_child(lw)
	if rte.get_node_or_null("RightWheel") == null:
		var rw := Node2D.new()
		rw.name = "RightWheel"
		rw.position = Vector2(26, 20)
		rte.add_child(rw)

func _ensure_skid_painter_for_me() -> void:
	# If somehow called too early, reschedule
	if get_tree() == null:
		call_deferred("_ensure_skid_painter_for_me")
		return

	# Pick a parent for the painter
	var parent: Node = null
	if skid_parent_path != NodePath():
		parent = get_node_or_null(skid_parent_path)

	# Fallback: search for a SubViewport in the current scene
	if parent == null:
		var root := get_tree().get_root()
		parent = root.find_child("SubViewport", true, false)  # adjust the name to your overlay if needed

	if parent == null:
		push_warning("Skids: SubViewport not found; cannot attach painter.")
		return

	# Unique name per opponent to avoid clashes (instance_id keeps it unique)
	var node_name := "Skids_%s_%d" % [name, get_instance_id()]
	if parent.get_node_or_null(node_name) != null:
		return  # already attached

	# Create painter
	var script := load("res://Scripts/SkidMarkPainter2D.gd")
	if script == null:
		push_warning("Skids: painter script missing.")
		return

	var painter := Node2D.new()
	painter.name = node_name
	painter.set_script(script)
	parent.add_child(painter)

	# Wire dependencies
	var p3d := _p3d_node()
	if p3d == null:
		push_warning("Skids: pseudo3d_ref not set; painter may not draw.")
	else:
		painter.set("pseudo3d_path", painter.get_path_to(p3d))
	painter.set("player_path", painter.get_path_to(self))  # if your script expects a different prop name, change it

	# Defaults
	painter.set("width_px", 0.6)
	painter.set("min_segment_px", 1.0)
	painter.set("draw_while_drifting", true)
	painter.set("draw_while_offroad", true)

	# Sanity log
	var lw := get_node_or_null(^"Road Type Effects/LeftWheel")
	var rw := get_node_or_null(^"Road Type Effects/RightWheel")
	prints("[Skids] Attached painter for", name, "LW?", lw != null, "RW?", rw != null)
