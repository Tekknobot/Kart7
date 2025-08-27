# Scripts/UI/Minimap.gd
extends Control
class_name Minimap

# ---------- Scene references ----------
@export var path_provider: NodePath               # PathOverlay2D or any node with get_path_points_uv_transformed()/get_path_points_uv()
@export var racers_root: NodePath                 # root that contains racer nodes
@export var player_path: NodePath                 # player node (for highlight)
@export var map_size_px: int = 1024               # used to normalize pixel coords -> UV when needed

# ---------- Appearance ----------
@export var path_color := Color(1, 1, 1, 0.9)
@export var path_width: int = 1                   # integer width helps the pixel look
@export var pixel_lines: bool = true              # NEW: render path as crisp pixels
@export var pixel_snap: bool = true               # NEW: snap vertices to pixel grid

@export var resample_step_px: float = 6.0
@export var smooth_iterations: int = 0            # keep corners; smoothing rounds pixels


@export var dot_color := Color(0.20, 0.75, 1.00, 1.0)   # AI / others
@export var player_dot_color := Color(1.00, 0.95, 0.20, 1.0)
@export var lapped_dot_color := Color(1.00, 0.45, 0.45, 1.0)  # optional (unused unless you set lapped ids)

@export var dot_radius: float = 3.0
@export var player_dot_radius: float = 5.0

@export var padding_px: float = 6.0                        # frame padding inside this panel
@export var flip_y: bool = true                            # UI coords often want Y flipped vs map UV

# Update throttling (for very large racer counts):
@export var update_stride_frames: int = 1                  # 1 = every frame, 2 = every other, etc.

@export var pixel_dots: bool = true     # draw chunky pixel dots
@export var dot_square_size: int = 3    # odd number (3,5,7…)
@export var player_square_size: int = 5 # odd number (3,5,7…)

# ---------- Internals ----------
var _provider: Node = null
var _root: Node = null
var _player: Node = null
var _uv_loop: PackedVector2Array = PackedVector2Array()    # closed UV path
var _uv_loop_dirty := true
var _last_panel_size: Vector2 = Vector2.ZERO
var _frame := 0

# optional: ids to render in the lapped color (fill from your Leaderboard if you want)
var _lapped_ids: = {}  # {instance_id: true}

func _ready() -> void:
	_provider = get_node_or_null(path_provider)
	_root = get_node_or_null(racers_root)
	_player = get_node_or_null(player_path)

	set_process(true)
	if not is_connected("resized", Callable(self, "_on_resized")):
		connect("resized", Callable(self, "_on_resized"))

	# try to fetch once now
	_fetch_uv_loop()
	queue_redraw()

func _on_resized() -> void:
	_last_panel_size = size
	queue_redraw()

func _process(_dt: float) -> void:
	_frame += 1
	if _frame % max(1, update_stride_frames) != 0:
		return

	# The path rarely changes, so fetch only when dirty or provider swapped
	if _uv_loop_dirty or _provider == null:
		_provider = get_node_or_null(path_provider)
		_fetch_uv_loop()

	# redraw whenever we update dots
	queue_redraw()

# ---------- Public helpers ----------
# If you want to mark lapped cars to draw in a different color:
func set_lapped_ids(ids: Array) -> void:
	_lapped_ids.clear()
	for i in ids:
		_lapped_ids[int(i)] = true

# ---------- Core ----------
func _fetch_uv_loop() -> void:
	_uv_loop = PackedVector2Array()
	if _provider != null:
		if _provider.has_method("get_path_points_uv_transformed"):
			_uv_loop = _provider.call("get_path_points_uv_transformed")
		elif _provider.has_method("get_path_points_uv"):
			_uv_loop = _provider.call("get_path_points_uv")
	# ensure closed
	if _uv_loop.size() >= 2:
		var a := _uv_loop[0]
		var b := _uv_loop[_uv_loop.size() - 1]
		if a.distance_to(b) > 0.00001:
			_uv_loop.append(a)
	_uv_loop_dirty = false

# Convert a racer map position (Vector3) to UV (0..1 on both axes)
func _pos3_to_uv(p3: Vector3) -> Vector2:
	var ax = abs(p3.x)
	var az = abs(p3.z)
	if ax <= 2.0 and az <= 2.0:
		# likely already UVs
		return Vector2(p3.x, p3.z)
	# pixels -> UV
	var denom := float(max(1, map_size_px))
	return Vector2(p3.x / denom, p3.z / denom)

# Fit UV in [0..1] to panel rect with padding, preserving aspect
func _uv_to_panel(uv: Vector2) -> Vector2:
	var rect := Rect2(Vector2(padding_px, padding_px), size - Vector2(padding_px * 2.0, padding_px * 2.0))
	var w := rect.size.x
	var h := rect.size.y

	# preserve aspect: letterbox/pillarbox in the smaller dimension
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
	# snap to integer pixel center for crisp fill
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
			# One AA call for the whole loop gives better continuity than many draw_line calls
			draw_polyline(pts, path_color, float(path_width), false)

	# Dots (racers)
	if _root != null:
		for r in _root.get_children():
			if not (r is Node) or not r.has_method("ReturnMapPosition"):
				continue

			var p3: Vector3 = r.call("ReturnMapPosition")
			var uv: Vector2 = _pos3_to_uv(p3)
			var p: Vector2 = _uv_to_panel(uv)

			var id := r.get_instance_id()
			var is_player := (_player != null and r == _player)
			var col := player_dot_color if is_player else (lapped_dot_color if _lapped_ids.has(id) else dot_color)

			if pixel_dots:
				var s := player_square_size if is_player else dot_square_size
				_draw_pixel_square(p, s, col)
			else:
				var rad := player_dot_radius if is_player else dot_radius
				draw_circle(p, rad, col)


# Resample + (optional) smooth the UV loop in panel space for crisp strokes
func _resampled_panel_points(uv_loop: PackedVector2Array, step_px: float, smooth_iters: int) -> PackedVector2Array:
	var N := uv_loop.size()
	if N < 2:
		return PackedVector2Array()

	# 1) Map to panel space
	var panel_pts := PackedVector2Array()
	panel_pts.resize(N)
	for i in range(N):
		panel_pts[i] = _uv_to_panel(uv_loop[i])

	# 2) Optional (disable for pixel look)
	if smooth_iters > 0 and not pixel_lines:
		panel_pts = _chaikin(panel_pts, clamp(smooth_iters, 0, 4))

	# 3) Resample (optional)
	var out: PackedVector2Array
	if step_px > 0.0:
		out = _resample_even(panel_pts, step_px)
	else:
		out = panel_pts

	# 4) SNAP TO PIXELS (crucial for crisp 1px lines)
	if pixel_snap:
		# Align to pixel centers: floor(x) + 0.5 to reduce half-pixel blur for width=1
		for i in range(out.size()):
			var p := out[i]
			out[i] = Vector2(floor(p.x) + 0.5, floor(p.y) + 0.5)

	return out

# helper extracted from your current resampling body (unchanged logic)
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

# Chaikin corner-cutting (simple curve smoothing)
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
