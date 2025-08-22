extends Node2D

# =========================
# Debug / rendering
# =========================
@export var preview_mode := true            # ignore matrix, fit to screen for quick visual check
@export var line_width := 6.0
@export var color := Color(1, 0, 0, 0.9)    # red, opaque by default (change as you like)
@export var z_index_on_top := 9999

# =========================
# Input points (PNG pixel coords)
# =========================
# Paste Aseprite pixels here or call set_points() at runtime.
# These are raw texture pixels relative to the PNG (0..pos_scale_px on both axes).
@export var points: PackedVector2Array = PackedVector2Array([])
@export var points_uv: PackedVector2Array = PackedVector2Array([])

# If you want a starting sample loop to see something on screen, uncomment:
# var DEFAULT_POINTS: PackedVector2Array = PackedVector2Array([
#     Vector2(160,224), Vector2(240,276), Vector2(320,330), Vector2(404,390),
#     Vector2(493,455), Vector2(584,526), Vector2(678,600), Vector2(764,656),
#     Vector2(832,704), Vector2(896,740), Vector2(944,768), Vector2(980,810),
#     Vector2(990,880), Vector2(968,940), Vector2(912,980), Vector2(832,1000),
#     Vector2(740,984), Vector2(650,944), Vector2(560,884), Vector2(480,812),
#     Vector2(400,740), Vector2(320,664), Vector2(244,588), Vector2(188,508),
#     Vector2(160,420), Vector2(164,340), Vector2(188,280), Vector2(220,240),
#     Vector2(240,220), Vector2(160,224) # closed
# ])

# =========================
# Alignment controls
# =========================
@export var pos_scale_px := 1024.0          # PNG size (use 1024.0 for 1024x1024)
@export var pre_rotate_deg := 0.0           # rotation (deg) around texture center BEFORE projection
@export var pre_scale := 1.0                # uniform scale in map units BEFORE projection

# Quick axis fixes (applied in centered map space)
@export var swap_xy := false
@export var invert_x := false
@export var invert_y := false

# Tiny nudges in map units AFTER (UV-0.5), rotation, scale (keep ZERO unless you need small offsets)
@export var map_offset_units := Vector2.ZERO

# Optional extra pixel-like offset BEFORE centering (rarely needed)
@export var offset_px := Vector2.ZERO

# Diagnostics
@export var debug := true
@export var fallback_fit_when_unset := true
@export var fit_margin_px := 12.0

# =========================
# Internal state
# =========================
var _world_matrix: Basis = Basis()      # same matrix you send to the shader as `mapMatrix`
var _screen_size: Vector2 = Vector2.ZERO

@export var show_debug_markers := true
var _debug_markers_uv: Array[Vector2] = []

# === Follow-the-path debug dot ===
@export var follow_enabled := true           # turn the green dot on/off
@export var follow_speed_px_sec := 140.0     # speed along the path in *texture pixels/sec*
@export var follow_loop := true              # loop when reaching the end

var _follow_total_len_px := 0.0
var _follow_s_px := 0.0                      # current distance along path (pixels)
var _follow_segments: Array = []             # [{a_uv:Vector2, b_uv:Vector2, len_px:float, cum_px:float}, ...]
var _follow_dirty := true                    # rebuild segments when points/transform change

# =========================
# Lifecycle
# =========================
func _ready() -> void:
	visible = true
	set_z_index(z_index_on_top)
	set_z_as_relative(false)
	set_process(true)                 # <-- needed to advance the dot
	
	# If you want an initial sample:
	# if points.is_empty():
	#     points = DEFAULT_POINTS.duplicate()

	# If we live inside a SubViewport, ensure it has size (and Transparent BG in the editor)
	var svp := get_viewport()
	if svp is SubViewport:
		if svp.size == Vector2i.ZERO:
			svp.size = Vector2i(1024, 1024)  # safe default; set to your target if needed
			if debug: prints("[Overlay] SubViewport size was 0x0; set to", svp.size)
		_screen_size = Vector2(svp.size)
		if debug: prints("[Overlay] Using SubViewport size:", _screen_size)

	queue_redraw()

# External API ---------------------------------------------------
# --- Add/replace these in PathOverlay2D.gd ---

# Set pixel-space points and auto-derive UVs (0..1)
func set_points(p: PackedVector2Array) -> void:
	if p.is_empty():
		if debug: push_warning("[Overlay] Ignored set_points([])")
		return
	points = p
	# derive UVs from pixels
	points_uv = PackedVector2Array()
	for v in points:
		points_uv.append(v / pos_scale_px)
	_ensure_closed_uv()
	if debug: prints("[Overlay] set_points px:", points.size(), " -> uv:", points_uv.size())
	queue_redraw()

# Optional: set UVs directly (0..1). Useful if your track tool already exports UVs.
func set_points_uv(puv: PackedVector2Array) -> void:
	if puv.is_empty():
		if debug: push_warning("[Overlay] Ignored set_points_uv([])")
		return
	points_uv = puv.duplicate()
	_ensure_closed_uv()
	# keep 'points' in pixel space for preview drawing
	points = PackedVector2Array()
	for uv in points_uv:
		points.append(uv * pos_scale_px)
	if debug: prints("[Overlay] set_points_uv:", points_uv.size())
	queue_redraw()

func get_path_points_uv() -> PackedVector2Array:
	return points_uv  # authoritative 0..1, CLOSED

# Ensure path is closed (first == last)
func _ensure_closed_uv() -> void:
	if points_uv.size() >= 2:
		var a: Vector2 = points_uv[0]
		var b: Vector2 = points_uv[points_uv.size() - 1]
		if a.distance_to(b) > (1.0 / pos_scale_px):
			points_uv.append(a)

func get_path_points() -> PackedVector2Array:
	return points

# Call this every frame from Pseudo3D.gd so we share the same matrix as the shader
func set_world_and_screen(m: Basis, screen_size: Vector2) -> void:
	_world_matrix = m
	_screen_size = screen_size
	#if debug: prints("[Overlay] set_world_and_screen screen:", _screen_size, " preview_mode:", preview_mode)
	queue_redraw()

# =========================
# Drawing
# =========================
func _draw() -> void:
	var n := points.size()
	if n < 2:
		if debug:
			draw_line(Vector2(0,0), Vector2(64,0), Color(0,1,0,0.9), 6, true)
			draw_line(Vector2(0,0), Vector2(0,64), Color(0,1,0,0.9), 6, true)
		return

	# Always draw in UV/texture space (pixels), since shader samples with projectedUV
	_draw_uv_space(points)

func _draw_uv_space(pts: PackedVector2Array) -> void:
	# Optionally apply rotation/flip/scale around texture center in PIXEL space:
	var ready = _apply_px_transforms(pts)

	for i in range(ready.size()):
		var a = ready[i]
		draw_circle(a, 2.5, color)
		if i < ready.size() - 1:
			var b = ready[i + 1]
			draw_line(a, b, color, line_width, true)
			
	# --- DEBUG: draw AI/markers in UV texture space ---
	if show_debug_markers and _debug_markers_uv.size() > 0:
		for uv in _debug_markers_uv:
			var p := uv * pos_scale_px      # uv -> pixels
			draw_circle(p, 6.0, Color(0,1,0,1))   # green dot
			

func _apply_px_transforms(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var C := Vector2(pos_scale_px * 0.5, pos_scale_px * 0.5)  # center in pixels

	var ang := deg_to_rad(pre_rotate_deg)
	var cs := cos(ang)
	var sn := sin(ang)

	for p in pts:
		var v := p + offset_px     # tiny pre-nudge in pixels (optional)

		# center to origin (pixels)
		v -= C

		# quick axis fixes in pixel space
		if swap_xy: v = Vector2(v.y, v.x)
		if invert_x: v.x = -v.x
		if invert_y: v.y = -v.y

		# scale, rotate, back to pixel space
		if pre_scale != 1.0: v *= pre_scale
		if pre_rotate_deg != 0.0:
			v = Vector2(v.x * cs - v.y * sn, v.x * sn + v.y * cs)

		v += C

		# final nudge in map units -> convert to pixels (map_offset_units is in “UV-centered units”)
		if map_offset_units != Vector2.ZERO:
			v += map_offset_units * pos_scale_px

		out.append(v)
	return out

# Fallback-fit (screen-space) -----------------------------------
func _draw_fallback(pts: PackedVector2Array) -> void:
	var scr := get_viewport_rect().size
	var bb := _bbox(pts)
	var sz := bb.size
	if sz.x <= 0.0001 or sz.y <= 0.0001:
		if debug: push_warning("[Overlay] degenerate bbox")
		return
	var sx := (scr.x - 2.0 * fit_margin_px) / sz.x
	var sy := (scr.y - 2.0 * fit_margin_px) / sz.y
	var s = min(sx, sy)
	var off = -bb.position * s + Vector2(fit_margin_px, fit_margin_px)

	for i in range(pts.size()):
		var p = pts[i] * s + off
		draw_circle(p, 2.5, color)
		if i < pts.size() - 1:
			var q = pts[i + 1] * s + off
			draw_line(p, q, color, line_width, true)
	if debug: prints("[Overlay] drew FALLBACK:", pts.size(), "pts")

# Matrix-projected (map space) ----------------------------------
func _draw_projected(pts: PackedVector2Array) -> void:
	var inv := _world_matrix.inverse()
	var last_ok := false
	var last_scr := Vector2.ZERO

	for i in range(pts.size()):
		var mp := _map_point_from_pixels(pts[i])  # centered map units
		var w := inv * Vector3(mp.x, mp.y, 1.0)
		if w.z <= 0.0:
			last_ok = false
			continue
		var scr := Vector2(w.x / w.z, w.y / w.z)
		scr = (scr + Vector2(0.5, 0.5)) * _screen_size

		draw_circle(scr, 2.5, color)
		if last_ok:
			draw_line(last_scr, scr, color, line_width, true)
		last_ok = true
		last_scr = scr

# =========================
# Core mapping math (this is the important bit)
# =========================
# Take PNG pixel coords (x_px, y_px) and convert to the same "map space"
# your shader uses with: mapMatrix * vec3(UV - 0.5, 1).
func _map_point_from_pixels(px: Vector2) -> Vector2:
	# 0) Optional extra pre-offset in pixels (rare; use to nudge before centering)
	var px_adj := px + offset_px

	# 1) pixels -> UV [0..1]
	var uv := px_adj / pos_scale_px

	# 2) center shift (the single offset): UV - 0.5
	var m := uv - Vector2(0.5, 0.5)

	# 3) quick axis fixes in centered space
	if swap_xy:
		m = Vector2(m.y, m.x)
	if invert_x:
		m.x = -m.x
	if invert_y:
		m.y = -m.y

	# 4) pre-scale
	if pre_scale != 1.0:
		m *= pre_scale

	# 5) pre-rotation around the center
	if pre_rotate_deg != 0.0:
		var r := deg_to_rad(pre_rotate_deg)
		var cs := cos(r)
		var sn := sin(r)
		m = Vector2(m.x * cs - m.y * sn, m.x * sn + m.y * cs)

	# 6) final nudge in map units (keep ZERO unless you need tiny offset)
	m += map_offset_units

	return m

# =========================
# Utilities
# =========================
func _bbox(pts: PackedVector2Array) -> Rect2:
	var minv := pts[0]
	var maxv := pts[0]
	for k in range(1, pts.size()):
		var v := pts[k]
		if v.x < minv.x: minv.x = v.x
		if v.y < minv.y: minv.y = v.y
		if v.x > maxv.x: maxv.x = v.x
		if v.y > maxv.y: maxv.y = v.y
	return Rect2(minv, maxv - minv)

# Return UVs AFTER applying editor transforms (rotate/flip/scale/offset),
# so the path matches what you see in the SubViewport.
func get_path_points_uv_transformed() -> PackedVector2Array:
	var src_px: PackedVector2Array

	# Ensure we have pixel-space points to transform
	if points.size() > 0:
		src_px = points.duplicate()
	elif points_uv.size() > 0:
		# rebuild pixels from UVs if needed
		src_px = PackedVector2Array()
		for uv in points_uv:
			src_px.append(uv * pos_scale_px)
	else:
		return PackedVector2Array()  # nothing to return

	# Apply the same pixel-space transforms used by _draw()
	var px_ready: PackedVector2Array = _apply_px_transforms(src_px)

	# Convert back to UVs
	var out := PackedVector2Array()
	for p in px_ready:
		out.append(p / pos_scale_px)

	# Ensure closed loop like other getters
	if out.size() >= 2:
		var a := out[0]
		var b := out[out.size() - 1]
		if a.distance_to(b) > (1.0 / pos_scale_px):
			out.append(a)

	return out

func clear_debug_markers() -> void:
	_debug_markers_uv.clear()
	queue_redraw()

func add_debug_marker_uv(uv: Vector2) -> void:
	_debug_markers_uv.append(uv)
	queue_redraw()
	
func _rebuild_follow_path() -> void:
	_follow_segments.clear()
	_follow_total_len_px = 0.0

	var uv_loop := get_path_points_uv_transformed()
	if uv_loop.size() < 2:
		return

	for i in range(uv_loop.size() - 1):
		var a := uv_loop[i]
		var b := uv_loop[i + 1]
		var seg_len_px := a.distance_to(b) * pos_scale_px
		if seg_len_px <= 0.0:
			continue
		_follow_total_len_px += seg_len_px
		_follow_segments.append({
			"a_uv": a,
			"b_uv": b,
			"len_px": seg_len_px,
			"cum_px": _follow_total_len_px
		})

	# keep current progress inside range
	if _follow_total_len_px > 0.0:
		_follow_s_px = fposmod(_follow_s_px, _follow_total_len_px)
	_follow_dirty = false
	
func _sample_uv_at_distance(s_px: float) -> Vector2:
	if _follow_segments.is_empty():
		return Vector2(0.5, 0.5)

	# clamp or wrap
	if follow_loop and _follow_total_len_px > 0.0:
		s_px = fposmod(s_px, _follow_total_len_px)
	else:
		s_px = clamp(s_px, 0.0, _follow_total_len_px)

	# find the segment
	for seg in _follow_segments:
		var end_cum = seg["cum_px"]
		var start_cum = end_cum - seg["len_px"]
		if s_px <= end_cum:
			var t = (s_px - start_cum) / seg["len_px"]  # 0..1
			var a: Vector2 = seg["a_uv"]
			var b: Vector2 = seg["b_uv"]
			return a.lerp(b, t)

	# fallback (numerical edge): last point
	var last: Dictionary = _follow_segments[_follow_segments.size() - 1]
	return last["b_uv"]

func _process(dt: float) -> void:
	# mark dirty if transform knobs changed at runtime (cheap heuristic):
	# If you allow editing in-game, you can set _follow_dirty = true when those change.
	if _follow_dirty:
		_rebuild_follow_path()

	if follow_enabled and _follow_total_len_px > 0.0:
		_follow_s_px += follow_speed_px_sec * dt

		var uv := _sample_uv_at_distance(_follow_s_px)

		# Update the green dot list (we draw all debug markers in _draw_uv_space)
		if _debug_markers_uv.size() == 0:
			_debug_markers_uv.append(uv)
		else:
			_debug_markers_uv[0] = uv

		# stop at the end if not looping
		if not follow_loop and _follow_s_px >= _follow_total_len_px:
			_follow_s_px = _follow_total_len_px
	else:
		# if disabled, don’t leave old markers around
		if _debug_markers_uv.size() > 0:
			_debug_markers_uv.clear()

	# keep the overlay fresh
	queue_redraw()
