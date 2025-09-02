extends Node

@export var minimap_node: NodePath
@export var path_overlay_node: NodePath
@export var racers_group: String = "opponents"
@export var map_size_px: int = 1024
@export var rear_half_span_px: float = 26.0
@export var draw_when_drifting: bool = true
@export var draw_when_offroad: bool = false
@export var use_y_instead_of_z: bool = false  # set true if your track uses XY instead of XZ

@export var rear_axle_back_px: float = 18.0   # distance from kart center to rear axle (texture pixels)
@export var overlay_latency_frames: float = 1.0  # compensate 1 frame of lag by default
@export var fwd_half_life_s: float = 0.08     # smoothing for forward axis
@export var min_motion_uv_per_sec: float = 0.0005  # ignore tiny motion noise

var _minimap: Node = null
var _overlay: Node = null
var _uv_loop: PackedVector2Array = PackedVector2Array()
var _last_dt: float = 1.0 / 60.0

var _last_uv_by_id := {}      # id -> Vector2
var _fwd_smooth_by_id := {}   # id -> Vector2 (unit)

@export var orient_window_px: float = 48.0   # central-diff window (match DRIFT_SIGN_SAMPLE_PX)
var _path_ready: bool = false
var _seg_len_px: PackedFloat32Array = PackedFloat32Array()
var _cum_len_px: PackedFloat32Array = PackedFloat32Array()
var _total_len_px: float = 0.0

func _ready() -> void:
	if minimap_node != NodePath():
		_minimap = get_node(minimap_node)
	if path_overlay_node != NodePath():
		_overlay = get_node(path_overlay_node)

	if _minimap == null:
		print("SkidsFromMinimap: minimap_node NOT set")
	else:
		print("SkidsFromMinimap: minimap ok -> ", _minimap.name)

	if _overlay == null:
		print("SkidsFromMinimap: path_overlay_node NOT set")
	else:
		print("SkidsFromMinimap: overlay ok -> ", _overlay.name, " has mm_append_uv: ", _overlay.has_method("mm_append_uv"))

	print("SkidsFromMinimap: racers_group = ", racers_group)

func _process(delta: float) -> void:
	_last_dt = delta
	
	if _minimap == null:
		return
	if _overlay == null:
		return

	_uv_loop = _get_uv_loop_from_minimap()
	_ensure_path_metrics()
	var opponents := get_tree().get_nodes_in_group(racers_group)
	for r in opponents:
		_process_racer(r)

func _ensure_path_metrics() -> void:
	# Build per-segment lengths (in pixels), cumulative arc-length, and total length.
	_path_ready = false
	_seg_len_px = PackedFloat32Array()
	_cum_len_px = PackedFloat32Array()
	_total_len_px = 0.0

	var n := _uv_loop.size()
	if n < 2:
		return

	# Ensure closed loop (duplicate first at end if needed)
	var closed := false
	if _uv_loop[0].distance_to(_uv_loop[n - 1]) <= (1.0 / float(max(1, map_size_px))):
		closed = true

	var pts := _uv_loop
	if not closed:
		pts = _uv_loop.duplicate()
		pts.append(_uv_loop[0])
	n = pts.size()

	_seg_len_px.resize(max(0, n - 1))
	_cum_len_px.resize(n)
	_cum_len_px[0] = 0.0

	var acc := 0.0
	for i in range(n - 1):
		var d_uv := pts[i + 1] - pts[i]
		var seg_px := d_uv.length() * float(map_size_px)
		_seg_len_px[i] = seg_px
		acc += seg_px
		_cum_len_px[i + 1] = acc

	_total_len_px = acc
	_path_ready = (_total_len_px > 0.0)

func _wrap_s(s_px: float) -> float:
	if _total_len_px <= 0.0:
		return 0.0
	return fposmod(s_px, _total_len_px)

func _find_segment_for_s(s_px: float) -> int:
	# Binary search cum-length to find i with s in [cum[i], cum[i+1]]
	var lo := 0
	var hi := _cum_len_px.size() - 1
	while lo < hi - 1:
		var mid := (lo + hi) >> 1
		if _cum_len_px[mid] <= s_px:
			lo = mid
		else:
			hi = mid
	return lo

func _sample_uv_at_s(s_px: float) -> Vector2:
	if not _path_ready:
		return Vector2(0.5, 0.5)

	var s := _wrap_s(s_px)
	var i := _find_segment_for_s(s)

	var a: Vector2 = _uv_loop[i]
	var b: Vector2
	if (i + 1) < _uv_loop.size():
		b = _uv_loop[i + 1]
	else:
		b = _uv_loop[0]

	var seg0 := _cum_len_px[i]
	var seg1 := _cum_len_px[i + 1]
	var denom = max(seg1 - seg0, 0.0001)
	var t = (s - seg0) / denom
	return a.lerp(b, t)

func _project_uv_to_s(uv: Vector2) -> float:
	# Find nearest point on the polyline and return arc-length at that point.
	if not _path_ready:
		return 0.0
	var best_d2 := 1e30
	var best_s := 0.0

	for i in range(_uv_loop.size() - 1):
		var a := _uv_loop[i]
		var b := _uv_loop[i + 1]
		var ab := b - a
		var ab2 := ab.length_squared()
		var t := 0.0
		if ab2 > 0.0:
			var proj := (uv - a).dot(ab) / ab2
			if proj < 0.0: proj = 0.0
			if proj > 1.0: proj = 1.0
			t = proj
		var p := a + ab * t
		var d2 := (uv - p).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best_s = _cum_len_px[i] + t * _seg_len_px[i]
	return _wrap_s(best_s)

func _tangent_smooth_at_uv(uv: Vector2, window_px: float) -> Vector2:
	# Central-difference tangent using arc-length samples s±window_px
	if not _path_ready:
		return Vector2(1, 0)
	var s0 := _project_uv_to_s(uv)
	var sA := _wrap_s(s0 - window_px)
	var sB := _wrap_s(s0 + window_px)
	var pA := _sample_uv_at_s(sA)
	var pB := _sample_uv_at_s(sB)
	var t := pB - pA
	var L := t.length()
	if L > 0.00001:
		return t / L
	# fallback: nearest segment direction
	var i := _find_segment_for_s(s0)
	var seg := _uv_loop[(i + 1) % _uv_loop.size()] - _uv_loop[i]
	var Ls := seg.length()
	if Ls > 0.00001:
		return seg / Ls
	return Vector2(1, 0)

func _get_uv_loop_from_minimap() -> PackedVector2Array:
	# Expect minimap to expose a getter; if not, add one:
	#   func get_uv_loop() -> PackedVector2Array: return _uv_loop
	var out := PackedVector2Array()
	if _minimap.has_method("get_uv_loop"):
		out = _minimap.call("get_uv_loop")
	return out

func _smooth_vec(prev: Vector2, target: Vector2, dt: float, half_life: float) -> Vector2:
	var hl = max(half_life, 0.0001)
	var a := 1.0 - pow(0.5, dt / hl)
	return prev + (target - prev) * a

func _get_forward_axis(r: Node, uv_now: Vector2, id: int, dt: float) -> Vector2:
	# 1) try the racer’s velocity (preferred)
	var fwd := Vector2.ZERO
	if r.has_method("ReturnVelocity"):
		var v = r.call("ReturnVelocity")
		if v is Vector3:
			var vx := float(v.x)
			var vz := float(v.z)
			var L := sqrt(vx * vx + vz * vz)
			if L > 0.00001:
				fwd = Vector2(vx / L, vz / L)

	# 2) else estimate from motion (Δuv / dt)
	if fwd == Vector2.ZERO and dt > 0.0 and _last_uv_by_id.has(id):
		var uv_prev: Vector2 = _last_uv_by_id[id]
		var duv := uv_now - uv_prev
		var speed_uv := duv.length() / dt
		if speed_uv >= min_motion_uv_per_sec:
			var L2 := duv.length()
			if L2 > 0.00001:
				fwd = duv / L2

	# 3) else fall back to path tangent
	if fwd == Vector2.ZERO:
		var tan := _nearest_tangent_at(uv_now)
		var Lt := tan.length()
		if Lt > 0.00001:
			fwd = tan / Lt
		else:
			fwd = Vector2(1, 0)

	# smooth and normalize
	var prev = _fwd_smooth_by_id.get(id, fwd)
	var sm := _smooth_vec(prev, fwd, dt, fwd_half_life_s)
	var Ls := sm.length()
	if Ls > 0.00001:
		sm = sm / Ls
	else:
		sm = fwd
	_fwd_smooth_by_id[id] = sm
	_last_uv_by_id[id] = uv_now
	return sm

func _process_racer(r: Node) -> void:
	if not r.has_method("ReturnMapPosition"):
		return

	var mp = r.call("ReturnMapPosition")
	var uv: Vector2 = _coerce_pos_to_uv(mp)
	if not _is_uv01(uv):
		_end_channels(r)
		return

	var is_drifting := false
	if r.has_method("ReturnIsDrifting"):
		is_drifting = r.call("ReturnIsDrifting")

	var is_offroad := false
	if r.has_method("ReturnOnRoadType"):
		var rt = r.call("ReturnOnRoadType")
		if typeof(rt) == TYPE_INT:
			if rt == 2 or rt == 3:
				is_offroad = true

	var should_draw := false
	if draw_when_drifting and is_drifting:
		should_draw = true
	if draw_when_offroad and is_offroad:
		should_draw = true

	var id := r.get_instance_id()
	if not should_draw:
		_end_channels(r)
		return

	# --- orientation strictly from path, with the same kind of smoothing you use for drift ---
	var fwd := _tangent_smooth_at_uv(uv, orient_window_px)  # unit
	var right := Vector2(-fwd.y, fwd.x)                     # unit

	# rear-axle base
	var back_uv := rear_axle_back_px / float(max(1, map_size_px))
	var base_uv := uv - fwd * back_uv

	# small optional lead (if you still want it)
	var spx := 0.0
	if r.has_method("ReturnMovementSpeed"):
		var s = r.call("ReturnMovementSpeed")
		if typeof(s) == TYPE_FLOAT or typeof(s) == TYPE_INT:
			spx = float(s)
	var lead_time := overlay_latency_frames * _last_dt
	var lead_uv := (spx * lead_time) / float(max(1, map_size_px))
	base_uv += fwd * lead_uv

	# wheel offsets
	var side_uv := rear_half_span_px / float(max(1, map_size_px))
	var uv_rl := _clamp_uv01(base_uv - right * side_uv)
	var uv_rr := _clamp_uv01(base_uv + right * side_uv)

	if _overlay != null and _overlay.has_method("mm_append_uv"):
		_overlay.call("mm_append_uv", id, 0, uv_rl, is_drifting)
		_overlay.call("mm_append_uv", id, 1, uv_rr, is_drifting)

func _end_channels(r: Node) -> void:
	if _overlay == null:
		return
	if not _overlay.has_method("mm_end"):
		return
	var id := r.get_instance_id()
	_overlay.call("mm_end", id, 0)
	_overlay.call("mm_end", id, 1)

func _nearest_tangent_at(uv: Vector2) -> Vector2:
	if _uv_loop.size() < 2:
		return Vector2(1, 0)

	var best_d2 := INF
	var a_best := Vector2.ZERO
	var b_best := Vector2.RIGHT

	for i in range(_uv_loop.size() - 1):
		var a := _uv_loop[i]
		var b := _uv_loop[i + 1]
		var ab := b - a
		var ab2 := ab.length_squared()
		var t := 0.0
		if ab2 > 0.0:
			var proj := (uv - a).dot(ab) / ab2
			if proj < 0.0:
				proj = 0.0
			if proj > 1.0:
				proj = 1.0
			t = proj
		var p := a + ab * t
		var d2 := (uv - p).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			a_best = a
			b_best = b

	var tan := b_best - a_best
	if tan.length_squared() <= 0.0:
		return Vector2(1, 0)
	return tan.normalized()

func _clamp_uv01(v: Vector2) -> Vector2:
	var x := v.x
	var y := v.y
	if x < 0.0:
		x = 0.0
	if x > 1.0:
		x = 1.0
	if y < 0.0:
		y = 0.0
	if y > 1.0:
		y = 1.0
	return Vector2(x, y)

func _coerce_pos_to_uv(p) -> Vector2:
	# Prefer Minimap converters if available
	if typeof(p) == TYPE_VECTOR3:
		if _minimap != null and _minimap.has_method("pos3_to_uv"):
			return _minimap.call("pos3_to_uv", p)
		if _minimap != null and _minimap.has_method("get_uv_from_world"):
			return _minimap.call("get_uv_from_world", p)

		# Fallback: interpret as pixel or world mapped to 1024
		var uv3 := _pos3_to_uv_raw(p)  # returns x,z unchanged
		var u := uv3.x
		var v := uv3.y
		if abs(u) > 1.5 or abs(v) > 1.5:
			var inv := 1.0 / float(max(1, map_size_px))
			u = u * inv
			v = v * inv
		return Vector2(u, v)

	if typeof(p) == TYPE_VECTOR2:
		var u2 = p.x
		var v2 = p.y
		if abs(u2) > 1.5 or abs(v2) > 1.5:
			var inv2 := 1.0 / float(max(1, map_size_px))
			u2 = u2 * inv2
			v2 = v2 * inv2
		return Vector2(u2, v2)

	return Vector2(-1.0, -1.0)

func _pos3_to_uv_raw(p3: Vector3) -> Vector2:
	var u := p3.x
	var v := p3.z
	if use_y_instead_of_z:
		v = p3.y
	return Vector2(u, v)


func _pos3_to_uv(p3: Vector3) -> Vector2:
	# Prefer asking the minimap if it exposes a converter
	if _minimap != null and _minimap.has_method("pos3_to_uv"):
		return _minimap.call("pos3_to_uv", p3)
	if _minimap != null and _minimap.has_method("get_uv_from_world"):
		return _minimap.call("get_uv_from_world", p3)

	var inv := 1.0 / float(max(1, map_size_px))
	var u := p3.x * inv
	var v := p3.z * inv
	if use_y_instead_of_z:
		v = p3.y * inv
	return Vector2(u, v)

func _is_uv01(uv: Vector2) -> bool:
	if uv.x < 0.0:
		return false
	if uv.x > 1.0:
		return false
	if uv.y < 0.0:
		return false
	if uv.y > 1.0:
		return false
	return true
