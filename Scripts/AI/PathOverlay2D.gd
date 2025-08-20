extends Node2D

# ---- TEMP: force visible, fat, neon while debugging
@export var preview_mode := true    # << set true to ignore matrix and fit to screen
@export var line_width := 8.0
@export var color := Color(0, 1, 1, 1.0)   # cyan, opaque
@export var z_index_on_top := 9999

# MarioTrack sample (30 pts). Replace later with your full list.
var DEFAULT_POINTS := PackedVector2Array([
	Vector2(920.0, 856.0), Vector2(160.1, 224.2), Vector2(168.3, 229.5),
	Vector2(176.7, 235.0), Vector2(185.2, 240.6), Vector2(194.0, 246.3),
	Vector2(203.0, 252.0), Vector2(212.2, 257.9), Vector2(221.5, 263.9),
	Vector2(231.0, 270.0), Vector2(240.5, 276.2), Vector2(250.1, 282.5),
	Vector2(259.8, 289.0), Vector2(269.6, 295.6), Vector2(279.5, 302.3),
	Vector2(289.5, 309.1), Vector2(299.6, 316.0), Vector2(309.8, 323.0),
	Vector2(320.0, 330.0), Vector2(330.3, 337.1), Vector2(340.7, 344.3),
	Vector2(351.1, 351.6), Vector2(361.6, 359.0), Vector2(372.2, 366.5),
	Vector2(382.9, 374.1), Vector2(393.6, 381.8), Vector2(404.4, 389.6),
	Vector2(415.3, 397.5), Vector2(426.2, 405.5)
])

# Recorder/scaling/options
@export var points: PackedVector2Array = PackedVector2Array([])
@export var pos_scale_px := 1024.0
@export var points_are_inverse := false
@export var debug := true
@export var fallback_fit_when_unset := true
@export var fit_margin_px := 12.0

@export var map_offset_units := Vector2.ZERO
@export var offset_px := Vector2.ZERO
@export var invert_x := false
@export var invert_y := false
@export var swap_xy := false

var _world_matrix: Basis = Basis()
var _screen_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	visible = true
	set_z_index(z_index_on_top)
	set_z_as_relative(false)   # draw on top of everything else (outside parent stacking)
	# Backfill points if inspector saved empty
	if points.is_empty():
		points = DEFAULT_POINTS.duplicate()
		if debug: prints("[Overlay] filled DEFAULT_POINTS:", points.size())

	# If we live inside a SubViewport, inherit its size (critical!)
	var svp := get_viewport()
	if svp is SubViewport:
		# Ensure SubViewport is actually sized; if not, set a sensible default once
		var sz = svp.size
		if sz == Vector2i(0,0):
			svp.size = Vector2i(1280, 720)  # set your game resolution here
			if debug: prints("[Overlay] SubViewport size was 0x0; set to", svp.size)
		_screen_size = Vector2(svp.size)
		if debug: prints("[Overlay] Using SubViewport size:", _screen_size)
		# If you want transparent overlay texture in shader, set this on the SubViewport in the editor:
		#  - Transparent Bg = On

	queue_redraw()

func set_points(p: PackedVector2Array) -> void:
	if p.is_empty():
		if debug: push_warning("[Overlay] Ignored set_points([])")
		return
	points = p
	if debug: prints("[Overlay] set_points:", points.size())
	queue_redraw()

func set_world_and_screen(m: Basis, screen_size: Vector2) -> void:
	_world_matrix = m
	_screen_size = screen_size
	if debug: prints("[Overlay] set_world_and_screen() screen:", _screen_size, " preview_mode:", preview_mode)
	queue_redraw()

func _draw() -> void:
	var n := points.size()
	if n < 2:
		if debug:
			draw_line(Vector2(0,0), Vector2(64,0), Color(0,1,0,0.9), 6, true)
			draw_line(Vector2(0,0), Vector2(0,64), Color(0,1,0,0.9), 6, true)
			push_warning("[Overlay] Not enough points to draw")
		return

	var use_fallback := preview_mode or _screen_size == Vector2.ZERO or _world_matrix == Basis()
	if use_fallback:
		var scr := get_viewport_rect().size
		var bb := _bbox(points)
		var sz := bb.size
		if sz.x <= 0.0001 or sz.y <= 0.0001:
			if debug: push_warning("[Overlay] degenerate bbox")
			return
		var sx := (scr.x - 2.0 * fit_margin_px) / sz.x
		var sy := (scr.y - 2.0 * fit_margin_px) / sz.y
		var s = min(sx, sy)
		var off = -bb.position * s + Vector2(fit_margin_px, fit_margin_px)
		# draw points as dots AND a polyline so you can’t miss them
		for i in range(n):
			var p = points[i] * s + off
			draw_circle(p, 3.0, color)
			if i < n - 1:
				var q = points[i + 1] * s + off
				draw_line(p, q, color, line_width, true)
		if debug: prints("[Overlay] drew FALLBACK (preview_mode or no matrix):", n, "pts")
		return

	# Matrix mode
	var inv := _world_matrix.inverse()
	var last_ok := false
	var last_scr := Vector2.ZERO
	var map_off := map_offset_units + (offset_px / pos_scale_px)

	for i in range(n):
		var mp := Vector2(points[i].x / pos_scale_px, points[i].y / pos_scale_px)
		if points_are_inverse: mp = -mp
		if swap_xy: mp = Vector2(mp.y, mp.x)
		if invert_x: mp.x = -mp.x
		if invert_y: mp.y = -mp.y
		mp += map_off

		var w := inv * Vector3(mp.x, mp.y, 1.0)
		if w.z <= 0.0:
			last_ok = false
			continue
		var scr := Vector2(w.x / w.z, w.y / w.z)
		scr = (scr + Vector2(0.5, 0.5)) * _screen_size

		# draw points as dots too (debug)
		draw_circle(scr, 3.0, color)
		if last_ok:
			draw_line(last_scr, scr, color, line_width, true)
		last_ok = true
		last_scr = scr

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

func get_path_points() -> PackedVector2Array:
	return points
