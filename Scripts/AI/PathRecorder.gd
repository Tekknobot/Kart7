# Scripts/AI/PathRecorder.gd
@tool
extends Node

# Reference to your Pseudo3D map sprite (the world node with _mapPosition)
@export var map_sprite_node: NodePath

# Optional path node to preview the recorded points (e.g., WaypointPath)
@export var path_node: NodePath

# Sampling + simplification
@export var sample_every_px := 24.0       # spacing between samples (pixels after scaling)
@export var simplify_epsilon := 6.0       # RDP tolerance
@export var close_loop_on_save := true

# Scaling: converts map units → pixels (tune to match texture size, e.g. 1024)
@export var pos_scale_px := 1024.0

# Live preview controls
@export var apply_interval_s := 0.25      # throttle path updates (seconds)
@export var live_preview := true
@export var debug := false

var _recording := false
var _buf: Array[Vector2] = []
var _apply_elapsed := 0.0
var _apply_pending := false

@export var racer_node: NodePath   # Racer with ReturnMapPosition()

func _ready() -> void:
	set_process(true)
	set_process_unhandled_input(true)
	if Engine.is_editor_hint():
		push_warning("PathRecorder: run scene, press R to start/stop, S to save, C to clear.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_R:
				_recording = not _recording
				if _recording:
					_buf.clear()
					print("[PathRecorder] Recording started")
				else:
					print("[PathRecorder] Recording stopped. Points:", _buf.size())
					if live_preview:
						_request_apply()
			KEY_S:
				_save()
			KEY_C:
				_buf.clear()
				_request_apply()
				print("[PathRecorder] Cleared points.")

func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return

	if _recording:
		var p := _get_map_space_pos()
		if debug and p != Vector2.ZERO:
			var d: float = -1.0
			if not _buf.is_empty():
				d = _buf[_buf.size() - 1].distance_to(p)

			prints("[PathRecorder]", "p:", p, "dist_from_last:", d)

		if p != Vector2.ZERO:
			if _buf.is_empty() or _buf[_buf.size()-1].distance_to(p) >= sample_every_px:
				_buf.append(p)
				if debug: prints("[PathRecorder] appended, total:", _buf.size())
				if live_preview:
					_apply_elapsed = 0.0
					_request_apply()

	if _apply_pending:
		_apply_elapsed += dt
		if _apply_elapsed >= apply_interval_s:
			_apply_elapsed = 0.0
			_apply_pending = false
			_apply_to_path_deferred()

# === Core: get map-space position (inverse of world motion) ===
func _get_map_space_pos() -> Vector2:
	# ✅ TRUE world/map path: use the racer's x/z
	var r = get_node_or_null(racer_node)
	if r and r.has_method("ReturnMapPosition"):
		var v = r.ReturnMapPosition()             # Vector3
		return Vector2(v.x, v.z) * pos_scale_px  # keep your scaling

	# fallback: your current map-based method (will be misaligned due to orbit)
	var m = get_node_or_null(map_sprite_node)
	if m and m.has_method("ReturnMapPosition3D"):
		var p3 = m.ReturnMapPosition3D()
		return Vector2(-p3.x, -p3.z) * pos_scale_px
	if m and m.has_method("get"):
		var p3b = m.get("_mapPosition")
		if typeof(p3b) == TYPE_VECTOR3:
			return Vector2(-p3b.x, -p3b.z) * pos_scale_px

	return Vector2.ZERO
	
func _request_apply() -> void:
	_apply_pending = true

func _apply_to_path_deferred() -> void:
	var packed := PackedVector2Array(_buf)
	call_deferred("_set_path_points", packed)

func _set_path_points(pts: PackedVector2Array) -> void:
	var path = get_node_or_null(path_node)
	if path == null:
		return

	# Prefer the method so auto-fit + redraw run.
	if path.has_method("set_points"):
		path.set_points(pts)
		return

	# Fallback: set the property and try to trigger fit + redraw if available.
	if "points" in path:
		path.points = pts
		if path.has_method("_compute_fit"):
			path._compute_fit()
		if path.has_method("queue_redraw"):
			path.queue_redraw()


func _save() -> void:
	if _buf.size() < 3:
		push_warning("PathRecorder: not enough points to save.")
		return

	var pts := _rdp(PackedVector2Array(_buf), simplify_epsilon)
	if close_loop_on_save and pts.size() >= 2:
		if pts[0].distance_to(pts[pts.size()-1]) > sample_every_px:
			pts.append(pts[0])

	# Convert to simple [[x,y], [x,y], ...] for JSON
	var arr: Array = []
	for v in pts:
		arr.append([v.x, v.y])

	var data := {"points": arr}

	var fa := FileAccess.open("user://ai_path.json", FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(data))
		fa.close()
		print("[PathRecorder] Saved to user://ai_path.json (", pts.size(), " points)")

		# Rebuild _buf as Array[Vector2] for runtime use
		_buf.clear()
		for v in pts:
			_buf.append(v)

		if live_preview:
			_request_apply()
	else:
		push_error("PathRecorder: Failed to write user://ai_path.json")


# --- RDP simplification ---
func _rdp(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() <= 2:
		return pts.duplicate()
	var first := pts[0]
	var last := pts[pts.size() - 1]
	var index := 0
	var dist_max := -1.0
	for i in range(1, pts.size() - 1):
		var d := _point_line_distance(pts[i], first, last)
		if d > dist_max:
			index = i
			dist_max = d
	var result: PackedVector2Array = []
	if dist_max > eps:
		var rec1 := _rdp(pts.slice(0, index + 1), eps)
		var rec2 := _rdp(pts.slice(index, pts.size()), eps)
		for j in rec1.size():
			result.append(rec1[j])
		for j in range(1, rec2.size()):
			result.append(rec2[j])
	else:
		result.append(first)
		result.append(last)
	return result

func _point_line_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := 0.0
	var denom := ab.length_squared()
	if denom > 0.0:
		t = clamp((p - a).dot(ab) / denom, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_to(proj)
