# Scripts/AI/WaypointPath.gd
@tool
extends Node2D

@export var looped := true
@export var point_radius := 3.0
@export var line_width := 2.0
@export var color: Color = Color(0.2, 1.0, 0.4, 0.9)

# The path data in MAP SPACE (must match your racer's _mapPosition.xz units!)
@export var points: PackedVector2Array = []

# Load exactly what the recorder saved. Do NOT recenter or scale data here.
@export var auto_load_json := true
@export var json_path := "user://ai_path.json"

# Preview-only knobs (affect drawing only; NOT the data)
@export var preview_scale := 1.0
@export var preview_offset := Vector2.ZERO
@export var z_index_on_top := 100

func _ready() -> void:
	set_z_index(z_index_on_top)
	if auto_load_json and not Engine.is_editor_hint():
		load_from_json(json_path)

func _draw() -> void:
	var n := points.size()
	if n == 0:
		return
	for i in range(n):
		var a := points[i] * preview_scale + preview_offset
		draw_circle(a, point_radius, color)
		var j := (i + 1) % n if looped else i + 1
		if j < n:
			var b := points[j] * preview_scale + preview_offset
			draw_line(a, b, color, line_width)

func _process(_dt: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()

func get_point(i: int) -> Vector2:
	return points[i % max(points.size(), 1)]

func find_lookahead_index(world_pos: Vector2, lookahead: float, start_idx: int) -> int:
	var n := points.size()
	if n == 0:
		return 0
	var idx := start_idx % n
	# bounded scan so this stays cheap even with big paths
	var max_scan = min(256, n)
	for _k in range(max_scan):
		if world_pos.distance_to(points[idx]) >= lookahead:
			return idx
		idx = (idx + 1) % n
	return start_idx % n

func load_from_json(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("WaypointPath: JSON not found: " + path)
		return
	var txt := FileAccess.get_file_as_string(path)
	var data := JSON.parse_string(txt) as Dictionary
	if data == null or not data.has("points"):
		push_warning("WaypointPath: invalid JSON (missing 'points')")
		return

	var arr: Array = data["points"]
	var out := PackedVector2Array()
	out.resize(arr.size())
	var i := 0
	for item in arr:
		if item is Array and (item as Array).size() >= 2:
			var a := item as Array
			out[i] = Vector2(float(a[0]), float(a[1]))
		elif item is Vector2:
			out[i] = (item as Vector2)
		else:
			out[i] = Vector2.ZERO
		i += 1

	points = out

	# Debug: log bounds so you can see the scale of map-space data
	var bb := _bbox(points)
	prints("[WaypointPath] loaded:", points.size(), "min:", bb.position, "size:", bb.size)
	queue_redraw()

func _bbox(pts: PackedVector2Array) -> Rect2:
	if pts.size() == 0:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	var minv := pts[0]
	var maxv := pts[0]
	for k in range(1, pts.size()):
		var v := pts[k]
		if v.x < minv.x: minv.x = v.x
		if v.y < minv.y: minv.y = v.y
		if v.x > maxv.x: maxv.x = v.x
		if v.y > maxv.y: maxv.y = v.y
	return Rect2(minv, maxv - minv)
