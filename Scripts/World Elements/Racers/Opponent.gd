extends Node2D

# ---------- References ----------
@export var path_ref: NodePath                            # PathOverlay2D (inside SubViewport)
@export var pseudo3d_ref: NodePath                        # Pseudo3D Sprite2D
@export var angle_sprite_path: NodePath = ^"GFX/AngleSprite"
@export var gfx_path: NodePath = ^"GFX"                   # Sprite2D for kart graphic

# ---------- Start / Lane (pixels) ----------
@export var start_index: int = 0                          # unique vertex index (not the closing duplicate)
@export var start_offset_px: float = 0.0                  # extra distance along path (pixels)
@export var lane_offset: float = 16.0                     # lateral offset in pixels (+right, -left)

# ---------- AI (smooth, distance + lookahead) ----------
@export var target_speed: float = 110.0                   # px/sec
@export var accel: float = 180.0                          # px/sec^2
@export var max_turn_rate: float = 3.0                    # rad/sec
@export var lookahead_px: float = 120.0                   # steer toward this distance ahead (pixels)
@export var steer_gain: float = 1.0                       # steering sensitivity
@export var speed_damper_on_curve: float = 0.65           # 0..1 on strong curves

# ---------- Path UV -> Pixel calibration ----------
@export var use_transformed_uv: bool = true               # use get_path_points_uv_transformed()
@export var invert_uv_y: bool = true                      # flip V once (matches your Player spawn)
@export var swap_xy: bool = false
@export var invert_x: bool = false
@export var invert_y: bool = false

# ---------- Projection & sizing ----------
@export var enable_depth_scale: bool = false              # off for perfect bumper cohesion
@export var depth_size_k: float = 1.0                     # numerator for 1/z sizing
@export var depth_size_min: float = 0.6
@export var depth_size_max: float = 1.3

# ---------- Debug ----------
@export var debug_draw_uv_point: bool = false             # draw the exact UV point used on the overlay

# ---------- Runtime state ----------
var _speed: float = 0.0
var _heading: float = 0.0
var _s: float = 0.0                                       # distance along path (pixels)

var _overlay: Node = null
var _p3d: Node = null
var _ang: Node = null
var _gfx: Node = null
var _tex_w: float = 1024.0

# Path cached in PIXELS (x = map X px, y = map Z px)
var _path_pts: PackedVector2Array = PackedVector2Array()
var _path_tan: PackedVector2Array = PackedVector2Array()
var _path_len: PackedFloat32Array = PackedFloat32Array()  # cumulative lengths (open) in pixels
var _path_total: float = 0.0
var _path_ready: bool = false

# ==============================
# Lifecycle
# ==============================
func _ready() -> void:
	_overlay = get_node_or_null(path_ref)
	_p3d = get_node_or_null(pseudo3d_ref)
	_gfx = get_node_or_null(gfx_path)
	if angle_sprite_path != NodePath():
		_ang = get_node_or_null(angle_sprite_path)

	if _p3d is Sprite2D and (_p3d as Sprite2D).texture != null:
		_tex_w = float((_p3d as Sprite2D).texture.get_size().x)

	_build_path_from_overlay()
	_snap_to_path_start()
	_bottom_anchor_gfx()

func _process(_dt: float) -> void:
	_project_like_bumpers()
	_update_angle_sprite()

func _physics_process(delta: float) -> void:
	_follow_distance_lookahead(delta)

# ==============================
# Path build (UV -> PIXELS)
# ==============================
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

	var uv: PackedVector2Array = PackedVector2Array()
	if use_transformed_uv and _overlay.has_method("get_path_points_uv_transformed"):
		uv = _overlay.call("get_path_points_uv_transformed")
	elif _overlay.has_method("get_path_points_uv"):
		uv = _overlay.call("get_path_points_uv")
	if uv.size() < 2:
		return

	# UV → pixel points with calibration to match Player/Map pixels
	var pts: PackedVector2Array = PackedVector2Array()
	for u in uv:
		var v: Vector2 = u
		if invert_uv_y:
			v.y = 1.0 - v.y
		if swap_xy:
			v = Vector2(v.y, v.x)
		if invert_x:
			v.x = -v.x
		if invert_y:
			v.y = -v.y
		pts.append(v * _tex_w)  # (x_px, z_px)

	# remove duplicate closing vertex (first==last)
	if pts.size() >= 2:
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[pts.size() - 1]
		if a.distance_to(b) <= (1.0 / 1024.0):
			pts.remove_at(pts.size() - 1)
	if pts.size() < 2:
		return

	# tangents + cumulative length in pixels (open path for lens; wrap added to total)
	var tans: PackedVector2Array = PackedVector2Array()
	var lens: PackedFloat32Array = PackedFloat32Array()
	lens.resize(pts.size())
	lens[0] = 0.0
	var total_px: float = 0.0

	var i: int = 0
	while i < pts.size():
		var j: int = (i + 1) % pts.size()
		var seg: Vector2 = pts[j] - pts[i]
		var t: Vector2
		if seg.length() > 0.0:
			t = seg.normalized()
		else:
			t = Vector2.RIGHT
		tans.append(t)

		if i < pts.size() - 1:
			total_px += seg.length()
			lens[i + 1] = total_px
		i += 1

	# add wrap length to total (lens stays open)
	total_px += (pts[0] - pts[pts.size() - 1]).length()

	_path_pts = pts
	_path_tan = tans
	_path_len = lens
	_path_total = total_px
	_path_ready = true

# ==============================
# Distance (px) → point/tangent (px)
# ==============================
func _point_at_distance(s: float) -> Vector2:
	if not _path_ready or _path_pts.size() == 0:
		return Vector2.ZERO
	var ss: float = fposmod(s, _path_total)  # pixels
	var i: int = 0
	while i < _path_len.size() - 1 and _path_len[i + 1] < ss:
		i += 1

	var a_px: float = _path_len[i]
	var b_px: float
	if (i + 1) >= _path_len.size():
		var seg_wrap: Vector2 = _path_pts[0] - _path_pts[i]
		b_px = a_px + seg_wrap.length()
	else:
		b_px = _path_len[i + 1]

	var seg_len_px: float = b_px - a_px
	if seg_len_px < 0.0001:
		seg_len_px = 0.0001
	var t: float = (ss - a_px) / seg_len_px
	return _path_pts[i].lerp(_path_pts[(i + 1) % _path_pts.size()], t)

func _tangent_at_distance(s: float) -> Vector2:
	if not _path_ready or _path_pts.size() == 0:
		return Vector2.RIGHT
	var ss: float = fposmod(s, _path_total)
	var i: int = 0
	while i < _path_len.size() - 1 and _path_len[i + 1] < ss:
		i += 1
	return _path_tan[i]

# ==============================
# Spawn
# ==============================
func _snap_to_path_start() -> void:
	if not _path_ready:
		return
	var n: int = _path_pts.size()
	if n == 0:
		return

	var idx: int = start_index
	if idx < 0:
		idx = 0
	if idx >= n:
		idx = n - 1

	var base_s: float = 0.0
	if _path_len.size() > idx:
		base_s = _path_len[idx]
	_s = base_s + start_offset_px

# ==============================
# Map-space helpers (PIXELS)
# ==============================
func get_map_space_position() -> Vector2:
	var P: Vector2 = _point_at_distance(_s)  # (x_px, z_px)
	var T: Vector2 = _tangent_at_distance(_s)
	if T.length_squared() == 0.0:
		T = Vector2.RIGHT
	else:
		T = T.normalized()
	var N: Vector2 = Vector2(-T.y, T.x)
	return P + N * lane_offset

func get_kart_forward_map() -> Vector2:
	var T: Vector2 = _tangent_at_distance(_s)
	if T.length_squared() == 0.0:
		return Vector2.RIGHT
	return T.normalized()

# ==============================
# Projection (BUMPER-STYLE)
# ==============================
func _project_like_bumpers() -> void:
	if _p3d == null or not (_p3d is Sprite2D):
		return

	# 1) Map pixels (x,z) → screen via worldMatrix inverse (exactly like SpriteHandler)
	var mp: Vector2 = get_map_space_position()
	var inv: Basis = (_p3d as Sprite2D).get("mapMatrixInv") if false else _p3d.call("ReturnWorldMatrix").inverse()
	# Using ReturnWorldMatrix().inverse() to mirror SpriteHandler logic
	var w: Vector3 = inv * Vector3(mp.x, mp.y, 1.0)

	var z: float = w.z
	if z <= 0.0001:
		visible = false
		return
	visible = true

	var scr: Vector2 = Vector2(w.x / z, w.y / z)
	scr = (scr + Vector2(0.5, 0.5)) * Globals.screenSize

	# 2) Optional depth sizing (off by default for cohesion)
	var sc: float = 1.0
	if enable_depth_scale:
		var zabs: float = z
		if zabs < 0.0001:
			zabs = 0.0001
		sc = depth_size_k / zabs
		if sc < depth_size_min:
			sc = depth_size_min
		if sc > depth_size_max:
			sc = depth_size_max

	# 3) Bottom-anchor (subtract half sprite height * scale)
	var anchor_px: float = 0.0
	if _gfx is Sprite2D:
		var spr: Sprite2D = _gfx as Sprite2D
		var sprite_h: float = 0.0
		if spr.region_enabled:
			sprite_h = spr.region_rect.size.y
		elif spr.texture != null:
			sprite_h = float(spr.texture.get_height())
		anchor_px = (sprite_h * sc) * 0.5
	scr.y -= anchor_px

	# 4) Apply
	global_position = scr
	if _gfx is Sprite2D:
		(_gfx as Sprite2D).scale = Vector2.ONE * sc
	else:
		scale = Vector2.ONE * sc

	# 5) Sort like bumpers (by Y)
	z_index = int(global_position.y)

	# 6) Debug overlay marker
	if debug_draw_uv_point:
		_debug_mark_overlay_point_px(mp)

func _bottom_anchor_gfx() -> void:
	if _gfx is Sprite2D:
		var spr: Sprite2D = _gfx as Sprite2D
		spr.centered = true
		spr.region_enabled = true
		var h: float = 0.0
		if spr.region_enabled:
			h = spr.region_rect.size.y
		elif spr.texture != null:
			h = float(spr.texture.get_height())
		spr.offset = Vector2(0.0, h * 0.5)

# ==============================
# Angle sprite (kart tangent vs. map yaw)
# ==============================
func _update_angle_sprite() -> void:
	if _ang == null or _p3d == null:
		return
	var f3: Vector3 = _p3d.call("ReturnForward")      # (sin(yaw), 0, cos(yaw))
	var cam_f: Vector2 = Vector2(f3.x, f3.z).normalized()
	var kart_f: Vector2 = get_kart_forward_map()

	if _ang.has_method("set_camera_forward"):
		_ang.call("set_camera_forward", cam_f)
	if _ang.has_method("set_kart_forward"):
		_ang.call("set_kart_forward", kart_f)
	if _ang.has_method("update_from_relative_angle"):
		_ang.call("update_from_relative_angle")

# ==============================
# Smooth follower (distance + lookahead, no waypoint snaps)
# ==============================
func _follow_distance_lookahead(delta: float) -> void:
	if not _path_ready or _path_total <= 0.0:
		return

	# current and ahead targets (both include lane offset at their s)
	var pos_now: Vector2 = get_map_space_position()

	var s_ahead: float = _s + lookahead_px
	var P_ahead_center: Vector2 = _point_at_distance(s_ahead)
	var T_ahead: Vector2 = _tangent_at_distance(s_ahead)
	if T_ahead.length_squared() == 0.0:
		T_ahead = Vector2.RIGHT
	else:
		T_ahead = T_ahead.normalized()
	var N_ahead: Vector2 = Vector2(-T_ahead.y, T_ahead.x)
	var P_ahead: Vector2 = P_ahead_center + N_ahead * lane_offset

	# steer toward lookahead
	var to_ahead: Vector2 = P_ahead - pos_now
	var desired_h: float = to_ahead.angle()
	var steer: float = wrapf(desired_h - _heading, -PI, PI) * steer_gain
	_heading += clamp(steer, -max_turn_rate * delta, max_turn_rate * delta)

	# curve-aware speed cap (using tangent similarity)
	var T_now: Vector2 = get_kart_forward_map()
	var dotv: float = clamp(abs(T_now.dot(T_ahead)), 0.0, 1.0)   # 1 = straight, 0 = sharp
	var curve: float = 1.0 - dotv
	var speed_cap: float = lerp(target_speed * speed_damper_on_curve, target_speed, 1.0 - curve)

	_speed = move_toward(_speed, speed_cap, accel * delta)
	_s = fposmod(_s + _speed * delta, _path_total)

# ==============================
# Debug helper: mark UV from PIXELS
# ==============================
func _debug_mark_overlay_point_px(mp_px: Vector2) -> void:
	if not debug_draw_uv_point:
		return
	if _overlay == null:
		return
	if not (_p3d is Sprite2D):
		return
	var tex: Texture2D = (_p3d as Sprite2D).texture
	if tex == null:
		return

	var uv: Vector2 = mp_px / _tex_w
	# undo calibration (reverse order of application)
	if invert_y:
		uv.y = -uv.y
	if invert_x:
		uv.x = -uv.x
	if swap_xy:
		uv = Vector2(uv.y, uv.x)
	if invert_uv_y:
		uv.y = 1.0 - uv.y

	uv.x = clamp(uv.x, 0.0, 1.0)
	uv.y = clamp(uv.y, 0.0, 1.0)

	if _overlay.has_method("clear_debug_markers"):
		_overlay.call("clear_debug_markers")
	if _overlay.has_method("add_debug_marker_uv"):
		_overlay.call("add_debug_marker_uv", uv)
