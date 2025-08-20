extends Node2D
# Opponent that follows a closed UV (0..1) loop and projects with the same matrix as the track.

# =========================
# Constants
# =========================
const TAU := PI * 2.0

# =========================
# Path source
# =========================
@export_node_path("Node2D") var path_overlay_uv: NodePath
@export var fallback_points_uv: PackedVector2Array = PackedVector2Array()

# =========================
# Movement tuning
# =========================
@export var speed_px_per_sec: float = 160.0
@export var lookahead_px: float = 24.0
@export var start_offset_px: float = 0.0
@export var start_at_first_point: bool = true

# =========================
# Render / depth / facing
# =========================
@export var z_index_on_top: int = 500
@export var face_along_path: bool = true

# =========================
# Sprite sheet framing (single row)
# =========================
@export_node_path("Sprite2D") var gfx_path: NodePath
@export var frames_per_row: int = 12
@export var frame_w: int = 32
@export var frame_h: int = 32
@export var straight_index: int = 0
@export var reverse_angle: bool = false
@export var angle_bias_deg: float = 0.0
@export var turn_increases_to_right: bool = true

# =========================
# Visual sprite scaling (choose ONE method)
# =========================
# A) Simple, robust: scale ~ 1/z (Mode-7 feel)
@export var use_depth_scale: bool = true
@export var depth_size_k: float = 0.9     # overall size knob for depth scaling
@export var invert_depth: bool = false    # set true if your z grows when NEARER

# B) Optional: Jacobian-based (map-space pixel density) -- used if use_depth_scale=false
@export var kart_height_map: float = 0.26

# Common clamps
@export var size_min: float = 0.9
@export var size_max: float = 8.0
@export var anchor_bottom: bool = true

# =========================
# Optional orientation / axis fixes
# =========================
@export var invert_uv_y: bool = true
@export var swap_xy: bool = false
@export var invert_x: bool = false
@export var invert_y: bool = false

# =========================
# Debug
# =========================
@export var preview_mode := true
@export var debug := true
@export var debug_dot: bool = false

# =========================
# Internals
# =========================
var _world_matrix: Basis = Basis()
var _screen_size: Vector2 = Vector2.ZERO

var _pts_uv: Array[Vector2] = []
var _cumlen_px: PackedFloat32Array = PackedFloat32Array()
var _total_len_px: float = 0.0
var _s_px: float = 0.0

var _cam_forward: Vector2 = Vector2(0.0, 1.0)
var _dbg_accum := 0.0

# =========================
# Lifecycle
# =========================
func _ready() -> void:
	visible = true
	set_z_as_relative(false)
	z_index = z_index_on_top

	_screen_size = get_viewport_rect().size
	if _screen_size == Vector2.ZERO:
		_screen_size = Vector2(1280, 720)
		if debug:
			push_warning("[AI] screen_size was ZERO; using 1280x720 fallback")

	_ensure_sprite_setup()
	_load_path_uv()
	if _pts_uv.size() < 2:
		_build_fallback_loop()
		if debug:
			print("[AI] Using internal fallback UV loop (no overlay path).")
	_close_if_needed()
	_build_lengths()

	if start_at_first_point and _total_len_px > 0.0:
		_s_px = 0.0
	else:
		var denom := _total_len_px
		if denom < 1.0:
			denom = 1.0
		_s_px = fposmod(start_offset_px, denom)

	_place_racer_at_s(_s_px)

	if debug:
		print("[AI] Init: pts=", _pts_uv.size(), " len_px=", _total_len_px, " screen=", _screen_size)

func _physics_process(delta: float) -> void:
	if _total_len_px <= 1.0:
		return
	_s_px = fposmod(_s_px + speed_px_per_sec * delta, _total_len_px)
	_place_racer_at_s(_s_px)

	if debug:
		_dbg_accum += delta
		if _dbg_accum >= 1.0:
			_dbg_accum = 0.0
			var gfx := get_node_or_null(gfx_path)
			if gfx is Node2D:
				print("[AI] s=", int(_s_px), "/", int(_total_len_px), " scale=", (gfx as Node2D).scale)

	if debug_dot:
		queue_redraw()

# =========================
# External API (from Pseudo3D)
# =========================
func set_world_and_screen(m: Basis, screen_size: Vector2) -> void:
	_world_matrix = m
	_screen_size = screen_size

func set_points_uv(p: PackedVector2Array) -> void:
	_pts_uv.clear()
	for q in p:
		_pts_uv.append(q)
	_close_if_needed()
	_build_lengths()
	if debug:
		print("[AI] got UVs:", _pts_uv.size(), " len_px:", _total_len_px)
	if start_at_first_point and _total_len_px > 0.0:
		_s_px = 0.0
	else:
		var denom := _total_len_px
		if denom < 1.0:
			denom = 1.0
		_s_px = fposmod(start_offset_px, denom)
	_place_racer_at_s(_s_px)

func set_camera_forward(v: Vector2) -> void:
	if v.length() > 0.0:
		_cam_forward = v.normalized()

# =========================
# Path ingest
# =========================
func _load_path_uv() -> void:
	_pts_uv.clear()
	var src := get_node_or_null(path_overlay_uv)
	if src != null and src.has_method("get_path_points_uv"):
		var arr: PackedVector2Array = src.call("get_path_points_uv")
		for p in arr:
			_pts_uv.append(p)
		if debug:
			print("[AI] Loaded UV points from overlay:", _pts_uv.size())
	elif fallback_points_uv.size() > 1:
		for p in fallback_points_uv:
			_pts_uv.append(p)
		if debug:
			print("[AI] Loaded UV points from fallback_points_uv:", _pts_uv.size())

func _build_fallback_loop() -> void:
	var uv := PackedVector2Array()
	var i := 0
	while i < 32:
		var t := float(i) / 32.0 * TAU
		var r := 0.35 + 0.05 * sin(3.0 * t)
		var p := Vector2(0.5, 0.5) + Vector2(cos(t), sin(t)) * r
		var minv := Vector2(0.05, 0.05)
		var maxv := Vector2(0.95, 0.95)
		p = p.clamp(minv, maxv)
		uv.append(p)
		i += 1
	fallback_points_uv = uv
	_pts_uv.clear()
	for q in uv:
		_pts_uv.append(q)

func _close_if_needed() -> void:
	if _pts_uv.size() >= 2:
		var a: Vector2 = _pts_uv[0]
		var b: Vector2 = _pts_uv[_pts_uv.size() - 1]
		if a.distance_to(b) > (1.0 / 1024.0):
			_pts_uv.append(a)

func _build_lengths() -> void:
	_cumlen_px.clear()
	_total_len_px = 0.0
	if _pts_uv.size() < 2:
		return
	_cumlen_px.resize(_pts_uv.size())
	_cumlen_px[0] = 0.0
	var i := 0
	while i < _pts_uv.size() - 1:
		var pa := _pts_uv[i] * 1024.0
		var pb := _pts_uv[i + 1] * 1024.0
		_total_len_px += pa.distance_to(pb)
		_cumlen_px[i + 1] = _total_len_px
		i += 1

# =========================
# Movement / projection
# =========================
func _sample_uv_at_s(s_px: float) -> Vector2:
	if _pts_uv.size() < 2:
		return Vector2(0.5, 0.5)
	var s := fposmod(s_px, _total_len_px)
	var i := 0
	while i < _cumlen_px.size() - 1 and _cumlen_px[i + 1] < s:
		i += 1
	var a_uv := _pts_uv[i]
	var b_uv := _pts_uv[i + 1]
	var a := _cumlen_px[i]
	var b := _cumlen_px[i + 1]
	var denom := b - a
	if denom < 0.0001:
		denom = 0.0001
	var t := (s - a) / denom
	return a_uv.lerp(b_uv, t)

func _place_racer_at_s(s_px: float) -> void:
	# --- UV sampling
	var uv := _sample_uv_at_s(s_px)
	var uv_ahead := _sample_uv_at_s(s_px + lookahead_px)

	# --- DEBUG: paint our current UV onto the overlay as a green dot
	var overlay := get_node_or_null(path_overlay_uv)
	if overlay and overlay.has_method("clear_debug_markers") and overlay.has_method("add_debug_marker_uv"):
		# Clear once per frame and draw the single, current point
		overlay.call("clear_debug_markers")
		# IMPORTANT: feed the UV the AI is actually using to move
		# If you KEEP invert_uv_y=true in Opponent, then send the flipped UV
		var uv_for_overlay := uv
		overlay.call("add_debug_marker_uv", uv_for_overlay)

	# Optional flip of incoming UVs
	if invert_uv_y:
		uv.y = 1.0 - uv.y
		uv_ahead.y = 1.0 - uv_ahead.y

	# UV -> centered map space
	var mp := uv - Vector2(0.5, 0.5)
	var mp2 := uv_ahead - Vector2(0.5, 0.5)

	# Optional axis fixes
	if swap_xy:
		var tmp := mp
		mp = Vector2(tmp.y, tmp.x)
		tmp = mp2
		mp2 = Vector2(tmp.y, tmp.x)
	if invert_x:
		mp.x = -mp.x
		mp2.x = -mp2.x
	if invert_y:
		mp.y = -mp.y
		mp2.y = -mp2.y

	# Matrix
	var M: Basis = _world_matrix
	if _world_matrix == Basis():
		M = Basis.IDENTITY

	# Project to screen
	var w := M * Vector3(mp.x, mp.y, 1.0)
	if w.z <= 0.0:
		if debug:
			push_warning("[AI] behind camera (w.z <= 0). Try axis flips.")
		visible = false
		return
	visible = true

	var scr := Vector2(w.x / w.z, w.y / w.z)
	global_position = (scr + Vector2(0.5, 0.5)) * _screen_size

	# Depth sort
	var zi := int(w.z * 1000.0)
	if zi < -200000:
		zi = -200000
	if zi > 200000:
		zi = 200000
	z_index = zi

	# --- SCALE ---
	var scale_px: float = 1.0
	if use_depth_scale:
		# Simple depth: closer = bigger (1/z) unless inverted
		var z = abs(w.z)
		if z < 1e-4:
			z = 1e-4
		if invert_depth:
			scale_px = depth_size_k * z
		else:
			scale_px = depth_size_k / z
	else:
		# Jacobian (finite difference) – optional/legacy
		var eps := 0.002
		var w0 := w
		var w1 := M * Vector3(mp.x, mp.y + eps, 1.0)
		if w1.z <= 0.0:
			w1 = w0
		var scr0 := Vector2(w0.x / w0.z, w0.y / w0.z)
		var scr1 := Vector2(w1.x / w1.z, w1.y / w1.z)
		var dscr_px := (scr1 - scr0) * _screen_size
		var denom := eps
		if denom < 1e-6:
			denom = 1e-6
		var pixels_per_map_unit := dscr_px.length() / denom
		var desired_px_h := kart_height_map * pixels_per_map_unit

		var tex_h: float = 1.0
		var gfxh := get_node_or_null(gfx_path)
		if gfxh is Sprite2D:
			var sprh := gfxh as Sprite2D
			if sprh.region_enabled:
				tex_h = sprh.region_rect.size.y
				if tex_h < 1.0:
					tex_h = 1.0
			elif sprh.texture != null:
				tex_h = float(sprh.texture.get_height())
				if tex_h < 1.0:
					tex_h = 1.0
		scale_px = desired_px_h / max(1.0, tex_h)

	# Clamp and apply
	if scale_px < size_min:
		scale_px = size_min
	if scale_px > size_max:
		scale_px = size_max
	var gfx := get_node_or_null(gfx_path)
	if gfx is Node2D:
		(gfx as Node2D).scale = Vector2(scale_px, scale_px)

	# Angle-based frame selection
	var kart_forward_map := (mp2 - mp)
	if kart_forward_map.length() > 0.0:
		kart_forward_map = kart_forward_map.normalized()
	else:
		kart_forward_map = Vector2(0.0, 1.0)
	_update_angle_frame(kart_forward_map, w.z)

# =========================
# Angle-based frames
# =========================
func _ensure_sprite_setup() -> void:
	var gfx := get_node_or_null(gfx_path)
	if gfx is Sprite2D:
		var spr := gfx as Sprite2D
		spr.centered = true
		spr.region_enabled = true
		var col := straight_index
		if col < 0:
			col = 0
		if col >= frames_per_row:
			col = frames_per_row - 1
		spr.region_rect = Rect2(col * frame_w, 0, frame_w, frame_h)
		if anchor_bottom:
			_bottom_anchor_sprite(spr)

func _update_angle_frame(kart_f: Vector2, z_val: float) -> void:
	var gfx := get_node_or_null(gfx_path)
	if not (gfx is Sprite2D):
		return
	var spr := gfx as Sprite2D
	if not spr.region_enabled:
		spr.region_enabled = true

	# Angle from camera forward to kart forward (map xz)
	var a1 := atan2(kart_f.y, kart_f.x)
	var a2 := atan2(_cam_forward.y, _cam_forward.x)
	var a := a1 - a2

	if reverse_angle:
		a = -a
	a += deg_to_rad(angle_bias_deg)
	a = fposmod(a + TAU, TAU)

	var steps := frames_per_row
	if steps < 1:
		steps = 1
	var step := TAU / float(steps)
	var idx := int(floor(a / step + 0.5))
	idx = idx % steps

	if not turn_increases_to_right:
		idx = steps - idx
		idx = idx % steps

	idx = straight_index + idx
	idx = idx % steps

	spr.region_rect = Rect2(idx * frame_w, 0, frame_w, frame_h)

# =========================
# Debug draw
# =========================
func _draw() -> void:
	if debug_dot:
		draw_circle(Vector2.ZERO, 6.0, Color(1, 0, 0, 1))

# =========================
# Helpers
# =========================
func _bottom_anchor_sprite(spr: Sprite2D) -> void:
	var h := 0.0
	if spr.region_enabled:
		h = spr.region_rect.size.y
	elif spr.texture != null:
		h = float(spr.texture.get_height())
	spr.offset = Vector2(0.0, h * 0.5)
