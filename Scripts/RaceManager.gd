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
signal race_finished(results: Array)

# --- Finish logic ---
@export var total_laps: int = 5
@export var finish_auto_speed_px: float = 220.0   # map pixels per second during auto drive
@export var finish_sprite_directions: int = 12    # hframes for the player's 12-angle sprite

var _race_over: bool = false
var _finish_mode: bool = false
var _finish_order: Array = []  # ids in the order they finish

var _finish_cam_played := false

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
# Sort: finished first by finish_rank, then active racers by (lap, s_px), then id
func _ahead(a: Dictionary, b: Dictionary) -> bool:
	var fa := bool(a.get("finished", false))
	var fb := bool(b.get("finished", false))
	if fa and not fb:
		return true
	if fb and not fa:
		return false
	if fa and fb:
		var ra := int(a.get("finish_rank", 0))
		var rb := int(b.get("finish_rank", 0))
		if ra != rb:
			return ra < rb
		var aid := (a["node"] as Node).get_instance_id()
		var bid := (b["node"] as Node).get_instance_id()
		return aid < bid

	# neither finished -> use lap/s_px + direction
	var la := int(a["lap"])
	var lb := int(b["lap"])
	if la != lb:
		return la > lb

	var sa := float(a["s_px"])
	var sb := float(b["s_px"])
	if sa != sb:
		if forward_increases_s_px:
			return sa > sb
		else:
			return sa < sb

	var aid := (a["node"] as Node).get_instance_id()
	var bid := (b["node"] as Node).get_instance_id()
	return aid < bid

func Setup() -> void:
	# Cache scene refs
	_pseudo3d = get_node_or_null(pseudo3d_node)
	_overlay  = get_node_or_null(path_overlay_node)
	_player   = get_node_or_null(player_path)

	# Build racer list
	var root := get_node_or_null(racers_root)
	_racers.clear()
	if root:
		for c in root.get_children():
			if c is Node and c.has_method("ReturnMapPosition") and c.has_method("ReturnSpriteGraphic"):
				_racers.append(c)
	# Ensure player is in the list and first
	if _player and not _racers.has(_player):
		_racers.insert(0, _player)

	# Path segments
	_rebuild_path_segments()

	# Reset state
	_progress.clear()
	_last_board_sig = ""
	if typeof(_finish_order) != TYPE_NIL:
		_finish_order.clear()
	_race_over = false
	_finish_mode = false
	_finish_cam_played = false

	# Do NOT start timing yet; timing begins when Lap becomes 1 on first S/F crossing.
	for r in _racers:
		var s := _sample_s_of(r)
		_progress[r.get_instance_id()] = {
			"lap": 0,
			"s_px": s,
			"prev_s_px": s,
			"lap_start_ms": 0,
			"timing_started": false,
			"last_lap_ms": 0,
			"best_lap_ms": 0,
			"total_ms": 0,           # <<< NEW
			"finished": false,
			"finish_rank": 0
		}

	# Debug
	print("[RaceManager] Setup: racers=", _racers.size(), " segments=", _segments.size(), " loop_len_px=", _loop_len_px)
	for r in _racers:
		var p3: Vector3 = r.ReturnMapPosition()
		prints("  racer:", r.name, "pos(", p3.x, p3.y, p3.z, ") s_px=", _sample_s_of(r))

	# Initial emit
	emit_signal("standings_changed", GetCurrentStandings())

func Update() -> void:
	if _segments.is_empty():
		_rebuild_path_segments()
		if _segments.is_empty():
			if Engine.get_process_frames() % 60 == 0:
				print("[RaceManager] _segments empty; no standings update. loop_len_px=", _loop_len_px)
			return

	var changed := false

	# progress update
	for r in _racers:
		if not is_instance_valid(r):
			continue

		var id := r.get_instance_id()
		if not _progress.has(id):
			_progress[id] = {
				"lap": 0, "s_px": 0.0, "prev_s_px": 0.0,
				"lap_start_ms": 0, "timing_started": false,
				"last_lap_ms": 0, "best_lap_ms": 0,
				"total_ms": 0,
				"finished": false, "finish_rank": 0
			}

		# freeze finished racers
		if bool(_progress[id]["finished"]):
			continue

		var prev_s := float(_progress[id]["s_px"])
		var lap    := int(_progress[id]["lap"])
		var s := _sample_s_of(r)

		var half = max(_loop_len_px * 0.5, 1.0)
		var ds := s - prev_s
		var crossed_finish := false

		if forward_increases_s_px:
			if ds < -half:
				lap += 1
				crossed_finish = true
			elif ds > half:
				lap = max(0, lap - 1)
		else:
			if ds > half:
				lap += 1
				crossed_finish = true
			elif ds < -half:
				lap = max(0, lap - 1)

		# timing
		if crossed_finish:
			var timing_started: bool = bool(_progress[id].get("timing_started", false))
			var now_ms := Time.get_ticks_msec()
			if not timing_started and lap == 1:
				_progress[id]["timing_started"] = true
				_progress[id]["lap_start_ms"] = now_ms
			elif timing_started:
				var start_ms := int(_progress[id].get("lap_start_ms", now_ms))
				var lap_ms = max(0, now_ms - start_ms)
				_progress[id]["last_lap_ms"] = lap_ms
				var best_ms := int(_progress[id]["best_lap_ms"])
				if best_ms == 0 or lap_ms < best_ms:
					_progress[id]["best_lap_ms"] = lap_ms
				_progress[id]["lap_start_ms"] = now_ms

				# accumulate total race time
				var accum := int(_progress[id].get("total_ms", 0))
				_progress[id]["total_ms"] = accum + lap_ms

			# mark finished on crossing that reaches total_laps
			if lap >= total_laps and not bool(_progress[id]["finished"]):
				_progress[id]["finished"] = true
				_finish_order.append(id)
				_progress[id]["finish_rank"] = _finish_order.size()
				lap = total_laps
				changed = true

				# if the player just finished, start finish camera once
				if is_instance_valid(_player) and id == _player.get_instance_id():
					if not _finish_cam_played:
						_finish_cam_played = true
						_finish_mode = true
						if _player.has_method("EnableInput"):
							_player.call("EnableInput", false)
						if is_instance_valid(_pseudo3d) and _pseudo3d.has_method("StartFinishCamera"):
							_pseudo3d.call("StartFinishCamera", _player)

		if s != prev_s or lap != int(_progress[id]["lap"]):
			changed = true

		_progress[id]["prev_s_px"] = prev_s
		_progress[id]["s_px"] = s
		_progress[id]["lap"] = lap

	# build sorted board
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		var cur_spd := 0.0
		if r.has_method("ReturnMovementSpeed"):
			cur_spd = float(r.call("ReturnMovementSpeed"))

		var finished := bool(_progress[id].get("finished", false))
		var timing_started := bool(_progress[id].get("timing_started", false))
		var total_ms := int(_progress[id].get("total_ms", 0))
		# include current lap in-progress time while still running
		if timing_started and not finished:
			var now_ms := Time.get_ticks_msec()
			var start_ms := int(_progress[id].get("lap_start_ms", now_ms))
			total_ms += max(0, now_ms - start_ms)

		board.append({
			"node": r,
			"lap":  int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"]),
			"last_ms": int(_progress[id].get("last_lap_ms", 0)),
			"best_ms": int(_progress[id].get("best_lap_ms", 0)),
			"total_ms": total_ms,
			"cur_speed": cur_spd,
			"finished": finished,
			"finish_rank": int(_progress[id].get("finish_rank", 0))
		})

	board.sort_custom(_ahead)
	for i in range(board.size()):
		board[i]["place"] = i + 1

	_apply_z_order()

	# signature/debug (muted)
	var sig_parts := []
	for i in range(board.size()):
		var it: Dictionary = board[i]
		var rid := (it["node"] as Node).get_instance_id()
		var lap_i := int(it["lap"])
		var spx := float(it["s_px"])
		sig_parts.append(str(rid, ":", lap_i, ":", int(spx)))
	var sig := ",".join(sig_parts)

	var do_periodic := (Engine.get_process_frames() % 30) == 0
	var order_changed := (sig != _last_board_sig)
	_last_board_sig = sig

	# finish-mode extras
	if _finish_mode and is_instance_valid(_player):
		_autodrive_player_step(self.get_process_delta_time())
		_update_player_12frame_sprite()

	if changed or order_changed:
		emit_signal("standings_changed", board)

# -- Auto-drive the player forward at a constant arc speed (finish_auto_speed_px)
func _autodrive_player_step(dt: float) -> void:
	if _segments.is_empty() or not is_instance_valid(_player):
		return
	var id := _player.get_instance_id()
	if not _progress.has(id):
		return
	# advance the stored s_px
	var s := float(_progress[id]["s_px"]) + finish_auto_speed_px * dt
	# wrap around loop
	if _loop_len_px > 0.0:
		s = fposmod(s, _loop_len_px)
	_progress[id]["prev_s_px"] = float(_progress[id]["s_px"])
	_progress[id]["s_px"] = s

	# place the player on the path from s
	var uv := _uv_at_s(s)
	var px := uv * float(map_size_px)
	if _player.has_method("SetMapPosition"):
		_player.call("SetMapPosition", Vector3(px.x, 0.0, px.y))

# -- Compute UV on the path at arc-distance s (pixels)
func _uv_at_s(s_px: float) -> Vector2:
	if _segments.is_empty():
		return Vector2.ZERO
	var s = clamp(s_px, 0.0, max(0.0, _loop_len_px))
	# find segment that contains s
	for i in range(_segments.size()):
		var seg = _segments[i]
		var cum := float(seg["cum_px"])
		var len := float(seg["len_px"])
		var before := cum - len
		if s <= cum or i == _segments.size() - 1:
			var t := 0.0
			if len > 0.0:
				t = clamp((s - before) / len, 0.0, 1.0)
			var a: Vector2 = seg["a_uv"]
			var b: Vector2 = seg["b_uv"]
			return a.lerp(b, t)
	return Vector2.ZERO

# -- Compute tangent (unit) on the path at arc-distance s (pixels)
func _tangent_at_s(s_px: float) -> Vector2:
	if _segments.is_empty():
		return Vector2.RIGHT
	var s = clamp(s_px, 0.0, max(0.0, _loop_len_px))
	for i in range(_segments.size()):
		var seg = _segments[i]
		var cum := float(seg["cum_px"])
		var len := float(seg["len_px"])
		var before := cum - len
		if s <= cum or i == _segments.size() - 1:
			var a: Vector2 = seg["a_uv"]
			var b: Vector2 = seg["b_uv"]
			var t2 := (b - a)
			var L := t2.length()
			return (t2 / (L if L > 0.00001 else 1.0))
	return Vector2.RIGHT

# -- Pick the correct frame (of 12) for the player's sprite vs camera yaw while in finish mode
# -- Pick the correct frame (of 12) for the player's sprite vs camera yaw while in finish mode
func _update_player_12frame_sprite() -> void:
	if not is_instance_valid(_player):
		return
	var spr = _player.ReturnSpriteGraphic()
	if spr == null:
		return
	if not is_instance_valid(_pseudo3d) or not _pseudo3d.has_method("get_camera_forward_map"):
		return

	# camera forward in map space
	var cam_f: Vector2 = _pseudo3d.call("get_camera_forward_map")
	var cam_yaw: float = atan2(cam_f.y, cam_f.x)

	# player path tangent as "heading"
	var id := _player.get_instance_id()
	var s := float(_progress.get(id, {}).get("s_px", 0.0))
	var tan: Vector2 = _tangent_at_s(s)
	var heading: float = atan2(tan.y, tan.x)

	# relative angle player->camera (same convention as Opponent)
	var theta_cam: float = wrapf(heading - cam_yaw, -PI, PI)
	var deg: float = rad_to_deg(theta_cam)

	# match your opponent logic
	var clockwise := true
	var frame0_is_front := true
	var angle_offset_deg := 0.0

	deg = wrapf(deg + angle_offset_deg, -180.0, 180.0)
	if not clockwise:
		deg = -deg

	var left_side := deg > 0.0
	var absdeg: float = clamp(abs(deg), 0.0, 179.999)
	var dirs = max(1, finish_sprite_directions)
	var step: float = 180.0 / float(dirs)
	var idx: int = int(floor((absdeg + step * 0.5) / step))
	if idx >= dirs:
		idx = dirs - 1
	if frame0_is_front:
		idx = (dirs - 1) - idx

	# apply to the sprite
	if spr is Sprite2D:
		var s2 := spr as Sprite2D
		if s2.hframes != dirs:
			s2.hframes = dirs
			s2.vframes = 1
		s2.frame = idx
		s2.flip_h = left_side
	elif spr.has_method("set_frame"):
		spr.frame = idx
		if "flip_h" in spr:
			spr.flip_h = left_side

func GetCurrentStandings() -> Array:
	var board := []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		var cur_spd := 0.0
		if r.has_method("ReturnMovementSpeed"):
			cur_spd = float(r.call("ReturnMovementSpeed"))

		var finished := bool(_progress[id].get("finished", false))
		var timing_started := bool(_progress[id].get("timing_started", false))
		var total_ms := int(_progress[id].get("total_ms", 0))
		if timing_started and not finished:
			var now_ms := Time.get_ticks_msec()
			var start_ms := int(_progress[id].get("lap_start_ms", now_ms))
			total_ms += max(0, now_ms - start_ms)

		board.append({
			"node": r,
			"lap":  int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"]),
			"last_ms": int(_progress[id].get("last_lap_ms", 0)),
			"best_ms": int(_progress[id].get("best_lap_ms", 0)),
			"total_ms": total_ms,
			"cur_speed": cur_spd,
			"finished": finished,
			"finish_rank": int(_progress[id].get("finish_rank", 0))
		})
	board.sort_custom(_ahead)
	for i in range(board.size()):
		board[i]["place"] = i + 1
	return board

# --- DIFFICULTY HELPERS FOR AI ---

func GetPlayerLap() -> int:
	if _player == null:
		return 0
	var id := _player.get_instance_id()
	if _progress.has(id):
		return int(_progress[id].get("lap", 0))
	return 0

func GetLeaderLap() -> int:
	# Uses same sorting rule as the board; robust if segments not ready.
	var best_lap := 0
	var best_s := -1e30
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := r.get_instance_id()
		var lap := int(_progress[id].get("lap", 0))
		var s := float(_progress[id].get("s_px", 0.0))
		if lap > best_lap:
			best_lap = lap
			best_s = s
		elif lap == best_lap and s > best_s:
			best_s = s
	return best_lap

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
