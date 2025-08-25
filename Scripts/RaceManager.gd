extends Node
class_name RaceManager

signal standings_changed(standings: Array)

@export var pseudo3d_node: NodePath
@export var path_overlay_node: NodePath
@export var racers_root: NodePath
@export var player_path: NodePath
@export var map_size_px: int = 1024

@export var force_player_on_top := true
@export var player_on_top_margin := 10
@export var player_front_screen_epsilon: float = 2.0

var _pseudo3d: Node = null
var _overlay: Node = null
var _player: Node = null
var _racers: Array[Node] = []
var _segments := []
var _loop_len_px := 0.0
var _progress := {}

func Setup() -> void:
	_pseudo3d = get_node_or_null(pseudo3d_node)
	_overlay  = get_node_or_null(path_overlay_node)
	_player   = get_node_or_null(player_path)

	var root := get_node_or_null(racers_root)
	_racers.clear()
	if root:
		for c in root.get_children():
			if c is Node and c.has_method("ReturnMapPosition") and c.has_method("ReturnSpriteGraphic"):
				_racers.append(c)
	if _player and not _racers.has(_player):
		_racers.insert(0, _player)

	_rebuild_path_segments()
	_progress.clear()
	for r in _racers:
		var s := _sample_s_of(r)
		_progress[r.get_instance_id()] = {"lap": 0, "s_px": s, "prev_s_px": s}

	# >>> NEW: give UI an immediate snapshot <<<
	emit_signal("standings_changed", GetCurrentStandings())

func Update() -> void:
	if _segments.is_empty():
		_rebuild_path_segments()
		if _segments.is_empty():
			return

	var changed := false
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		if not _progress.has(id):
			_progress[id] = {"lap": 0, "s_px": 0.0, "prev_s_px": 0.0}

		var prev = _progress[id]["s_px"]
		var s := _sample_s_of(r)
		var lap := int(_progress[id]["lap"])

		var half := _loop_len_px * 0.5
		var ds = s - prev
		if ds < -half:
			lap += 1
		elif ds > half:
			lap = max(0, lap - 1)

		if s != prev or lap != int(_progress[id]["lap"]):
			changed = true

		_progress[id]["prev_s_px"] = prev
		_progress[id]["s_px"] = s
		_progress[id]["lap"] = lap

	# standings + z-order unchanged
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		var ent := {
			"node": r,
			"lap": int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"])
		}
		board.append(ent)

	board.sort_custom(func(a, b):
		if a["lap"] != b["lap"]:
			return a["lap"] > b["lap"]
		if a["s_px"] != b["s_px"]:
			return a["s_px"] > b["s_px"]
		var ay := _screen_y_of(a["node"])
		var by := _screen_y_of(b["node"])
		return ay > by
	)

	for i in range(board.size()):
		board[i]["place"] = i + 1

	_apply_z_order()

	if changed:
		emit_signal("standings_changed", board)

# >>> NEW: public helpers for the UI <<<

func GetLoopLengthPx() -> float:
	return _loop_len_px

func GetCurrentStandings() -> Array:
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		board.append({
			"node": r,
			"lap": int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"])
		})
	board.sort_custom(func(a, b):
		if a["lap"] != b["lap"]:
			return a["lap"] > b["lap"]
		if a["s_px"] != b["s_px"]:
			return a["s_px"] > b["s_px"]
		var ay := _screen_y_of(a["node"])
		var by := _screen_y_of(b["node"])
		return ay > by
	)
	for i in range(board.size()):
		board[i]["place"] = i + 1
	return board

# --- helpers below unchanged ---

func _rebuild_path_segments() -> void:
	_segments.clear()
	_loop_len_px = 0.0
	var uv_loop := _get_path_points_uv_closed()
	if uv_loop.size() < 2:
		return
	for i in range(uv_loop.size() - 1):
		var a: Vector2 = uv_loop[i]
		var b: Vector2 = uv_loop[i + 1]
		var len_px := a.distance_to(b) * float(map_size_px)
		if len_px <= 0.0:
			continue
		_loop_len_px += len_px
		_segments.append({"a_uv": a, "b_uv": b, "len_px": len_px, "cum_px": _loop_len_px})

func _get_path_points_uv_closed() -> PackedVector2Array:
	var pts: PackedVector2Array
	if _pseudo3d:
		for name in ["GetPathPointsUV","get_path_points_uv","ReturnPathPointsUV"]:
			if _pseudo3d.has_method(name):
				pts = _pseudo3d.call(name)
				break
	if (pts == null or pts.size() == 0) and _overlay:
		for name in ["get_path_points_uv_transformed","get_path_points_uv"]:
			if _overlay.has_method(name):
				pts = _overlay.call(name)
				break
	if pts != null and pts.size() >= 2:
		var a := pts[0]
		var b := pts[pts.size() - 1]
		if not a.is_equal_approx(b):
			var out := PackedVector2Array()
			for i in range(pts.size()):
				out.append(pts[i])
			out.append(a)
			return out
	if pts == null:
		return PackedVector2Array()
	return pts

func _sample_s_of(r: Node) -> float:
	if _segments.is_empty():
		return 0.0
	var p3: Vector3 = r.ReturnMapPosition()
	var uv := Vector2(p3.x / float(map_size_px), p3.z / float(map_size_px))
	for seg in _segments:
		var a: Vector2 = seg["a_uv"]
		var b: Vector2 = seg["b_uv"]
		var ab := b - a
		var ab2 := ab.length_squared()
		if ab2 <= 0.0:
			continue
		var t = clamp((uv - a).dot(ab) / ab2, 0.0, 1.0)
		var proj := a.lerp(b, t)
		if proj.distance_squared_to(uv) <= 0.001 * 0.001:
			var before := float(seg["cum_px"]) - float(seg["len_px"])
			return before + (t * float(seg["len_px"]))
	var best_s := 0.0
	var best_d2 := 1e9
	var cum_prev := 0.0
	for seg2 in _segments:
		var a2: Vector2 = seg2["a_uv"]
		var b2: Vector2 = seg2["b_uv"]
		var abv := b2 - a2
		var L := float(seg2["len_px"])
		var t2 := 0.0
		var abv2 := abv.length_squared()
		if abv2 > 0.0:
			t2 = clamp((uv - a2).dot(abv) / abv2, 0.0, 1.0)
		var proj2 := a2.lerp(b2, t2)
		var d2 := proj2.distance_squared_to(uv)
		if d2 < best_d2:
			best_d2 = d2
			best_s  = cum_prev + t2 * L
		cum_prev += L
	return best_s

func _apply_z_order() -> void:
	var elems := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var spr = r.ReturnSpriteGraphic()
		if spr == null:
			continue
		elems.append(r)
	elems.sort_custom(func(a, b):
		return _screen_y_of(a) < _screen_y_of(b)
	)
	var base := 0
	for e in elems:
		var spr = e.ReturnSpriteGraphic()
		if spr == null:
			continue
		if spr.z_index != base:
			spr.z_index = base
		base += 1
	if force_player_on_top and is_instance_valid(_player):
		var pspr = _player.ReturnSpriteGraphic()
		if pspr != null:
			if not _someone_lower_on_screen_than_player(elems):
				pspr.z_index = base + player_on_top_margin

func _screen_y_of(r: Node) -> float:
	if r.has_method("ReturnScreenPosition"):
		var v: Vector2 = r.ReturnScreenPosition()
		return v.y
	var spr = r.ReturnSpriteGraphic()
	if spr != null:
		return (spr as Node2D).global_position.y
	return 0.0

func _someone_lower_on_screen_than_player(elems: Array) -> bool:
	if _player == null:
		return false
	var p_y := _screen_y_of(_player)
	if p_y < 0.0:
		return false
	for e in elems:
		if e == _player:
			continue
		var y := _screen_y_of(e)
		if y < 0.0:
			continue
		if y > p_y + player_front_screen_epsilon:
			return true
	return false
