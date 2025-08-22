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
	var curv: float = acos(clamp(t0.dot(t1), -1.0, 1.0))
	var v_target: float = target_speed * lerp(1.0, speed_damper_on_curve, clamp(curv / 0.6, 0.0, 1.0))

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
	

# ---------------- visuals ----------------
@export var angle_offset_deg: float = 0.0
@export var clockwise: bool = true

func _update_angle_sprite() -> void:
	var sp := get_node_or_null(angle_sprite_path)
	if sp == null: return
	var p3d := _p3d()
	if p3d == null: return

	var cam_f: Vector2 = (p3d.call("get_camera_forward_map") as Vector2)
	var cam_yaw: float = atan2(cam_f.y, cam_f.x)

	var theta_cam: float = wrapf(_heading - cam_yaw, -PI, PI)
	var deg: float = rad_to_deg(theta_cam)
	deg = wrapf(deg + angle_offset_deg, 0.0, 360.0)
	if deg < 0.0: deg += 360.0
	if not clockwise: deg = 360.0 - deg

	var step: float = 360.0 / float(DIRECTIONS)
	var idx: int = int(floor((deg + step * 0.5) / step)) % DIRECTIONS

	if sp is Sprite2D:
		var s := sp as Sprite2D
		s.hframes = DIRECTIONS
		s.vframes = 1
		s.frame = idx
	elif sp.has_method("set_frame"):
		sp.frame = idx

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
