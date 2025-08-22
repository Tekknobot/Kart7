# Scripts/World Elements/Racers/Opponent.gd  (perf-tuned)
extends "res://Scripts/World Elements/Racers/Racer.gd"

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

# ---------------- lifecycle ----------------
func _ready() -> void:
	_try_cache_nodes()
	_cache_path()

	if ReturnSpriteGraphic() == null and has_node(^"GFX/AngleSprite"):
		sprite_graphic_path = ^"GFX/AngleSprite"

	if _uv_points.size() < 2:
		push_error("Opponent: path has < 2 points.")
		return

	_s_px = _arc_at_index(start_index) + max(0.0, start_offset_px)
	_s_px = fposmod(_s_px, _total_len_px)

	_heading = _tangent_angle_at_distance(_s_px)

	var uv: Vector2 = _uv_at_distance(_s_px)
	var px: Vector2 = uv * _pos_scale_px()
	SetMapPosition(Vector3(px.x, 0.0, px.y))

	# Ensure AI can actually reach higher speeds
	if _maxMovementSpeed < max_speed_override:
		_maxMovementSpeed = max_speed_override

func _process(delta: float) -> void:
	if _uv_points.is_empty():
		return

	# Lazy recache if nodes were freed
	_try_cache_nodes()

	# --- lookahead steering (cheap) ---
	var p_uv: Vector2 = _uv_at_distance(_s_px)
	var t_uv: Vector2 = _uv_at_distance(_s_px + lookahead_px)
	var to_t: Vector2 = t_uv - p_uv
	var to_t_len := to_t.length()
	if to_t_len > 0.00001:
		to_t /= to_t_len
	var desired_angle: float = atan2(to_t.y, to_t.x)

	var yaw_err: float = wrapf(desired_angle - _heading, -PI, PI) * steer_gain
	var yaw_step: float = clamp(yaw_err, -max_turn_rate * delta, max_turn_rate * delta)
	_heading = wrapf(_heading + yaw_step, -PI, PI)

	# --- curvature proxy (no acos) ---
	# Use dot of tangents as 0..1 sharpness, then map like before
	var t0: Vector2 = _tangent_at_distance(_s_px)
	var t1: Vector2 = _tangent_at_distance(_s_px + lookahead_px * 0.5)
	var dot_raw: float = clamp(t0.dot(t1), -1.0, 1.0)
	var curv_approx: float = 1.0 - max(dot_raw, -1.0)  # 0 (straight) .. ~2 (u-turn), but typically 0..1

	# --- base desired speed ---
	var desired_speed: float = target_speed

	# --- catch-up vs player ---
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

		var my_pos3: Vector3 = ReturnMapPosition()
		var pl_pos3: Vector3 = (pl.call("ReturnMapPosition") as Vector3)
		var fwd_gap: float = (Vector2(pl_pos3.x - my_pos3.x, pl_pos3.z - my_pos3.z)).dot(cam_f)

		if fwd_gap > catchup_deadzone_uv:
			var eff_gap: float = fwd_gap - catchup_deadzone_uv
			desired_speed += eff_gap * catchup_gain_speed

		var min_over: float = pl_speed * min_ratio_vs_player
		if desired_speed < min_over:
			desired_speed = min_over

	# --- curve damping (same shape, no acos)
	var curv_u: float = clamp(curv_approx / 0.6, 0.0, 1.0)
	var corner_mult: float = lerp(1.0, speed_damper_on_curve, curv_u)
	desired_speed *= corner_mult

	# --- clamp to AI max ---
	if desired_speed > _maxMovementSpeed:
		desired_speed = _maxMovementSpeed

	# accel/decel
	var v_target: float = desired_speed
	if _movementSpeed < v_target:
		_movementSpeed = min(v_target, _movementSpeed + accel * delta)
	else:
		_movementSpeed = max(v_target, _movementSpeed - accel * delta)

	# advance along path
	_s_px = fposmod(_s_px + _movementSpeed * delta, _total_len_px)

	# final lateral offset at NEW position
	var cur_uv: Vector2 = _uv_at_distance(_s_px)
	var tan: Vector2 = _tangent_at_distance(_s_px)
	var right: Vector2 = Vector2(-tan.y, tan.x) # already unit
	var final_uv: Vector2 = cur_uv + (lane_offset_px / _pos_scale_px()) * right

	# write pixels
	var final_px: Vector2 = final_uv * _pos_scale_px()
	SetMapPosition(Vector3(final_px.x, 0.0, final_px.y))

	# visuals (throttled)
	var f := Engine.get_process_frames()
	if visual_update_stride <= 1 or (f % visual_update_stride) == 0:
		_update_angle_sprite_fast()
		_update_depth_sort_fast()

	if debug_log_ai_sprite and (f % 60 == 0):
		var sp := ReturnSpriteGraphic()
		prints("AI sprite:", sp, " path:", str(get("sprite_graphic_path")))

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
	var cam_f: Vector2 = (p3d.call("get_camera_forward_map") as Vector2)
	var c_len := cam_f.length()
	if c_len > 0.00001:
		cam_f /= c_len

	var my_pos: Vector3 = ReturnMapPosition()
	var pl_pos: Vector3 = (pl.call("ReturnMapPosition") as Vector3)
	var depth: float = (Vector2(my_pos.x - pl_pos.x, my_pos.z - pl_pos.z)).dot(cam_f)
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

# Opponent.gd — match player scale when nearest (snap near, blend far)
func update_screen_transform(camera_pos: Vector2) -> void:
	# 1) Let the base (Racer.gd) place & base-scale first
	super(camera_pos)

	# 2) Need the player sprite
	var pl := _player()
	if pl == null or not (pl is Node2D):
		return

	# 3) Distance to player in UV (0..1 across map)
	var my3: Vector3 = ReturnMapPosition()
	var pl3: Vector3 = (pl.call("ReturnMapPosition") as Vector3)
	var d_uv := Vector2(my3.x, my3.z).distance_to(Vector2(pl3.x, pl3.z))

	# 4) Derive an automatic “near radius” from this sprite’s own footprint
	var spr := ReturnSpriteGraphic()
	var h_px := 32.0
	if spr != null and "region_rect" in spr and spr.region_rect.size.y > 0.0:
		h_px = spr.region_rect.size.y

	var tex_w: float = 1024.0
	if "_pseudo" in self and _pseudo != null:
		var p3d := _pseudo as Sprite2D
		if p3d != null and p3d.texture != null:
			tex_w = float(p3d.texture.get_size().x)

	var uv_footprint = h_px / max(tex_w, 1.0)
	var R = uv_footprint * 6.0      # auto near radius
	var snap_threshold = R * 0.6    # “nearest” -> snap exactly to player

	# 5) Target scale = snap if very close, else blend by distance
	var pl_sc := (pl as Node2D).scale.x
	var my_sc := scale.x
	var target: float
	if d_uv <= snap_threshold:
		target = pl_sc                           # exact match when nearest
	else:
		var w = R / (R + d_uv)                 # 0..1, near→1, far→0
		target = lerp(my_sc, pl_sc, clamp(w, 0.0, 1.0))

	# 6) Smooth: faster when close, gentler when far (no visible pops)
	var dt := get_process_delta_time()
	var near_hl := 0.04                        # snappier near
	var far_hl  := 0.10                        # softer far
	var hl = lerp(near_hl, far_hl, clamp(d_uv / (R * 2.0), 0.0, 1.0))
	var sm := _smooth_scalar(my_sc, target, dt, hl)

	scale = Vector2(sm, sm)
