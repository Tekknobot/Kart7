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
@export var path_width: float = 2.0

@export var dot_color := Color(0.20, 0.75, 1.00, 1.0)   # AI / others
@export var player_dot_color := Color(1.00, 0.95, 0.20, 1.0)
@export var lapped_dot_color := Color(1.00, 0.45, 0.45, 1.0)  # optional (unused unless you set lapped ids)

@export var dot_radius: float = 3.0
@export var player_dot_radius: float = 5.0

@export var padding_px: float = 6.0                        # frame padding inside this panel
@export var flip_y: bool = true                            # UI coords often want Y flipped vs map UV

# Update throttling (for very large racer counts):
@export var update_stride_frames: int = 1                  # 1 = every frame, 2 = every other, etc.

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

# ---------- Drawing ----------
func _draw() -> void:
	# Path
	if _uv_loop.size() >= 2:
		var prev := _uv_to_panel(_uv_loop[0])
		for i in range(1, _uv_loop.size()):
			var cur := _uv_to_panel(_uv_loop[i])
			draw_line(prev, cur, path_color, path_width, true)
			prev = cur

	# Dots (racers)
	if _root != null:
		for r in _root.get_children():
			if not (r is Node):
				continue
			if not r.has_method("ReturnMapPosition"):
				continue

			var p3: Vector3 = r.call("ReturnMapPosition")
			var uv: Vector2 = _pos3_to_uv(p3)
			var p: Vector2 = _uv_to_panel(uv)

			var id := r.get_instance_id()
			var is_player := (_player != null and r == _player)
			var col := player_dot_color if is_player else (lapped_dot_color if _lapped_ids.has(id) else dot_color)
			var rad := player_dot_radius if is_player else dot_radius

			draw_circle(p, rad, col)
