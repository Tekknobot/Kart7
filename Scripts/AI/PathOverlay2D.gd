# Scripts/AI/PathOverlay2D.gd
extends Node2D

@export var points: PackedVector2Array = []   # recorder output (scaled by pos_scale_px)
@export var line_width := 3.0
@export var color := Color(1, 0.1, 0.1, 0.95)
@export var pos_scale_px := 1024.0            # MUST match PathRecorder.pos_scale_px
@export var points_are_inverse := false        # recorder samples -_mapPosition
@export var z_index_on_top := 200
@export var debug := true
@export var fallback_fit_when_unset := true   # draw fitted to screen if no matrix yet
@export var fit_margin_px := 12.0

@export var map_offset_units := Vector2.ZERO   # offset in MAP UNITS (same units as Racer.ReturnMapPosition x/z)
@export var offset_px := Vector2.ZERO          # convenience: add screen-pixel-like offset (divided by pos_scale_px)

@export var invert_x := false                  # quick axis fixes if needed
@export var invert_y := false
@export var swap_xy := false

var _world_matrix: Basis = Basis()            # 0-initialized
var _screen_size: Vector2 = Vector2.ZERO

func _ready() -> void:
	set_z_index(z_index_on_top)

func set_points(p: PackedVector2Array) -> void:
	points = p
	if debug:
		prints("[Overlay] set_points:", points.size())
	queue_redraw()

# SpriteHandler calls this every frame
func set_world_and_screen(m: Basis, screen_size: Vector2) -> void:
	_world_matrix = m
	_screen_size = screen_size
	queue_redraw()

func _draw() -> void:
	var n := points.size()
	if n < 2:
		if debug:
			draw_line(Vector2(0,0), Vector2(64,0), Color(0,1,0,0.9), 3, true)
			draw_line(Vector2(0,0), Vector2(0,64), Color(0,1,0,0.9), 3, true)
		return

	# If SpriteHandler hasn't fed us yet, optionally draw a fitted preview
	if _screen_size == Vector2.ZERO or _world_matrix == Basis():
		if not fallback_fit_when_unset:
			return
		var scr := get_viewport_rect().size
		var bb := _bbox(points)
		var sz := bb.size
		if sz.x <= 0.0001 or sz.y <= 0.0001:
			return
		var sx := (scr.x - 2.0 * fit_margin_px) / sz.x
		var sy := (scr.y - 2.0 * fit_margin_px) / sz.y
		var s = min(sx, sy)
		var off = -bb.position * s + Vector2(fit_margin_px, fit_margin_px)
		for i in range(n - 1):
			var a = points[i] * s + off
			var b = points[i + 1] * s + off
			draw_line(a, b, color, line_width, true)
		if debug: prints("[Overlay] drew fallback-fit:", n, "pts")
		return

	# Normal: project with the same matrix SpriteHandler uses
	var inv := _world_matrix.inverse()
	var last_ok := false
	var last_scr := Vector2.ZERO

	# Precompute combined map-space offset (units)
	var map_off := map_offset_units + (offset_px / pos_scale_px)

	for i in range(n):
		# back to MAP units (recorder saved pixels)
		var mp := Vector2(points[i].x / pos_scale_px, points[i].y / pos_scale_px)

		# undo inverse if recorder used map inverse (we use racer now, so false)
		if points_are_inverse:
			mp = -mp

		# optional axis fixes
		if swap_xy:
			mp = Vector2(mp.y, mp.x)
		if invert_x:
			mp.x = -mp.x
		if invert_y:
			mp.y = -mp.y

		# apply alignment offset
		mp += map_off

		# project to screen
		var w := inv * Vector3(mp.x, mp.y, 1.0)
		if w.z <= 0.0:
			last_ok = false
			continue
		var scr := Vector2(w.x / w.z, w.y / w.z)
		scr = (scr + Vector2(0.5, 0.5)) * _screen_size

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
