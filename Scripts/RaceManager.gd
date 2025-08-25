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

var _last_board_sig := ""

@export var forward_increases_s_px := true

# >>> NEW: public helpers for the UI <<<
func GetLoopLengthPx() -> float:
	return _loop_len_px

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

func _progress_value(ent: Dictionary) -> float:
	# robust if loop length isn't ready yet
	if _loop_len_px <= 0.0:
		return float(ent["s_px"])
	return float(ent["lap"]) * _loop_len_px + float(ent["s_px"])

func _seg_count() -> int:
	return max(0, _segments.size())

# --- helper: closest segment + t in [0,1]
func _sample_seg_t_of(r: Node) -> Dictionary:
	if _segments.is_empty():
		return {"i": 0, "t": 0.0}
	var p3: Vector3 = r.ReturnMapPosition()
	var uv := Vector2(p3.x / float(map_size_px), p3.z / float(map_size_px))
	var best_i := 0
	var best_t := 0.0
	var best_d2 := 1e30
	for i in range(_segments.size()):
		var a: Vector2 = _segments[i]["a_uv"]
		var b: Vector2 = _segments[i]["b_uv"]
		var ab := b - a
		var ab2 := ab.length_squared()
		var t := 0.0
		if ab2 > 0.0:
			t = clamp((uv - a).dot(ab) / ab2, 0.0, 1.0)
		var proj := a.lerp(b, t)
		var d2 := proj.distance_squared_to(uv)
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
			best_t = t
	return {"i": best_i, "t": best_t}

# --- helper: (seg_i, t) -> arc distance s_px (pixels)
func _s_px_from_seg_t(i: int, t: float) -> float:
	if _segments.is_empty():
		return 0.0
	i = clamp(i, 0, _segments.size() - 1)
	var seg = _segments[i]
	var before := float(seg["cum_px"]) - float(seg["len_px"])
	return before + t * float(seg["len_px"])

# Rank comparator: (lap, s_px) in the forward direction, then stable id
func _ahead(a: Dictionary, b: Dictionary) -> bool:
	var la := int(a["lap"])
	var lb := int(b["lap"])
	if la != lb:
		return la > lb

	var sa := float(a["s_px"])
	var sb := float(b["s_px"])
	if sa != sb:
		# Direction-aware comparison
		if forward_increases_s_px:
			return sa > sb
		else:
			return sa < sb

	var aid := (a["node"] as Node).get_instance_id()
	var bid := (b["node"] as Node).get_instance_id()
	return aid < bid

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

	# ---- DEBUG: verify wiring at boot ----
	print("[RaceManager] Setup: racers=", _racers.size(), " segments=", _segments.size(), " loop_len_px=", _loop_len_px)
	for r in _racers:
		var p3: Vector3 = r.ReturnMapPosition()
		prints("  racer:", r.name, "pos(", p3.x, p3.y, p3.z, ") s_px=", _sample_s_of(r))

	emit_signal("standings_changed", GetCurrentStandings())

func Update() -> void:
	if _segments.is_empty():
		_rebuild_path_segments()
		if _segments.is_empty():
			if Engine.get_process_frames() % 60 == 0:
				print("[RaceManager] _segments empty; no standings update. loop_len_px=", _loop_len_px)
			return

	var changed := false

	# ---- per-racer progress (lap, s_px) ----
	for r in _racers:
		if not is_instance_valid(r):
			continue

		var id := r.get_instance_id()
		if not _progress.has(id):
			_progress[id] = {"lap": 0, "s_px": 0.0, "prev_s_px": 0.0}

		var prev_s := float(_progress[id]["s_px"])
		var lap    := int(_progress[id]["lap"])
		var s := _sample_s_of(r)

		# wrap-safe lap accounting using arc-distance, honoring direction
		var half = max(_loop_len_px * 0.5, 1.0)
		var ds := s - prev_s

		if forward_increases_s_px:
			if ds < -half:
				lap += 1
			elif ds > half:
				lap = max(0, lap - 1)
		else:
			if ds > half:
				lap += 1
			elif ds < -half:
				lap = max(0, lap - 1)

		if s != prev_s or lap != int(_progress[id]["lap"]):
			changed = true

		_progress[id]["prev_s_px"] = prev_s
		_progress[id]["s_px"] = s
		_progress[id]["lap"] = lap

	# ---- build sorted board (lap, s_px) ----
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		board.append({
			"node": r,
			"lap":  int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"])
		})

	board.sort_custom(_ahead)
	for i in range(board.size()):
		board[i]["place"] = i + 1

	_apply_z_order()

	# ---- DEBUG signature: includes instance ids in order to detect swaps ----
	var sig_parts := []
	for i in range(board.size()):
		var it: Dictionary = board[i]
		var rid := (it["node"] as Node).get_instance_id()
		var lap_i := int(it["lap"])
		var spx := float(it["s_px"])
		sig_parts.append(str(rid, ":", lap_i, ":", int(spx)))
	var sig := ",".join(sig_parts)

	var do_periodic := (Engine.get_process_frames() % 30) == 0  # ~2x/sec
	var order_changed := (sig != _last_board_sig)

	if do_periodic or order_changed:
		print("[RaceManager] loop_len_px=", _loop_len_px, " changed=", changed, " order_changed=", order_changed, " racers=", _racers.size())
		for r in _racers:
			var id := r.get_instance_id()
			var prev_s := float(_progress[id]["prev_s_px"])
			var s := float(_progress[id]["s_px"])
			var ds := s - prev_s
			prints("    ", r.name, "lap", _progress[id]["lap"], "s_px", s, "ds", ds)

	_last_board_sig = sig

	# ---- emit when data changes OR the sorted order changes ----
	if changed or order_changed:
		emit_signal("standings_changed", board)
		print("[RaceManager] emitted standings_changed (changed=", changed, " order_changed=", order_changed, ")")

func GetCurrentStandings() -> Array:
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		board.append({
			"node": r,
			"lap":  int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"])
		})

	board.sort_custom(_ahead)
	for i in range(board.size()):
		board[i]["place"] = i + 1
	return board

# Heuristic: convert a racer position to UV correctly (0..1 on both axes)
func _pos_to_uv(p3: Vector3) -> Vector2:
	# If the coordinates already look like UV (small), use them as-is.
	# Otherwise treat them as pixels and normalize by map_size_px.
	var ax = abs(p3.x)
	var az = abs(p3.z)
	if ax <= 2.0 and az <= 2.0:
		# Already UV (typical values ~0.0..1.0). Your logs show ~0.92 / ~0.76.
		return Vector2(p3.x, p3.z)
	else:
		# Pixels -> UV
		return Vector2(p3.x / float(map_size_px), p3.z / float(map_size_px))

# >>> REPLACE your _sample_s_of with this one (uses the UV from _pos_to_uv)
func _sample_s_of(r: Node) -> float:
	if _segments.is_empty():
		return 0.0

	var p3: Vector3 = r.ReturnMapPosition()
	var uv: Vector2 = _pos_to_uv(p3)  # <-- key fix

	# Try “on-segment” fast-path first
	for seg in _segments:
		var a: Vector2 = seg["a_uv"]
		var b: Vector2 = seg["b_uv"]
		var ab := b - a
		var ab2 := ab.length_squared()
		if ab2 <= 0.0:
			continue
		var t = clamp((uv - a).dot(ab) / ab2, 0.0, 1.0)
		var proj := a.lerp(b, t)
		# 0.001 UV ~ 1px on a 1024 map — keep as-is, or loosen slightly if needed
		if proj.distance_squared_to(uv) <= 0.001 * 0.001:
			var before := float(seg["cum_px"]) - float(seg["len_px"])
			return before + (t * float(seg["len_px"]))

	# Fallback: nearest segment (works for off-line points)
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
