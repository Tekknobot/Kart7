extends Control
class_name Leaderboard

# ---------------- Scene refs (wire these in Inspector) ----------------
@export var pseudo3d_node: NodePath
@export var path_overlay_node: NodePath
@export var racers_root: NodePath
@export var player_path: NodePath

# ---------------- Layout ----------------
@export var max_rows: int = 8
@export var row_height: int = 32
@export var animate_time: float = 0.22

# Column widths (edit to taste)
@export var col_place_w: int = 40
@export var col_arrow_w: int = 20
@export var col_lap_w:   int = 60
@export var col_speed_w: int = 80
@export var col_gap_w:   int = 80

# Colors
@export var color_gain := Color(0.30, 1.00, 0.45, 0.90)
@export var color_loss := Color(1.00, 0.40, 0.40, 0.90)
@export var color_player_bg := Color(0.95, 0.90, 0.20, 0.20)
@export var color_row_even := Color(0.20, 0.20, 0.20, 0.35)
@export var color_row_odd  := Color(0.12, 0.12, 0.12, 0.35)

# ---------------- internals ----------------
var _p3d: Node
var _overlay: Node
var _player: Node
var _racers: Array = []

var _segments: Array = []         # [{a_uv:Vector2,b_uv:Vector2,len_px:float,cum_px:float}]
var _loop_len_px: float = 0.0

# progress cache: id -> {lap:int, s_px:float, prev_s_px:float}
var _progress := {}

# UI containers & rows (built on the fly)
var _header: HBoxContainer
var _rows_holder: Control
var _rows: Array = []             # index -> {bg:ColorRect, place:Label, arrow:Label, name:Label, lap:Label, speed:Label, gap:Label}
var _row_owner_for_id := {}       # racer_id -> row_index
var _prev_place_for_id := {}      # racer_id -> int
var _tweens := {}                 # row_index -> Tween

# leader snapshot
var _leader_id := 0
var _leader_lap := 0
var _leader_s_px := 0.0

# ---------------- lifecycle ----------------
func _ready() -> void:
	_build_ui_once()

	_p3d = get_node_or_null(pseudo3d_node)
	_overlay = get_node_or_null(path_overlay_node)
	_player = get_node_or_null(player_path)

	_collect_racers()
	_rebuild_path_segments()
	_seed_progress()
	_draw_initial_board()

	set_process(true)

func _exit_tree() -> void:
	for k in _tweens.keys():
		var tw: Tween = _tweens[k]
		if tw: tw.kill()
	_tweens.clear()

func _process(_dt: float) -> void:
	if _racers.is_empty():
		_collect_racers()
	if _segments.is_empty():
		_rebuild_path_segments()
		if _segments.is_empty():
			return

	var changed := _update_progress_all()
	var board := _compose_board_sorted()
	if board.is_empty():
		return

	_leader_id  = (board[0]["node"] as Node).get_instance_id()
	_leader_lap = int(board[0]["lap"])
	_leader_s_px= float(board[0]["s_px"])

	_update_rows(board, changed)

# ---------------- UI construction (no prefabs) ----------------
func _build_ui_once() -> void:
	# Root vertical layout so children stack visibly
	var v := VBoxContainer.new()
	v.name = "VBox"
	v.anchor_left = 0.0
	v.anchor_top = 0.0
	v.anchor_right = 1.0
	v.anchor_bottom = 1.0
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(v)

	# Header row
	_header = HBoxContainer.new()
	_header.name = "Header"
	_header.size_flags_horizontal = SIZE_EXPAND_FILL
	_header.size_flags_vertical = SIZE_FILL
	_header.custom_minimum_size.y = 24
	_header.add_theme_constant_override("separation", 6)
	v.add_child(_header)

	# Header labels (fixed widths to align with rows)
	var hp := _make_label("POS", col_place_w, HORIZONTAL_ALIGNMENT_RIGHT)
	_header.add_child(hp)
	var ha := _make_label("Δ", col_arrow_w, HORIZONTAL_ALIGNMENT_CENTER)
	_header.add_child(ha)
	var hn := _make_label("DRIVER", 0, HORIZONTAL_ALIGNMENT_LEFT)
	hn.size_flags_horizontal = SIZE_EXPAND_FILL
	_header.add_child(hn)
	var hl := _make_label("LAP", col_lap_w, HORIZONTAL_ALIGNMENT_CENTER)
	_header.add_child(hl)
	var hs := _make_label("SPEED", col_speed_w, HORIZONTAL_ALIGNMENT_RIGHT)
	_header.add_child(hs)
	var hg := _make_label("GAP", col_gap_w, HORIZONTAL_ALIGNMENT_RIGHT)
	_header.add_child(hg)

	# Divider
	var div := ColorRect.new()
	div.name = "Divider"
	div.color = Color(1, 1, 1, 0.15)
	div.custom_minimum_size = Vector2(0, 2)
	v.add_child(div)

	# Rows holder fills the rest
	_rows_holder = Control.new()
	_rows_holder.name = "Rows"
	_rows_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows_holder.size_flags_vertical = SIZE_EXPAND_FILL
	_rows_holder.clip_contents = true
	v.add_child(_rows_holder)

	# keep row widths synced when container resizes
	if not _rows_holder.is_connected("resized", Callable(self, "_on_rows_holder_resized")):
		_rows_holder.connect("resized", Callable(self, "_on_rows_holder_resized"))

func _make_label(text: String, min_w: int, align: int) -> Label:
	var L := Label.new()
	L.text = text
	L.horizontal_alignment = align
	if min_w > 0:
		L.custom_minimum_size.x = min_w
	return L

func _get_or_make_row(i: int) -> Dictionary:
	while _rows.size() <= i:
		var row := {}

		var holder := Control.new()
		holder.name = "Row_%d" % _rows.size()
		holder.position = Vector2(0, float(_rows.size() * row_height))
		holder.size = Vector2(_rows_holder.size.x, row_height)
		holder.size_flags_horizontal = SIZE_EXPAND_FILL
		_rows_holder.add_child(holder)

		var bg := ColorRect.new()
		bg.name = "BG"
		bg.anchor_right = 1.0
		bg.anchor_bottom = 1.0
		bg.size_flags_horizontal = SIZE_EXPAND_FILL
		bg.size_flags_vertical = SIZE_EXPAND_FILL
		# no ternary: alternate stripe
		if (_rows.size() % 2) == 0:
			bg.color = color_row_even
		else:
			bg.color = color_row_odd
		holder.add_child(bg)

		var H := HBoxContainer.new()
		H.name = "H"
		H.anchor_right = 1.0
		H.anchor_bottom = 1.0
		H.size_flags_horizontal = SIZE_EXPAND_FILL
		H.size_flags_vertical = SIZE_EXPAND_FILL
		H.add_theme_constant_override("separation", 6)
		holder.add_child(H)

		var L_place := _make_label("", col_place_w, HORIZONTAL_ALIGNMENT_RIGHT)
		var L_arrow := _make_label("•", col_arrow_w, HORIZONTAL_ALIGNMENT_CENTER)
		var L_name  := _make_label("", 0, HORIZONTAL_ALIGNMENT_LEFT)
		L_name.size_flags_horizontal = SIZE_EXPAND_FILL
		var L_lap   := _make_label("", col_lap_w, HORIZONTAL_ALIGNMENT_CENTER)
		var L_speed := _make_label("", col_speed_w, HORIZONTAL_ALIGNMENT_RIGHT)
		var L_gap   := _make_label("", col_gap_w, HORIZONTAL_ALIGNMENT_RIGHT)

		H.add_child(L_place)
		H.add_child(L_arrow)
		H.add_child(L_name)
		H.add_child(L_lap)
		H.add_child(L_speed)
		H.add_child(L_gap)

		row["holder"] = holder
		row["bg"]     = bg
		row["place"]  = L_place
		row["arrow"]  = L_arrow
		row["name"]   = L_name
		row["lap"]    = L_lap
		row["speed"]  = L_speed
		row["gap"]    = L_gap

		_rows.append(row)
	return _rows[i]

# ---------------- racers / path ----------------
func _collect_racers() -> void:
	_racers.clear()
	var root := get_node_or_null(racers_root)
	if root == null:
		return
	for c in root.get_children():
		if c is Node and c.has_method("ReturnMapPosition") and c.has_method("ReturnSpriteGraphic"):
			_racers.append(c)
	if _player and not _racers.has(_player):
		_racers.insert(0, _player)

func _rebuild_path_segments() -> void:
	_segments.clear()
	_loop_len_px = 0.0
	var uv_loop := _get_path_points_uv_closed()
	if uv_loop.size() < 2:
		return

	var map_size_px: float = 1024.0
	if _p3d is Sprite2D and (_p3d as Sprite2D).texture != null:
		map_size_px = float((_p3d as Sprite2D).texture.get_size().x)

	for i in range(uv_loop.size() - 1):
		var a: Vector2 = uv_loop[i]
		var b: Vector2 = uv_loop[i + 1]
		var len_px := a.distance_to(b) * map_size_px
		if len_px <= 0.0:
			continue
		_loop_len_px += len_px
		_segments.append({"a_uv":a,"b_uv":b,"len_px":len_px,"cum_px":_loop_len_px})

func _get_path_points_uv_closed() -> PackedVector2Array:
	var pts: PackedVector2Array
	if _p3d != null:
		if _p3d.has_method("GetPathPointsUV"):
			pts = _p3d.call("GetPathPointsUV")
		elif _p3d.has_method("get_path_points_uv"):
			pts = _p3d.call("get_path_points_uv")
		elif _p3d.has_method("ReturnPathPointsUV"):
			pts = _p3d.call("ReturnPathPointsUV")
	if (pts == null or pts.size() == 0) and _overlay != null:
		if _overlay.has_method("get_path_points_uv_transformed"):
			pts = _overlay.call("get_path_points_uv_transformed")
		elif _overlay.has_method("get_path_points_uv"):
			pts = _overlay.call("get_path_points_uv")
	if pts == null:
		return PackedVector2Array()

	if pts.size() >= 2:
		var a := pts[0]
		var b := pts[pts.size() - 1]
		if not a.is_equal_approx(b):
			var out := PackedVector2Array()
			for i in range(pts.size()):
				out.append(pts[i])
			out.append(a)
			return out
	return pts

# ---------------- standings math ----------------
func _seed_progress() -> void:
	_progress.clear()
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var s := _sample_s_of(r)
		var id := (r as Node).get_instance_id()
		_progress[id] = {"lap": 0, "s_px": s, "prev_s_px": s}

func _update_progress_all() -> bool:
	if _segments.is_empty():
		return false
	var changed := false
	var half := _loop_len_px * 0.5
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := (r as Node).get_instance_id()
		if not _progress.has(id):
			_progress[id] = {"lap": 0, "s_px": 0.0, "prev_s_px": 0.0}

		var prev_s := float(_progress[id]["s_px"])
		var s := _sample_s_of(r)
		var lap := int(_progress[id]["lap"])

		var ds := s - prev_s
		if ds < -half:
			lap += 1
		elif ds > half:
			lap = max(0, lap - 1)

		if s != prev_s or lap != int(_progress[id]["lap"]):
			changed = true

		_progress[id]["prev_s_px"] = prev_s
		_progress[id]["s_px"] = s
		_progress[id]["lap"] = lap
	return changed

func _compose_board_sorted() -> Array:
	var board: Array = []
	for r in _racers:
		if not is_instance_valid(r):
			continue
		var id := (r as Node).get_instance_id()
		board.append({
			"node": r,
			"lap":  int(_progress[id]["lap"]),
			"s_px": float(_progress[id]["s_px"])
		})

	board.sort_custom(func(a, b):
		var al := int(a["lap"])
		var bl := int(b["lap"])
		if al != bl:
			return al > bl
		var asx := float(a["s_px"])
		var bsx := float(b["s_px"])
		if asx != bsx:
			return asx > bsx
		var ay := _screen_y_of(a["node"] as Node)
		var by := _screen_y_of(b["node"] as Node)
		return ay > by
	)

	for i in range(board.size()):
		board[i]["place"] = i + 1
	return board

func _screen_y_of(r: Node) -> float:
	if r.has_method("ReturnScreenPosition"):
		var v: Vector2 = r.call("ReturnScreenPosition")
		return v.y
	var spr = r.call("ReturnSpriteGraphic")
	if spr != null:
		return (spr as Node2D).global_position.y
	return 0.0

func _sample_s_of(r: Node) -> float:
	if _segments.is_empty():
		return 0.0
	var map_size_px: float = 1024.0
	if _p3d is Sprite2D and (_p3d as Sprite2D).texture != null:
		map_size_px = float((_p3d as Sprite2D).texture.get_size().x)

	var p3: Vector3 = r.call("ReturnMapPosition")
	var uv := Vector2(p3.x / map_size_px, p3.z / map_size_px)

	# fast pass
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
			return before + t * float(seg["len_px"])

	# fallback
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
			best_s = cum_prev + t2 * L
		cum_prev += L
	return best_s

# ---------------- UI updates ----------------
func _draw_initial_board() -> void:
	var board := _compose_board_sorted()
	if board.is_empty():
		return
	_update_rows(board, true)

func _update_rows(board: Array, reordering_changed: bool) -> void:
	var count = min(max_rows, board.size())

	# build/resize row widgets as needed
	for i in range(count):
		_get_or_make_row(i)

	# position + fill each row
	for i in range(count):
		var it: Dictionary = board[i]
		var racer: Node = it["node"]
		var id := racer.get_instance_id()
		var place := int(it["place"])
		var lap := int(it["lap"])
		var s_px := float(it["s_px"])

		# assign this racer to a row index
		_row_owner_for_id[id] = i

		# animate to slot
		var holder: Control = _rows[i]["holder"]
		var target_y := float(i * row_height)
		if abs(holder.position.y - target_y) >= 0.5:
			# tween per row index
			if _tweens.has(i):
				var old: Tween = _tweens[i]
				if old: old.kill()
			var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(holder, "position:y", target_y, animate_time)
			_tweens[i] = tw
		else:
			holder.position.y = target_y

		# name + base text
		var L_name: Label = _rows[i]["name"]
		L_name.text = racer.name

		var L_place: Label = _rows[i]["place"]
		var prev_place := 0
		if _prev_place_for_id.has(id):
			prev_place = int(_prev_place_for_id[id])
		_prev_place_for_id[id] = place
		L_place.text = str(place)

		# arrow + flash
		var L_arrow: Label = _rows[i]["arrow"]
		var bg: ColorRect = _rows[i]["bg"]

		if reordering_changed and prev_place != 0 and prev_place != place:
			var gained := place < prev_place
			if gained:
				L_arrow.text = "↑"
				bg.color = color_gain
			else:
				L_arrow.text = "↓"
				bg.color = color_loss

			var tw2 := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw2.tween_property(bg, "color:a", 0.0, 0.45).from(0.90)
			tw2.tween_callback(func ():
				# restore row stripe or player highlight
				if _player != null and racer == _player:
					bg.color = color_player_bg
				else:
					if (i % 2) == 0:
						bg.color = color_row_even
					else:
						bg.color = color_row_odd
			)
		else:
			L_arrow.text = "•"
			# ensure background is proper (player highlight or stripe)
			if _player != null and racer == _player:
				bg.color = color_player_bg
			else:
				if (i % 2) == 0:
					bg.color = color_row_even
				else:
					bg.color = color_row_odd

		# lap
		var L_lap: Label = _rows[i]["lap"]
		L_lap.text = "Lap " + str(lap + 1)

		# speed
		var speed := 0.0
		if racer.has_method("ReturnMovementSpeed"):
			speed = float(racer.call("ReturnMovementSpeed"))
		var L_speed: Label = _rows[i]["speed"]
		L_speed.text = String.num(speed, 0) + " u/s"

		# gap vs leader
		var gap_s := _gap_seconds_for(id, lap, s_px, speed)
		var L_gap: Label = _rows[i]["gap"]
		if gap_s <= 0.01:
			L_gap.text = "—"
		else:
			L_gap.text = "+" + String.num(gap_s, 2) + "s"

	# hide any extra prebuilt rows if your max_rows shrank
	for j in range(count, _rows.size()):
		var h := _rows[j]["holder"] as Control
		h.visible = false

func _gap_seconds_for(id: int, lap: int, s_px: float, speed: float) -> float:
	if id == _leader_id:
		return 0.0
	var dlaps := _leader_lap - lap
	var dpx := (_leader_s_px - s_px) + float(dlaps) * _loop_len_px
	var denom = max(speed, 1.0)
	return abs(dpx) / denom

func _on_rows_holder_resized() -> void:
	# keep each row the full width, and reflow their heights if row_height changed
	for i in range(_rows.size()):
		var holder: Control = _rows[i]["holder"]
		holder.size.x = _rows_holder.size.x
		holder.size.y = row_height
		# also ensure the row’s y matches its index (in case fonts changed height)
		var target_y := float(i * row_height)
		if abs(holder.position.y - target_y) > 0.5:
			holder.position.y = target_y
