extends Node2D
# Opponent that follows a closed UV (0..1) loop and projects with the same matrix as the track.

# ---- Path source ----
@export_node_path("Node2D") var path_overlay_uv: NodePath              # assign your PathOverlayUV node (inside SubViewport)
@export var fallback_points_uv: PackedVector2Array = PackedVector2Array()  # optional: fill in Inspector to test without overlay

# ---- Movement tuning ----
@export var speed_px_per_sec: float = 160.0
@export var lookahead_px: float = 24.0
@export var start_offset_px: float = 0.0

# ---- Render / depth / facing ----
@export var z_index_on_top: int = 500
@export var face_along_path: bool = true

# ---- Visual sprite scaling (perspective) ----
@export_node_path("Sprite2D") var gfx_path: NodePath                   # assign your Sprite2D child (e.g., "GFX")
@export var size_k: float = 0.9                                        # scale numerator; tweak for camera pitch
@export var size_min: float = 0.35                                     # min scale clamp
@export var size_max: float = 2.0                                      # max scale clamp

# ---- Orientation fix ----
@export var invert_uv_y: bool = true   # flip UV.y if your path appears upside-down

# ---- Internals ----
var _world_matrix: Basis = Basis()          # must match shader mapMatrix
var _screen_size: Vector2 = Vector2.ZERO

var _pts_uv: Array[Vector2] = []            # UV points (0..1), closed
var _cumlen_px: PackedFloat32Array = []     # cumulative arc length (texture pixels)
var _total_len_px: float = 0.0
var _s_px: float = 0.0

func _ready() -> void:
	visible = true
	set_z_as_relative(false)
	z_index = z_index_on_top

	# screen size fallback so we don't sit at (0,0) if set_world_and_screen isn't called yet
	_screen_size = get_viewport_rect().size
	if _screen_size == Vector2.ZERO:
		_screen_size = Vector2(1280, 720)
		push_warning("[AI] screen_size was ZERO; using 1280x720 fallback")

	_load_path_uv()
	if _pts_uv.size() < 2:
		_build_fallback_loop()
		print("[AI] Using internal fallback UV loop (no overlay path).")
	_close_if_needed()
	_build_lengths()
	_s_px = fposmod(start_offset_px, max(1.0, _total_len_px))
	print("[AI] Init: pts=%d len_px=%.1f screen=%s" % [_pts_uv.size(), _total_len_px, str(_screen_size)])

func _physics_process(delta: float) -> void:
	if _total_len_px <= 1.0:
		return
	_s_px = fposmod(_s_px + speed_px_per_sec * delta, _total_len_px)
	_place_racer_at_s(_s_px)
	queue_redraw()  # draws a red dot so you can see the node even without a sprite

# Feed same matrix+screen as shader each frame (from Pseudo3D.Update)
func set_world_and_screen(m: Basis, screen_size: Vector2) -> void:
	_world_matrix = m
	_screen_size = screen_size

# ---------------- path ingest ----------------
func _load_path_uv() -> void:
	_pts_uv.clear()
	var src := get_node_or_null(path_overlay_uv)
	if src and src.has_method("get_path_points_uv"):
		var arr: PackedVector2Array = src.call("get_path_points_uv")
		for p in arr:
			_pts_uv.append(p)
		print("[AI] Loaded UV points from overlay:", _pts_uv.size())
	elif fallback_points_uv.size() > 1:
		for p in fallback_points_uv:
			_pts_uv.append(p)
		print("[AI] Loaded UV points from fallback_points_uv:", _pts_uv.size())

func _build_fallback_loop() -> void:
	# 32-point rounded loop in UV space; guaranteed movement even if overlay not wired
	var uv := PackedVector2Array()
	for i in range(32):
		var t := float(i) / 32.0 * TAU
		var r := 0.35 + 0.05 * sin(3.0 * t)
		var p := Vector2(0.5, 0.5) + Vector2(cos(t), sin(t)) * r
		uv.append(p.clamp(Vector2(0.05,0.05), Vector2(0.95,0.95)))
	fallback_points_uv = uv
	_pts_uv.clear()
	for p in uv:
		_pts_uv.append(p)

func _close_if_needed() -> void:
	if _pts_uv.size() >= 2:
		var a: Vector2 = _pts_uv[0]
		var b: Vector2 = _pts_uv[_pts_uv.size()-1]
		if a.distance_to(b) > (1.0/1024.0):
			_pts_uv.append(a)

func _build_lengths() -> void:
	_cumlen_px.clear()
	_total_len_px = 0.0
	if _pts_uv.size() < 2:
		return
	_cumlen_px.resize(_pts_uv.size())
	_cumlen_px[0] = 0.0
	for i in range(_pts_uv.size()-1):
		var pa := _pts_uv[i] * 1024.0
		var pb := _pts_uv[i+1] * 1024.0
		_total_len_px += pa.distance_to(pb)
		_cumlen_px[i+1] = _total_len_px

# ---------------- movement / projection ----------------
func _sample_uv_at_s(s_px: float) -> Vector2:
	if _pts_uv.size() < 2:
		return Vector2(0.5, 0.5)
	var s := fposmod(s_px, _total_len_px)
	var i := 0
	while i < _cumlen_px.size()-1 and _cumlen_px[i+1] < s:
		i += 1
	var a_uv := _pts_uv[i]
	var b_uv := _pts_uv[i+1]
	var a := _cumlen_px[i]
	var b := _cumlen_px[i+1]
	var t = (s - a) / max(0.0001, b - a)
	return a_uv.lerp(b_uv, t)

func _place_racer_at_s(s_px: float) -> void:
	var uv := _sample_uv_at_s(s_px)
	var uv_ahead := _sample_uv_at_s(s_px + lookahead_px)

	# --- UV orientation fix ---
	if invert_uv_y:
		uv.y = 1.0 - uv.y
		uv_ahead.y = 1.0 - uv_ahead.y

	# UV -> centered map units (UV - 0.5), same as shader
	var mp := uv - Vector2(0.5, 0.5)
	var mp2 := uv_ahead - Vector2(0.5, 0.5)

	# Inverse projection basis (safe default = identity)
	var inv: Basis
	if _world_matrix == Basis():
		inv = Basis.IDENTITY
	else:
		inv = _world_matrix.inverse()

	# Project to clip/screen
	var w := inv * Vector3(mp.x, mp.y, 1.0)
	if w.z <= 0.0:
		visible = false
		return
	visible = true

	var scr := Vector2(w.x / w.z, w.y / w.z)
	global_position = (scr + Vector2(0.5, 0.5)) * _screen_size

	# Depth sort
	z_index = int(clamp(w.z * 1000.0, -200000.0, 200000.0))

	# Perspective sprite scale (1/z)
	var s = clamp(size_k / w.z, size_min, size_max)
	var gfx := get_node_or_null(gfx_path)
	if gfx and gfx.has_method("set_scale"):
		gfx.scale = Vector2(s, s)

	# Face along the path tangent (screen-projected)
	if face_along_path:
		var w2 := inv * Vector3(mp2.x, mp2.y, 1.0)
		if w2.z > 0.0:
			var scr2 := Vector2(w2.x / w2.z, w2.y / w2.z)
			var dir := ((scr2 + Vector2(0.5, 0.5)) * _screen_size) - global_position
			if dir.length() > 0.001:
				rotation = dir.angle()

# ---------------- debug ----------------
func _draw() -> void:
	draw_circle(Vector2.ZERO, 6.0, Color(1,0,0,1))
