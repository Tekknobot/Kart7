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

@export var dot_min_px_change := 1.0          # redraw only if dot moves ≥ this many pixels
@export var dot_updates_per_second := 0       # 0 = on-change; >0 = throttle Hz (e.g., 10)

var _dot_last_px := Vector2.INF               # cached last drawn pixel position
var _dot_accum := 0.0                         # throttle accumulator

# --- Skid marks (overlay painting) -------------------------------------------
@export_category("Skid Marks")
@export var skids_enabled := true
@export var skid_draw_while_drifting := true
@export var skid_draw_while_offroad := true
@export var skid_width_px: float = 3.0
@export var skid_min_segment_px: float = 2.0
@export var skid_fade_seconds: float = 0.0   # 0 = permanent
@export var skid_color_drift: Color = Color(0, 0, 0, 0.55)
@export var skid_color_offroad: Color = Color(0, 0, 0, 0.40)

# Bindings (set from your world after spawning)
@export var player_path: NodePath           # Racer prefab instance (root)
@export var pseudo3d_path: NodePath         # the Sprite2D running Pseudo3D.gd

# Internals
var _player_ref: Node = null
var _map_ref: Sprite2D = null
var _wheel_nodes: Array[Node2D] = [null, null, null, null]  # FL, FR, RL, RR

# one active stroke per wheel
var _skid_curr_pts: Array[PackedVector2Array] = [
	PackedVector2Array(), PackedVector2Array(), PackedVector2Array(), PackedVector2Array()
]
var _skid_curr_col: Array[Color] = [Color(), Color(), Color(), Color()]
var _skid_is_active: Array[bool] = [false, false, false, false]

# completed strokes (per wheel): [{pts:PackedVector2Array, col:Color, age:float}, ...]
var _skid_strokes: Array = [[], [], [], []]

@export var draw_path := false          # leave false = only skids

@export var mm_stroke_width_px: float = 1.0
@export var mm_fade_seconds: float = 2.5
@export var mm_color_drift: Color = Color(0, 0, 0, 0.70)
@export var mm_color_offroad: Color = Color(0, 0, 0, 0.50)

var _mm_curr := {}        # key "id:ch" -> {pts:PackedVector2Array, col:Color}
var _mm_done: Array = []  # array of {pts:PackedVector2Array, col:Color, age:float}

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

	# --- Skids wiring ---
	_player_ref = get_node_or_null(player_path)
	_map_ref = get_node_or_null(pseudo3d_path) as Sprite2D
	_try_autowire_wheels()

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
	var need_redraw := false
	if _world_matrix != m:
		_world_matrix = m
		need_redraw = true
	if _screen_size != screen_size:
		_screen_size = screen_size
		need_redraw = true
	if need_redraw:
		queue_redraw()


# =========================
# Drawing
# =========================
func _draw_mm_skids() -> void:
	# completed external strokes
	for d in _mm_done:
		var col: Color = d["col"]
		if mm_fade_seconds > 0.0:
			var k := 1.0 - (float(d["age"]) / mm_fade_seconds)
			if k < 0.0:
				k = 0.0
			if k > 1.0:
				k = 1.0
			col.a = col.a * k
		_draw_polyline_px(d["pts"], col, mm_stroke_width_px)

	# active external strokes
	for key in _mm_curr.keys():
		var rec = _mm_curr[key]
		var pts: PackedVector2Array = rec["pts"]
		if pts.size() >= 2:
			_draw_polyline_px(pts, rec["col"], mm_stroke_width_px)

func _draw() -> void:
	# (optional) path preview
	if draw_path and points.size() >= 2:
		_draw_uv_space(points)

	# wheel-based skids (player wheels)
	_draw_skids()

	# minimap-driven skids (from mm_append_uv)
	_draw_mm_skids()

	
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
	if _follow_dirty:
		_rebuild_follow_path()

	var changed := false

	if follow_enabled and _follow_total_len_px > 0.0:
		_follow_s_px += follow_speed_px_sec * dt

		# throttle if requested
		var can_emit := true
		if dot_updates_per_second > 0:
			_dot_accum += dt
			var interval := 1.0 / float(max(1, dot_updates_per_second))
			if _dot_accum < interval:
				can_emit = false
			else:
				_dot_accum = 0.0

		if can_emit:
			var uv := _sample_uv_at_distance(_follow_s_px)
			var px := uv * pos_scale_px

			# draw-on-change guard
			if _dot_last_px == Vector2.INF or _dot_last_px.distance_squared_to(px) >= dot_min_px_change * dot_min_px_change:
				_dot_last_px = px
				if _debug_markers_uv.size() == 0:
					_debug_markers_uv.append(uv)
				else:
					_debug_markers_uv[0] = uv
				changed = true

		# stop at the end if not looping
		if not follow_loop and _follow_s_px >= _follow_total_len_px:
			_follow_s_px = _follow_total_len_px
	else:
		if _debug_markers_uv.size() > 0:
			_debug_markers_uv.clear()
			_dot_last_px = Vector2.INF
			changed = true

	if changed:
		queue_redraw()
		
	# --- Skids update ---
	_update_skids(dt)
	
	if mm_fade_seconds > 0.0:
		var kept: Array = []
		for d in _mm_done:
			var age := float(d.get("age", 0.0)) + get_process_delta_time()
			d["age"] = age
			if age < mm_fade_seconds:
				kept.append(d)
		_mm_done = kept
	

# ---------- Skids: runtime update & drawing ----------------------------------

func _update_skids(dt: float) -> void:
	if not skids_enabled:
		return

	# late-bind if needed (prefab may spawn after _ready)
	if _player_ref == null:
		_player_ref = get_node_or_null(player_path)
	if _map_ref == null:
		_map_ref = get_node_or_null(pseudo3d_path) as Sprite2D
	if not _has_all_wheels():
		_try_autowire_wheels()

	if _player_ref == null or _map_ref == null or not _has_all_wheels():
		return

	# should we paint this frame?
	var rt := _get_rt()
	var drifting := _get_drifting()
	var should_draw := false
	if skid_draw_while_drifting and drifting:
		should_draw = true
	elif skid_draw_while_offroad and _is_offroadish(rt):
		should_draw = true
	if rt == Globals.RoadType.SINK or rt == Globals.RoadType.WALL:
		should_draw = false

	# Age & GC old strokes
	if skid_fade_seconds > 0.0:
		for wi in range(4):
			var kept := []
			for d in _skid_strokes[wi]:
				d["age"] = float(d.get("age", 0.0)) + dt
				if d["age"] < skid_fade_seconds:
					kept.append(d)
			_skid_strokes[wi] = kept

	# For each wheel, sample → UV → overlay px → append/end stroke
	var ov_px_size := pos_scale_px   # overlay coordinate system is 0..pos_scale_px
	for wi in range(4):
		var w := _wheel_nodes[wi]
		if w == null:
			_end_stroke(wi)
			continue

		# screen px (global) -> map UV (0..1) -> overlay px
		var screen_px: Vector2 = w.global_position
		var muv := _screen_px_to_map_uv(screen_px)
		if not muv.is_finite():
			_end_stroke(wi)
			continue

		# clamp to [0..1]
		if muv.x < 0.0 or muv.x > 1.0 or muv.y < 0.0 or muv.y > 1.0:
			_end_stroke(wi)
			continue

		var ov_px := Vector2(muv.x * ov_px_size, muv.y * ov_px_size)

		if should_draw:
			_append_skid_point(wi, ov_px, drifting)
		else:
			_end_stroke(wi)


func _append_skid_point(wi: int, px: Vector2, drifting: bool) -> void:
	# start stroke if needed
	if not _skid_is_active[wi]:
		_skid_is_active[wi] = true
		if drifting:
			_skid_curr_col[wi] = skid_color_drift
		else:
			_skid_curr_col[wi] = skid_color_offroad
		_skid_curr_pts[wi] = PackedVector2Array()

	var pts := _skid_curr_pts[wi]
	if pts.size() == 0 or pts[pts.size() - 1].distance_to(px) >= skid_min_segment_px:
		pts.append(px)
		_skid_curr_pts[wi] = pts


func _end_stroke(wi: int) -> void:
	if not _skid_is_active[wi]:
		return
	var pts := _skid_curr_pts[wi]
	if pts.size() >= 2:
		_skid_strokes[wi].append({
			"pts": pts,
			"col": _skid_curr_col[wi],
			"age": 0.0
		})
	# reset
	_skid_curr_pts[wi] = PackedVector2Array()
	_skid_is_active[wi] = false


func _draw_skids() -> void:
	# draw completed strokes
	for wi in range(4):
		for d in _skid_strokes[wi]:
			var col: Color = d["col"]
			if skid_fade_seconds > 0.0:
				var k = clamp(1.0 - float(d["age"]) / skid_fade_seconds, 0.0, 1.0)
				col.a *= k
			_draw_polyline_px(d["pts"], col, skid_width_px)
	# draw active strokes
	for wi in range(4):
		if _skid_is_active[wi] and _skid_curr_pts[wi].size() >= 2:
			_draw_polyline_px(_skid_curr_pts[wi], _skid_curr_col[wi], skid_width_px)


func _draw_polyline_px(pts: PackedVector2Array, col: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, width, true)


# ---------- Wheel discovery under the player's RoadEffects child ---------------

func _has_all_wheels() -> bool:
	for w in _wheel_nodes:
		if w == null:
			return false
	return true

func _try_autowire_wheels() -> void:
	if _player_ref == null:
		return
	var re := _find_road_effects_node(_player_ref)
	if re == null:
		return

	# Preferred names
	if _wheel_nodes[0] == null: _wheel_nodes[0] = _find_first_of(re, ["FrontLeftWheel","FrontLeft","WheelFL","FL"])  as Node2D
	if _wheel_nodes[1] == null: _wheel_nodes[1] = _find_first_of(re, ["FrontRightWheel","FrontRight","WheelFR","FR"]) as Node2D
	if _wheel_nodes[2] == null: _wheel_nodes[2] = _find_first_of(re, ["RearLeftWheel","RearLeft","WheelRL","RL"])     as Node2D
	if _wheel_nodes[3] == null: _wheel_nodes[3] = _find_first_of(re, ["RearRightWheel","RearRight","WheelRR","RR"])   as Node2D

	# Fallback: Left/Right duplicated to front & rear
	if _wheel_nodes[0] == null or _wheel_nodes[2] == null:
		var lw := _find_first_of(re, ["LeftWheel","WheelLeft","LeftWheelSpecial"]) as Node2D
		if lw != null:
			if _wheel_nodes[0] == null: _wheel_nodes[0] = lw
			if _wheel_nodes[2] == null: _wheel_nodes[2] = lw
	if _wheel_nodes[1] == null or _wheel_nodes[3] == null:
		var rw := _find_first_of(re, ["RightWheel","WheelRight","RightWheelSpecial"]) as Node2D
		if rw != null:
			if _wheel_nodes[1] == null: _wheel_nodes[1] = rw
			if _wheel_nodes[3] == null: _wheel_nodes[3] = rw


func _find_road_effects_node(root: Node) -> Node:
	var n := root.get_node_or_null("RoadEffects")
	if n != null: return n
	n = root.get_node_or_null("Road Type Effects")
	if n != null: return n
	var hit := root.find_child("RoadEffects", true, false)
	if hit != null: return hit
	return root.find_child("Road Type Effects", true, false)


func _find_first_of(parent: Node, names: Array[String]) -> Node:
	for nm in names:
		var n := parent.get_node_or_null(nm)
		if n != null:
			return n
		var deep := parent.find_child(nm, true, false)
		if deep != null:
			return deep
	return null


# ---------- Player state helpers ----------------------------------------------

func _get_rt() -> int:
	if _player_ref != null and _player_ref.has_method("ReturnOnRoadType"):
		return int(_player_ref.call("ReturnOnRoadType"))
	return -1

func _get_drifting() -> bool:
	if _player_ref != null and _player_ref.has_method("ReturnIsDrifting"):
		return bool(_player_ref.call("ReturnIsDrifting"))
	return false

func _is_offroadish(rt: int) -> bool:
	return rt == Globals.RoadType.OFF_ROAD or rt == Globals.RoadType.GRAVEL


# ---------- Project wheel screen → map UV using your world matrix --------------

func _screen_px_to_map_uv(screen_px: Vector2) -> Vector2:
	# Convert the wheel's screen/global pixel into the Pseudo3D sprite's local UV,
	# then apply the SAME projective transform the shader uses: projectedUV = (M * (uv-0.5,1)).xy / z
	if _map_ref == null or _map_ref.texture == null:
		return Vector2(INF, INF)

	var local_px := _map_ref.to_local(screen_px)
	var tex_sz := _map_ref.texture.get_size()
	if tex_sz.x <= 0.0 or tex_sz.y <= 0.0:
		return Vector2(INF, INF)

	var uv := (local_px / tex_sz) + Vector2(0.5, 0.5)
	var uv_centered := uv - Vector2(0.5, 0.5)

	# _world_matrix is the "mapMatrix" you already pass into the shader
	var h: Vector3 = _world_matrix * Vector3(uv_centered.x, uv_centered.y, 1.0)
	if abs(h.z) < 1e-6:
		return Vector2(INF, INF)

	return Vector2(h.x / h.z, h.y / h.z)

# ---------- Utilities ----------------------------------------------------------
func ClearSkids() -> void:
	for wi in range(4):
		_skid_curr_pts[wi] = PackedVector2Array()
		_skid_is_active[wi] = false
		_skid_strokes[wi] = []
	queue_redraw()
		
func _uv_to_px(uv: Vector2) -> Vector2:
	var s := float(max(1, int(pos_scale_px)))
	var x := uv.x * s
	var y := uv.y * s
	return Vector2(x, y)

func _mm_key(id: int, ch: int) -> String:
	return str(id) + ":" + str(ch)

func mm_append_uv(id: int, ch: int, uv: Vector2, drifting: bool) -> void:
	var key := _mm_key(id, ch)
	var px := _uv_to_px(uv)

	var rec = null
	if _mm_curr.has(key):
		rec = _mm_curr[key]
	else:
		rec = {"pts": PackedVector2Array(), "col": mm_color_offroad}
		_mm_curr[key] = rec

	if drifting:
		rec["col"] = mm_color_drift
	else:
		rec["col"] = mm_color_offroad

	var pts: PackedVector2Array = rec["pts"]
	var add_point := true
	if pts.size() > 0:
		var last := pts[pts.size() - 1]
		if last.distance_to(px) < float(max(1, int(skid_min_segment_px))):
			add_point = false
	if add_point:
		pts.append(px)

	queue_redraw()

func mm_end(id: int, ch: int) -> void:
	var key := _mm_key(id, ch)
	if not _mm_curr.has(key):
		return
	var rec = _mm_curr[key]
	var pts: PackedVector2Array = rec["pts"]
	if pts.size() >= 2:
		_mm_done.append({"pts": pts, "col": rec["col"], "age": 0.0})
	_mm_curr.erase(key)
	queue_redraw()

func mm_clear_all() -> void:
	_mm_curr.clear()
	_mm_done.clear()
	queue_redraw()

# --- Expose the overlay texture ----------------------------------------------
func get_texture() -> Texture2D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_texture()


# --- Wire the overlay texture into your ground shader -------------------------
# Call once after both nodes exist:
#   $PathOverlay2D.wire_overlay_to_ground($GroundSprite, "skid_overlay")
func wire_overlay_to_ground(ground_sprite: Node, shader_param_name: String = "pathOverlay") -> void:
	if ground_sprite == null:
		push_warning("[Overlay] wire_overlay_to_ground: ground_sprite is null")
		return

	var tex := get_texture()
	if tex == null:
		push_warning("[Overlay] wire_overlay_to_ground: overlay viewport has no texture")
		return

	var mat = null
	# CanvasItems (Sprite2D, MeshInstance2D, etc.) have 'material'
	if "material" in ground_sprite:
		mat = ground_sprite.material
	elif "get_material" in ground_sprite:
		mat = ground_sprite.get_material()
	else:
		push_warning("[Overlay] wire_overlay_to_ground: node has no material property")
		return

	if mat == null:
		push_warning("[Overlay] wire_overlay_to_ground: material is null")
		return
	if not (mat is ShaderMaterial):
		push_warning("[Overlay] wire_overlay_to_ground: material is not a ShaderMaterial")
		return

	var sm := mat as ShaderMaterial
	# Just set it; if the param doesn't exist the editor will warn once.
	sm.set_shader_parameter(shader_param_name, tex)
	prints("[Overlay] wired overlay texture into", ground_sprite.name, "param:", shader_param_name)


# --- One-shot sanity stroke to prove the hookup works -------------------------
func debug_draw_center_line() -> void:
	var id := 123456
	var u0 := Vector2(0.49, 0.50)
	var u1 := Vector2(0.51, 0.50)
	mm_append_uv(id, 0, u0, true)
	mm_append_uv(id, 0, u1, true)
	mm_end(id, 0)
	prints("[Overlay] drew debug center line")
