extends Node2D

# ----------------- References -----------------
@export var path_ref: NodePath              # PathOverlay2D (in SubViewport)
@export var pseudo3d_ref: NodePath          # Pseudo3D Sprite2D
@export var angle_sprite_path: NodePath = ^"GFX/AngleSprite"

# ----------------- Start / Lane -----------------
@export var start_index: int = 0            # which path vertex to spawn on (unique index, not the last duplicate)
@export var start_offset_px: float = 0.0    # extra distance along path in pixels
@export var lane_offset: float = 22.0       # lateral offset in pixels (+right, -left)

# ----------------- AI tuning -----------------
@export var target_speed: float = 110.0     # px/sec
@export var accel: float = 180.0            # px/sec^2
@export var max_turn_rate: float = 3.0      # rad/sec
@export var waypoint_advance_dist: float = 24.0
@export var curvature_slowdown: float = 0.6

# ----------------- Projection tuning (SNES-ish) -----------------
@export var horizon_y: float = 120.0
@export var focal: float = 420.0
@export var min_depth: float = 12.0

# ----------------- Runtime state -----------------
var _speed: float = 0.0
var _heading: float = 0.0
var _s: float = 0.0
var _wp_idx: int = 0

# cached nodes
var _overlay = null
var _p3d = null
var _ang = null

# ----------------- Path cache (built from overlay UVs) -----------------
var _path_pts: PackedVector2Array = PackedVector2Array()    # pixel positions on map (x,z -> x,y)
var _path_tan: PackedVector2Array = PackedVector2Array()
var _path_len: PackedFloat32Array = PackedFloat32Array()    # cumulative length to i (open)
var _path_total: float = 0.0
var _path_ready: bool = false

# ----------------- Utilities -----------------
func _ready() -> void:
	_overlay = get_node_or_null(path_ref)
	_p3d = get_node_or_null(pseudo3d_ref)
	if angle_sprite_path != NodePath():
		_ang = get_node_or_null(angle_sprite_path)
	_build_path_from_overlay()
	_snap_to_path_start()

func _process(_dt: float) -> void:
	var cam_pos := Globals.get_camera_map_position()
	_project_to_screen(cam_pos)
	_update_angle_sprite()

func _physics_process(delta: float) -> void:
	_follow_tick(delta)

# ----------------- Build path from overlay (UV -> pixels) -----------------
func _build_path_from_overlay() -> void:
	_path_ready = false
	_path_pts = PackedVector2Array()
	_path_tan = PackedVector2Array()
	_path_len = PackedFloat32Array()
	_path_total = 0.0

	if _overlay == null or _p3d == null:
		return
	if not (_p3d is Sprite2D):
		return
	var tex: Texture2D = (_p3d as Sprite2D).texture
	if tex == null:
		return
	var tex_w := float(tex.get_size().x)

	var uv: PackedVector2Array = PackedVector2Array()
	if _overlay.has_method("get_path_points_uv_transformed"):
		uv = _overlay.call("get_path_points_uv_transformed")
	elif _overlay.has_method("get_path_points_uv"):
		uv = _overlay.call("get_path_points_uv")
	if uv.size() < 2:
		return

	# UV -> map pixels (flip Y once to match map space)
	var pts := PackedVector2Array()
	for u in uv:
		var v := Vector2(u.x, 1.0 - u.y)
		pts.append(v * tex_w)

	# remove duplicate closing vertex (first==last)
	if pts.size() >= 2:
		var a := pts[0]
		var b := pts[pts.size() - 1]
		if a.distance_to(b) <= (1.0 / 1024.0):
			pts.remove_at(pts.size() - 1)
	if pts.size() < 2:
		return

	# tangents + cumulative length
	var tans := PackedVector2Array()
	var lens := PackedFloat32Array()
	lens.resize(pts.size())
	lens[0] = 0.0
	var total := 0.0
	for i in range(pts.size()):
		var j := (i + 1) % pts.size()
		var seg := pts[j] - pts[i]
		var t := seg
		if t.length_squared() > 0.0:
			t = t.normalized()
		else:
			t = Vector2.RIGHT
		tans.append(t)
		if i < pts.size() - 1:
			total += seg.length()
			lens[i + 1] = total
	# close loop length
	total += (pts[0] - pts[pts.size() - 1]).length()

	_path_pts = pts
	_path_tan = tans
	_path_len = lens
	_path_total = total
	_path_ready = true

func _point_count() -> int:
	if not _path_ready: return 0
	return _path_pts.size()

func _point_at_index(i: int) -> Vector2:
	if not _path_ready or _path_pts.size() == 0:
		return Vector2.ZERO
	var n := _path_pts.size()
	var k := i % n
	if k < 0:
		k += n
	return _path_pts[k]

func _tangent_at_index(i: int) -> Vector2:
	if not _path_ready or _path_tan.size() == 0:
		return Vector2.RIGHT
	var n := _path_tan.size()
	var k := i % n
	if k < 0:
		k += n
	return _path_tan[k]

func _point_at_distance(s: float) -> Vector2:
	if not _path_ready:
		return Vector2.ZERO
	var n := _path_pts.size()
	if n == 0:
		return Vector2.ZERO
	var ss := fposmod(s, _path_total)
	var i := 0
	while i < _path_len.size() - 1 and _path_len[i + 1] < ss:
		i += 1
	var a := _path_len[i]
	var b := _path_len[i + 1] if (i + 1) < _path_len.size() else _path_total
	var denom := b - a
	if denom < 0.0001:
		denom = 0.0001
	var t := (ss - a) / denom
	var p0 := _path_pts[i]
	var p1 := _path_pts[(i + 1) % n]
	return p0.lerp(p1, t)

func _tangent_at_distance(s: float) -> Vector2:
	if not _path_ready:
		return Vector2.RIGHT
	var n := _path_pts.size()
	if n == 0:
		return Vector2.RIGHT
	var ss := fposmod(s, _path_total)
	var i := 0
	while i < _path_len.size() - 1 and _path_len[i + 1] < ss:
		i += 1
	return _tangent_at_index(i)

# ----------------- Spawn / start -----------------
func _snap_to_path_start() -> void:
	if not _path_ready:
		return
	var n := _point_count()
	if n == 0:
		return
	var idx := start_index
	if idx < 0:
		idx = 0
	if idx >= n:
		idx = n - 1
	_wp_idx = idx

	var base_s := 0.0
	if _path_len.size() > idx:
		base_s = _path_len[idx]
	_s = base_s + start_offset_px

# ----------------- Map-space helpers -----------------
func get_map_space_position() -> Vector2:
	var P: Vector2 = _point_at_distance(_s)
	var T: Vector2 = _tangent_at_distance(_s)
	if T.length_squared() == 0.0:
		T = Vector2.RIGHT
	else:
		T = T.normalized()
	var N: Vector2 = Vector2(-T.y, T.x) # left normal
	return P + N * lane_offset

func get_kart_forward_map() -> Vector2:
	var T: Vector2 = _tangent_at_distance(_s)
	if T.length_squared() == 0.0:
		return Vector2.RIGHT
	return T.normalized()

# ----------------- Projection (pseudo-3D) -----------------
func _camera_basis(cam_f: Vector2) -> Dictionary:
	var f := cam_f.normalized()
	var r := Vector2(f.y, -f.x)   # camera right
	var out: Dictionary = {}
	out["f"] = f
	out["r"] = r
	return out

func _camera_components(camera_pos: Vector2, basis: Dictionary, world: Vector2) -> Dictionary:
	var cam_to := world - camera_pos
	var depth := cam_to.dot(basis["f"])     # forward (z-like)
	var lateral := cam_to.dot(basis["r"])   # right (x-like)
	var out: Dictionary = {}
	out["depth"] = depth
	out["lateral"] = lateral
	return out

func _project_to_screen(camera_pos: Vector2) -> void:
	if _p3d == null:
		return
	var cam_f: Vector2 = _p3d.get_camera_forward_map()
	var basis := _camera_basis(cam_f)

	var world: Vector2 = get_map_space_position()
	var comps := _camera_components(camera_pos, basis, world)

	var depth_val := float(comps["depth"])
	if depth_val < min_depth:
		depth_val = min_depth

	var lateral_val := float(comps["lateral"])
	var x_ndc := (lateral_val * focal) / depth_val
	var y_ndc := horizon_y + (focal / depth_val)

	var sc = _p3d.depth_scale(float(comps["depth"]))

	global_position = _p3d.global_position + Vector2(x_ndc, y_ndc)
	scale = Vector2.ONE * sc
	z_index = int(100000.0 - float(comps["depth"]))
	visible = (float(comps["depth"]) > 0.0)

# ----------------- Angle sprite -----------------
func _update_angle_sprite() -> void:
	if _ang == null or _p3d == null:
		return
	if _ang.has_method("set_camera_forward"):
		_ang.call("set_camera_forward", _p3d.get_camera_forward_map())
	if _ang.has_method("set_kart_forward"):
		_ang.call("set_kart_forward", get_kart_forward_map())
	if _ang.has_method("update_from_relative_angle"):
		_ang.call("update_from_relative_angle")

# ----------------- AI follow tick -----------------
func _follow_tick(delta: float) -> void:
	if not _path_ready:
		return

	var n := _point_count()
	if n == 0:
		return

	# steer toward current waypoint
	var P: Vector2 = _point_at_index(_wp_idx)
	var next_idx: int = (_wp_idx + 1) % n
	var N: Vector2 = _point_at_index(next_idx)

	var to_target: Vector2 = P - get_map_space_position()
	var desired_h: float = to_target.angle()
	var steer: float = wrapf(desired_h - _heading, -PI, PI)
	_heading += clamp(steer, -max_turn_rate * delta, max_turn_rate * delta)

	# curvature-based speed cap
	var T0: Vector2 = (N - P).normalized()
	var T1: Vector2 = _tangent_at_index(_wp_idx).normalized()
	var dotv: float = clamp(T0.dot(T1), -1.0, 1.0)
	var curv: float = abs(acos(dotv))

	var factor: float = 1.0 - curv
	if factor < 0.0:
		factor = 0.0
	if factor > 1.0:
		factor = 1.0
	var speed_cap: float = lerp(target_speed * curvature_slowdown, target_speed, factor)

	_speed = move_toward(_speed, speed_cap, accel * delta)
	_s += _speed * delta

	if to_target.length() <= waypoint_advance_dist:
		_wp_idx = next_idx
