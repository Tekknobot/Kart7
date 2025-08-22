# Scripts/World Elements/Racers/Opponent.gd
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

# Internals unique to Opponent (NOT in Racer.gd)
var _cum_len_px: PackedFloat32Array = PackedFloat32Array()
var _total_len_px: float = 0.0
var _s_px: float = 0.0

# ---------------- visuals ----------------
@export var angle_offset_deg: float = 0.0
@export var clockwise: bool = true
@export var frame0_is_front: bool = true  # set true if atlas frame 0 is a FRONT view

# --- speed tuning (add under your existing AI exports) ---
@export var max_speed_override: float = 320.0      # hard cap just for AI
@export var catchup_gain_speed: float = 380.0      # speed added per 1.0 UV of forward gap
@export var catchup_deadzone_uv: float = 0.02      # ignore tiny gaps
@export var min_ratio_vs_player: float = 1.05      # always at least 5% faster than player


# --- convenience accessors to inherited exports ---
func _path_node() -> Node:
	return get_node_or_null(path_ref)        # path_ref is inherited from Racer.gd

func _p3d() -> Node:
	return get_node_or_null(pseudo3d_ref)    # pseudo3d_ref is inherited from Racer.gd

func _player() -> Node:
	return get_node_or_null(player_ref)

# ---------------- lifecycle ----------------
func _ready() -> void:
	_cache_path()
	
	if ReturnSpriteGraphic() == null:
		if has_node(^"GFX/AngleSprite"):
			sprite_graphic_path = ^"GFX/AngleSprite"  # WorldElement export
				
	if _uv_points.size() < 2:
		push_error("Opponent: path has < 2 points.")
		return

	_s_px = _arc_at_index(start_index) + max(0.0, start_offset_px)
	_s_px = fposmod(_s_px, _total_len_px)

	_heading = _tangent_angle_at_distance(_s_px)

	var uv: Vector2 = _uv_at_distance(_s_px)       # 0..1 along the path
	var px: Vector2 = uv * _pos_scale_px()         # convert to pixels (e.g., * 1024)
	SetMapPosition(Vector3(px.x, 0.0, px.y))       # <-- pixels into SetMapPosition

	# Ensure AI can actually reach higher speeds
	if _maxMovementSpeed < max_speed_override:
		_maxMovementSpeed = max_speed_override
		
func _process(delta: float) -> void:
	if _uv_points.is_empty():
		return

	var p_uv: Vector2 = _uv_at_distance(_s_px)
	var t_uv: Vector2 = _uv_at_distance(_s_px + lookahead_px)
	var to_t: Vector2 = (t_uv - p_uv).normalized()
	var desired: float = atan2(to_t.y, to_t.x)

	var yaw_err: float = wrapf(desired - _heading, -PI, PI) * steer_gain
	var yaw_step: float = clamp(yaw_err, -max_turn_rate * delta, max_turn_rate * delta)
	_heading = wrapf(_heading + yaw_step, -PI, PI)

	var t0: Vector2 = _tangent_at_distance(_s_px)
	var t1: Vector2 = _tangent_at_distance(_s_px + lookahead_px * 0.5)
	var dot_raw: float = t0.dot(t1)
	if dot_raw < -1.0:
		dot_raw = -1.0
	if dot_raw > 1.0:
		dot_raw = 1.0
	var curv: float = acos(dot_raw)

	# --- base desired speed ---
	desired = target_speed

	# --- catch-up towards player along camera-forward ---
	var pl := _player()
	if pl != null:
		var pl_speed: float = 0.0
		if pl.has_method("ReturnMovementSpeed"):
			pl_speed = float(pl.call("ReturnMovementSpeed"))

		# camera forward
		var p3d := _p3d()
		var cam_f: Vector2 = Vector2(0, 1)
		if p3d != null and p3d.has_method("get_camera_forward_map"):
			cam_f = (p3d.call("get_camera_forward_map") as Vector2).normalized()

		# Signed forward gap (player ahead => positive)
		var my_pos3: Vector3 = ReturnMapPosition()
		var pl_pos3: Vector3 = (pl.call("ReturnMapPosition") as Vector3)
		var my_uv: Vector2 = Vector2(my_pos3.x, my_pos3.z)
		var pl_uv: Vector2 = Vector2(pl_pos3.x, pl_pos3.z)
		var fwd_gap: float = (pl_uv - my_uv).dot(cam_f)

		# ignore tiny gaps
		if fwd_gap > catchup_deadzone_uv:
			var eff_gap: float = fwd_gap - catchup_deadzone_uv
			desired = desired + eff_gap * catchup_gain_speed

		# ensure a margin over the player's current speed
		var min_over: float = pl_speed * min_ratio_vs_player
		if desired < min_over:
			desired = min_over

	# --- curve damping (same shape as before) ---
	var curv_u: float = curv / 0.6
	if curv_u < 0.0:
		curv_u = 0.0
	if curv_u > 1.0:
		curv_u = 1.0
	var corner_mult: float = lerp(1.0, speed_damper_on_curve, curv_u)
	desired = desired * corner_mult

	# --- clamp to AI max ---
	if desired > _maxMovementSpeed:
		desired = _maxMovementSpeed

	# hand off to your existing accel/decel code by aliasing v_target
	var v_target: float = desired


	if _movementSpeed < v_target:
		_movementSpeed = min(v_target, _movementSpeed + accel * delta)
	else:
		_movementSpeed = max(v_target, _movementSpeed - accel * delta)

	_s_px = fposmod(_s_px + _movementSpeed * delta, _total_len_px)

	# tangent/right in UV, lane offset in pixels → convert to UV then add
	var tan: Vector2 = _tangent_at_distance(_s_px)
	var right: Vector2 = Vector2(-tan.y, tan.x)
	var final_uv: Vector2 = p_uv + (lane_offset_px / _pos_scale_px()) * right

	# write PIXELS to SetMapPosition
	var final_px: Vector2 = final_uv * _pos_scale_px()
	SetMapPosition(Vector3(final_px.x, 0.0, final_px.y))

	_update_angle_sprite()
	_update_depth_sort()
	
	if Engine.get_process_frames() % 30 == 0:
		var sp := ReturnSpriteGraphic()
		prints("AI sprite:", sp, " path:", str(get("sprite_graphic_path")))

# Assumes: const DIRECTIONS := 12 (12 right-side frames laid out in one row)
# The sheet is a HALF-CIRCLE (right side only). We mirror with flip_h for the left side.
func _update_angle_sprite() -> void:
	var sp := get_node_or_null(angle_sprite_path)
	if sp == null:
		return
	var p3d := _p3d()
	if p3d == null:
		return

	# Camera yaw in map space
	var cam_f: Vector2 = (p3d.call("get_camera_forward_map") as Vector2)
	var cam_yaw: float = atan2(cam_f.y, cam_f.x)

	# Signed bearing (kart heading relative to camera), degrees in [-180, 180)
	var theta_cam: float = wrapf(_heading - cam_yaw, -PI, PI)
	var deg: float = rad_to_deg(theta_cam)

	# Apply atlas offset and handedness
	deg = wrapf(deg + angle_offset_deg, -180.0, 180.0)
	if not clockwise:
		deg = -deg

	# We only have RIGHT-side art; mirror for LEFT with flip_h.
	# Define: Right side => deg < 0 ; Left side => deg > 0
	var left_side := deg > 0.0

	# Map absolute bearing [0..180] to 12 frames (0 = aligned-with-camera, 180 = facing camera)
	var absdeg: float = clamp(abs(deg), 0.0, 179.999)
	var step: float = 180.0 / float(DIRECTIONS)   # 15° per frame
	var idx: int = int(floor((absdeg + step * 0.5) / step))
	if idx >= DIRECTIONS:
		idx = DIRECTIONS - 1

	# --- FRONT/BACK ORIENTATION FIX ---
	# If your atlas frame 0 is a FRONT view, reverse the index so behind-you uses a BACK frame.
	# (This flips 0↔11, 1↔10, etc.)
	if frame0_is_front:
		idx = (DIRECTIONS - 1) - idx

	# Apply to the sprite
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

func _update_depth_sort() -> void:
	var p3d := _p3d()
	var pl := _player()
	if p3d == null or pl == null:
		return

	var cam_f: Vector2 = (p3d.call("get_camera_forward_map") as Vector2).normalized()

	var my_pos: Vector3 = ReturnMapPosition()
	var pl_pos: Vector3 = (pl.call("ReturnMapPosition") as Vector3)

	var my_uv: Vector2 = Vector2(my_pos.x, my_pos.z)
	var pl_uv: Vector2 = Vector2(pl_pos.x, pl_pos.z)

	var depth: float = (my_uv - pl_uv).dot(cam_f)
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
	_path_ready = false

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

	# --- ensure the path lives in true UV [0..1] ---
	var min_v := Vector2(1e30, 1e30)
	var max_v := Vector2(-1e30, -1e30)
	for p in _uv_points:
		if p.x < min_v.x: min_v.x = p.x
		if p.y < min_v.y: min_v.y = p.y
		if p.x > max_v.x: max_v.x = p.x
		if p.y > max_v.y: max_v.y = p.y
	var ext := max_v - min_v
	var scale_px := _pos_scale_px()

	# If extents look like pixels (>2), convert to UV by dividing once.
	if ext.x > 2.0 or ext.y > 2.0:
		for i in range(_uv_points.size()):
			_uv_points[i] /= scale_px
	# If extents look "micro-UV" (<0.01), multiply once (fix double division).
	elif ext.x < 0.01 and ext.y < 0.01:
		for i in range(_uv_points.size()):
			_uv_points[i] *= scale_px
	# else: already proper UV, do nothing.

	# Close the loop if needed
	if _uv_points[0] != _uv_points[_uv_points.size() - 1]:
		_uv_points.append(_uv_points[0])

	# Build cumulative length in **pixels** (UV * pos_scale_px)
	_path_len.resize(_uv_points.size())
	_path_len[0] = 0.0
	var total: float = 0.0
	for i in range(1, _uv_points.size()):
		var d_uv := _uv_points[i] - _uv_points[i - 1]
		var d_px := d_uv.length() * scale_px
		total += d_px
		_path_len[i] = total
	_total_len_px = total
	_cum_len_px = _path_len
	_path_ready = true

func _arc_at_index(i: int) -> float:
	if _path_len.is_empty(): return 0.0
	i = clamp(i, 0, _path_len.size() - 1)
	return _path_len[i]

func _uv_at_distance(s_px: float) -> Vector2:
	if _path_len.is_empty(): return Vector2.ZERO
	var s: float = fposmod(s_px, _total_len_px)
	var i: int = 0
	while i < _path_len.size() - 1 and _path_len[i + 1] < s:
		i += 1
	var a: Vector2 = _uv_points[i]
	var b: Vector2 = _uv_points[i + 1]
	var seg0: float = _path_len[i]
	var seg1: float = _path_len[i + 1]
	var t: float = (s - seg0) / max(seg1 - seg0, 0.0001)
	return a.lerp(b, t)

func _tangent_at_distance(s_px: float) -> Vector2:
	if _uv_points.size() < 2:
		return Vector2.RIGHT
	var p0: Vector2 = _uv_at_distance(s_px)
	var p1: Vector2 = _uv_at_distance(s_px + 1.0)
	var t: Vector2 = (p1 - p0)
	if t.length() > 0.0:
		return t.normalized()
	else:
		return Vector2.RIGHT

func _tangent_angle_at_distance(s_px: float) -> float:
	var t: Vector2 = _tangent_at_distance(s_px)
	return atan2(t.y, t.x)
