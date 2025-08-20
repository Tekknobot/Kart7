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

# =========================
# Lifecycle
# =========================
func _ready() -> void:
	visible = true
	set_z_index(z_index_on_top)
	set_z_as_relative(false)

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
func set_points(p: PackedVector2Array) -> void:
	if p.is_empty():
		if debug: push_warning("[Overlay] Ignored set_points([])")
		return
	points = p
	if debug: prints("[Overlay] set_points:", points.size())
	queue_redraw()

func get_path_points() -> PackedVector2Array:
	return points

# Call this every frame from Pseudo3D.gd so we share the same matrix as the shader
func set_world_and_screen(m: Basis, screen_size: Vector2) -> void:
	_world_matrix = m
	_screen_size = screen_size
	if debug: prints("[Overlay] set_world_and_screen screen:", _screen_size, " preview_mode:", preview_mode)
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

func get_path_points_uv() -> PackedVector2Array:
	return points_uv  # UVs 0..1, CLOSED
