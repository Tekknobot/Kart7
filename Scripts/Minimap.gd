extends Control
class_name Minimap

# ---------- Scene references (optional) ----------
@export var path_provider: NodePath        # PathOverlay2D or Map (Pseudo3D). Optional—can be bound at runtime.
@export var racers_root: NodePath          # Optional—can be bound at runtime. If empty we scan group "racers".
@export var player_path: NodePath          # Optional—can be bound at runtime. We'll also try group "player".
@export var map_size_px: int = 1024        # px width used when positions are in pixels

# ---------- Appearance ----------
@export var path_color := Color(1, 1, 1, 0.9)
@export var path_width: int = 1
@export var pixel_lines: bool = true
@export var pixel_snap: bool = true

@export var resample_step_px: float = 6.0
@export var smooth_iterations: int = 0

@export var dot_color := Color(0.20, 0.75, 1.00, 1.0)     # others
@export var player_dot_color := Color(1.00, 0.95, 0.20, 1.0)
@export var lapped_dot_color := Color(1.00, 0.45, 0.45, 1.0)

@export var dot_radius: float = 3.0
@export var player_dot_radius: float = 5.0

@export var padding_px: float = 6.0
@export var flip_y: bool = true

@export var update_stride_frames: int = 1

@export var pixel_dots: bool = true
@export var dot_square_size: int = 3     # odd (3,5,…)
@export var player_square_size: int = 5  # odd

# ---------- Internals ----------
var _provider: Node = null
var _root: Node = null
var _player: Node = null
var _uv_loop: PackedVector2Array = PackedVector2Array()  # closed UV loop
var _uv_loop_dirty := true
var _frame := 0

# optional: ids to render in the lapped color (fill from Leaderboard if desired)
var _lapped_ids := {}  # {instance_id: true}

# ---------- Public API (World can call this once after spawn) ----------
func Bind(player: Node, racers_root_node: Node, provider_node: Node) -> void:
	_player = player
	_root = racers_root_node
	_provider = provider_node
	_uv_loop_dirty = true
	_fetch_uv_loop()
	queue_redraw()

func set_lapped_ids(ids: Array) -> void:
	_lapped_ids.clear()
	for i in ids:
		_lapped_ids[int(i)] = true

# ---------- Lifecycle ----------
func _ready() -> void:
	_provider = get_node_or_null(path_provider)
	_root = get_node_or_null(racers_root)
	_player = get_node_or_null(player_path)
	set_process(true)
	if not is_connected("resized", Callable(self, "_on_resized")):
		connect("resized", Callable(self, "_on_resized"))
	_fetch_uv_loop()
	queue_redraw()

func _on_resized() -> void:
	queue_redraw()

func _process(_dt: float) -> void:
	_frame += 1
	if _frame % max(1, update_stride_frames) != 0:
		return

	_lazy_bind()

	if _uv_loop_dirty:
		_fetch_uv_loop()

	queue_redraw()

# ---------- Lazy binding for prefabs ----------
func _lazy_bind() -> void:
	if _provider == null:
		# 1) Exported path
		_provider = get_node_or_null(path_provider)
	# 2) Common scene search (PathOverlay2D in a SubViewport)
	if _provider == null:
		var cand := get_tree().get_root().find_child("PathOverlay2D", true, false)
		if cand != null:
			_provider = cand
			_uv_loop_dirty = true
	# 3) Map (Pseudo3D) can also provide UV points
	if _provider == null:
		var m := get_tree().get_root().find_child("Map", true, false)
		if m != null:
			_provider = m
			_uv_loop_dirty = true

	if _root == null:
		_root = get_node_or_null(racers_root)

	if _player == null:
		_player = get_node_or_null(player_path)
		if _player == null:
			# Try group "player"
			var p := get_tree().get_first_node_in_group("player")
			if p != null:
				_player = p
		# As a last resort, pick the racer whose name matches Globals.selected_racer
		if _player == null:
			var rr := _scan_racers()
			var want := ""
			if "selected_racer" in Globals:
				want = String(Globals.selected_racer)
			for r in rr:
				if r.name == want:
					_player = r
					break

# ---------- Data fetch ----------
func _fetch_uv_loop() -> void:
	_uv_loop = PackedVector2Array()
	if _provider != null:
		# Preferred: PathOverlay2D
		if _provider.has_method("get_path_points_uv_transformed"):
			_uv_loop = _provider.call("get_path_points_uv_transformed")
		elif _provider.has_method("get_path_points_uv"):
			_uv_loop = _provider.call("get_path_points_uv")
		# Map (Pseudo3D) fallback
		elif _provider.has_method("GetPathPointsUV"):
			_uv_loop = _provider.call("GetPathPointsUV")
		elif _provider.has_method("ReturnPathPointsUV"):
			_uv_loop = _provider.call("ReturnPathPointsUV")

	# ensure closed
	if _uv_loop.size() >= 2:
		var a := _uv_loop[0]
		var b := _uv_loop[_uv_loop.size() - 1]
		if not a.is_equal_approx(b):
			_uv_loop.append(a)

	_uv_loop_dirty = false

# ---------- Helpers ----------
func _scan_racers() -> Array:
	# Prefer exported root; otherwise scan the "racers" group
	if _root != null:
		return _root.get_children()
	return get_tree().get_nodes_in_group("racers")

# Convert a racer map position (Vector3) to UV (0..1)
func _pos3_to_uv(p3: Vector3) -> Vector2:
	var ax = abs(p3.x)
	var az = abs(p3.z)
	if ax <= 2.0 and az <= 2.0:
		return Vector2(p3.x, p3.z)  # already UV
	var denom := float(max(1, map_size_px))
	return Vector2(p3.x / denom, p3.z / denom)

# Fit UV to panel with padding, preserving aspect
func _uv_to_panel(uv: Vector2) -> Vector2:
	var rect := Rect2(Vector2(padding_px, padding_px), size - Vector2(padding_px * 2.0, padding_px * 2.0))
	var w := rect.size.x
	var h := rect.size.y
	var s = min(w, h)
	var off := rect.position + Vector2((w - s) * 0.5, (h - s) * 0.5)

	var u := uv.x
	var v := uv.y
	if flip_y:
		v = 1.0 - v
	return off + Vector2(u * s, v * s)

func _odd(n: int) -> int:
	return n if (n % 2) != 0 else n + 1

func _draw_pixel_square(center: Vector2, size_px: int, col: Color) -> void:
	var s = max(1, _odd(size_px))
	var cx := int(round(center.x))
	var cy := int(round(center.y))
	var half = (s - 1) / 2
	var top_left := Vector2(cx - half, cy - half)
	draw_rect(Rect2(top_left, Vector2(s, s)), col, true)

# ---------- Drawing ----------
func _draw() -> void:
	# Path
	if _uv_loop.size() >= 2:
		var pts := _resampled_panel_points(_uv_loop, resample_step_px, smooth_iterations)
		if pts.size() >= 2:
			draw_polyline(pts, path_color, float(path_width), false)

	# Racers
	var racers := _scan_racers()
	for r in racers:
		if not (r is Node) or not r.has_method("ReturnMapPosition"):
			continue
		var p3: Vector3 = r.call("ReturnMapPosition")
		var uv: Vector2 = _pos3_to_uv(p3)
		var p: Vector2 = _uv_to_panel(uv)

		var id = r.get_instance_id()
		var is_player = (_player != null and r == _player)

		var col := dot_color
		if is_player:
			col = player_dot_color
		elif _lapped_ids.has(id):
			col = lapped_dot_color

		if pixel_dots:
			var s := player_square_size if is_player else dot_square_size
			_draw_pixel_square(p, s, col)
		else:
			var rad := player_dot_radius if is_player else dot_radius
			draw_circle(p, rad, col)

# --- resampling / smoothing ---
func _resampled_panel_points(uv_loop: PackedVector2Array, step_px: float, smooth_iters: int) -> PackedVector2Array:
	var N := uv_loop.size()
	if N < 2:
		return PackedVector2Array()

	# to panel space
	var panel_pts := PackedVector2Array()
	panel_pts.resize(N)
	for i in range(N):
		panel_pts[i] = _uv_to_panel(uv_loop[i])

	if smooth_iters > 0 and not pixel_lines:
		panel_pts = _chaikin(panel_pts, clamp(smooth_iters, 0, 4))

	var out: PackedVector2Array
	if step_px > 0.0:
		out = _resample_even(panel_pts, step_px)
	else:
		out = panel_pts

	if pixel_snap:
		for i in range(out.size()):
			var p := out[i]
			out[i] = Vector2(floor(p.x) + 0.5, floor(p.y) + 0.5)

	return out

func _resample_even(panel_pts: PackedVector2Array, step_px: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.append(panel_pts[0])
	var acc := 0.0
	for i in range(1, panel_pts.size()):
		var a := panel_pts[i - 1]
		var b := panel_pts[i]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.0001:
			continue
		var t := step_px - acc
		while t <= seg_len:
			var p := a.lerp(b, t / seg_len)
			out.append(p)
			t += step_px
		acc = seg_len - (t - step_px)
	if out.size() == 0 or out[out.size() - 1] != panel_pts[panel_pts.size() - 1]:
		out.append(panel_pts[panel_pts.size() - 1])
	return out

func _chaikin(src: PackedVector2Array, iters: int) -> PackedVector2Array:
	var pts := src
	for _i in range(iters):
		if pts.size() < 3:
			break
		var dst := PackedVector2Array()
		dst.append(pts[0])
		for k in range(0, pts.size() - 1):
			var p := pts[k]
			var q := pts[k + 1]
			var Q := p * 0.75 + q * 0.25
			var R := p * 0.25 + q * 0.75
			dst.append(Q)
			dst.append(R)
		dst.append(pts[pts.size() - 1])
		pts = dst
	return pts
