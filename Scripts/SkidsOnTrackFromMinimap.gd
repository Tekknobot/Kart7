extends Node

@export var minimap_node: NodePath
@export var path_overlay_node: NodePath
@export var racers_group: String = "opponents"
@export var map_size_px: int = 1024
@export var rear_half_span_px: float = 26.0
@export var draw_when_drifting: bool = true
@export var draw_when_offroad: bool = false
@export var use_y_instead_of_z: bool = false  # set true if your track uses XY instead of XZ

var _minimap: Node = null
var _overlay: Node = null
var _uv_loop: PackedVector2Array = PackedVector2Array()

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
	if _minimap == null:
		return
	if _overlay == null:
		return

	_uv_loop = _get_uv_loop_from_minimap()

	var opponents := get_tree().get_nodes_in_group(racers_group)
	for r in opponents:
		_process_racer(r)

func _get_uv_loop_from_minimap() -> PackedVector2Array:
	# Expect minimap to expose a getter; if not, add one:
	#   func get_uv_loop() -> PackedVector2Array: return _uv_loop
	var out := PackedVector2Array()
	if _minimap.has_method("get_uv_loop"):
		out = _minimap.call("get_uv_loop")
	return out

func _process_racer(r: Node) -> void:
	if not r.has_method("ReturnMapPosition"):
		return

	var mp = r.call("ReturnMapPosition")
	var uv: Vector2 = _coerce_pos_to_uv(mp)
	
	print_verbose("racer ", r.name, " uv=", uv)
		
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

	if should_draw:
		var tan := _nearest_tangent_at(uv)
		var off_uv := rear_half_span_px / float(max(1, map_size_px))
		var side := Vector2(-tan.y, tan.x) * off_uv

		var uv_rl := _clamp_uv01(uv - side)
		var uv_rr := _clamp_uv01(uv + side)

		if _overlay.has_method("mm_append_uv"):
			_overlay.call("mm_append_uv", id, 0, uv_rl, is_drifting)
			_overlay.call("mm_append_uv", id, 1, uv_rr, is_drifting)
	else:
		_end_channels(r)

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
