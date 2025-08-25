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
		var st := _sample_seg_t_of(r)
		var i := int(st["i"])
		var t := float(st["t"])
		_progress[r.get_instance_id()] = {"lap": 0, "seg_i": i, "t": t, "prev_i": i, "prev_t": t}

	emit_signal("standings_changed", GetCurrentStandings())

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

# --- comparator: rank by (lap, seg_i, t) if present; otherwise by (lap, s_px)
func _ahead(a: Dictionary, b: Dictionary) -> bool:
	# 1) laps
	var la := int(a.get("lap", 0))
	var lb := int(b.get("lap", 0))
	if la != lb:
		return la > lb

	# 2) segment/t if available on both
	var has_seg := a.has("seg_i") and a.has("t") and b.has("seg_i") and b.has("t")
	if has_seg:
		var ia := int(a["seg_i"])
		var ib := int(b["seg_i"])
		if ia != ib:
			return ia > ib
		var ta := float(a["t"])
		var tb := float(b["t"])
		if abs(ta - tb) > 0.0005:
			return ta > tb
	else:
		# 2’) fall back to s_px if present
		var has_spx := a.has("s_px") and b.has("s_px")
		if has_spx:
			var sa := float(a["s_px"])
			var sb := float(b["s_px"])
			if sa != sb:
				return sa > sb
		else:
			# 2’’) last resort: compute s_px on the fly if seg/t exists on either one
			var sa2 := 0.0
			if a.has("seg_i") and a.has("t"):
				sa2 = _s_px_from_seg_t(int(a["seg_i"]), float(a["t"]))
			var sb2 := 0.0
			if b.has("seg_i") and b.has("t"):
				sb2 = _s_px_from_seg_t(int(b["seg_i"]), float(b["t"]))
			if sa2 != sb2:
				return sa2 > sb2

	# 3) stable, non-visual tie-break
	var aid := (a["node"] as Node).get_instance_id()
	var bid := (b["node"] as Node).get_instance_id()
	return aid < bid

# --- FULL Update: keeps lap/seg_i/t, builds board WITH s_px, sorts with _ahead
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

		# initialize/migrate progress record
		if not _progress.has(id):
			_progress[id] = {"lap": 0, "seg_i": 0, "t": 0.0, "prev_i": 0, "prev_t": 0.0}
		else:
			var rec: Dictionary = _progress[id]
			if not rec.has("seg_i") or not rec.has("t"):
				var st0 := _sample_seg_t_of(r)
				rec["seg_i"] = int(st0["i"])
				rec["t"] = float(st0["t"])
				rec["prev_i"] = int(st0["i"])
				rec["prev_t"] = float(st0["t"])
				rec["lap"] = int(rec.get("lap", 0))
				_progress[id] = rec

		var prev_i := int(_progress[id]["seg_i"])
		var prev_t := float(_progress[id]["t"])
		var lap    := int(_progress[id]["lap"])

		var st := _sample_seg_t_of(r)
		var seg_i := int(st["i"])
		var t     := float(st["t"])

		# lap accounting by index wrap (with small hysteresis)
		var N := _segments.size()
		if N > 0:
			if (prev_i > N - 4) and (seg_i < 3):
				lap += 1
			elif (prev_i < 3) and (seg_i > N - 4):
				lap = max(0, lap - 1)

		if seg_i != prev_i or abs(t - prev_t) > 0.0005 or lap != int(_progress[id]["lap"]):
			changed = true

		_progress[id]["prev_i"] = prev_i
		_progress[id]["prev_t"] = prev_t
		_progress[id]["seg_i"]  = seg_i
		_progress[id]["t"]      = t
		_progress[id]["lap"]    = lap

	# build board (includes s_px so UI & snapshots work)
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		var seg_i := int(_progress[id]["seg_i"])
		var t := float(_progress[id]["t"])
		board.append({
			"node":  r,
			"lap":   int(_progress[id]["lap"]),
			"seg_i": seg_i,
			"t":     t,
			"s_px":  _s_px_from_seg_t(seg_i, t)
		})

	board.sort_custom(_ahead)

	for i in range(board.size()):
		board[i]["place"] = i + 1

	_apply_z_order()

	if changed:
		emit_signal("standings_changed", board)

# --- FULL GetCurrentStandings: same shape as Update (and includes s_px)
func GetCurrentStandings() -> Array:
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		var seg_i := int(_progress[id].get("seg_i", 0))
		var t := float(_progress[id].get("t", 0.0))
		board.append({
			"node":  r,
			"lap":   int(_progress[id].get("lap", 0)),
			"seg_i": seg_i,
			"t":     t,
			"s_px":  _s_px_from_seg_t(seg_i, t)
		})

	board.sort_custom(_ahead)

	for i in range(board.size()):
		board[i]["place"] = i + 1
	return board
