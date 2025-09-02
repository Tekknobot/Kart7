# SkidMarkPainter2D.gd
extends Node2D

# Main scene refs
@export var pseudo3d_path: NodePath        # -> your Pseudo3D node
@export var player_path: NodePath          # -> the Racer

# Wheel anchors (Node2D anywhere in the main scene; we sample their global_position)
# If these are empty, we auto-find under the player's "RoadEffects" / "Road Type Effects" child.
@export var front_left_path: NodePath
@export var front_right_path: NodePath
@export var rear_left_path: NodePath
@export var rear_right_path: NodePath

# Tuning
@export var draw_while_drifting := true
@export var draw_while_offroad := true
@export var width_px: float = 3.0
@export var min_segment_px: float = 2.0       # distance before adding new point
@export var fade_seconds: float = 0.0         # 0 = never fade
@export var color_drift: Color = Color(0, 0, 0, 0.55)
@export var color_offroad: Color = Color(0, 0, 0, 0.40)
@export var brush_texture: Texture2D          # optional: a tread/brush texture
@export var clamp_to_overlay := true          # ignore points outside [0..overlay_size]

var _pseudo3d: Node = null
var _player: Node = null
var _wheels: Array[Node2D] = [null, null, null, null]   # FL, FR, RL, RR
var _lines: Array[Line2D]  = [null, null, null, null]   # active stroke for each wheel

func _ready() -> void:
	_pseudo3d = get_node_or_null(pseudo3d_path)
	_player = get_node_or_null(player_path)

	# explicit paths first
	_wheels[0] = get_node_or_null(front_left_path)  as Node2D
	_wheels[1] = get_node_or_null(front_right_path) as Node2D
	_wheels[2] = get_node_or_null(rear_left_path)   as Node2D
	_wheels[3] = get_node_or_null(rear_right_path)  as Node2D

	# if any missing, try auto-discovery under player's RoadEffects
	if not _all_wheels_found():
		_auto_wire_wheels_from_player()

	# ensure overlay is transparent
	var sv := get_viewport()
	if sv is SubViewport:
		sv.transparent_bg = true

func _process(_dt: float) -> void:
	if _player == null or _pseudo3d == null:
		return

	# late-bind if prefab children arrived after _ready
	if not _all_wheels_found() and Engine.get_frames_drawn() % 10 == 0:
		_auto_wire_wheels_from_player()

	var rt := _get_rt()
	var drifting := _get_drifting()

	var should_draw := false
	if draw_while_drifting and drifting:
		should_draw = true
	elif draw_while_offroad and _is_offroadish(rt):
		should_draw = true

	if rt == Globals.RoadType.SINK or rt == Globals.RoadType.WALL:
		should_draw = false

	for i in range(4):
		var wn := _wheels[i]
		if wn == null:
			_close_stroke(i)
			continue

		# wheel -> screen px -> map UV -> overlay px
		var screen_px: Vector2 = wn.global_position
		var muv: Vector2 = _pseudo3d.call("screen_px_to_map_uv", screen_px)

		# invalid or NaN guard
		if not muv.is_finite():
			_close_stroke(i)
			continue

		var ov_size := get_viewport_rect().size
		var ov_px := Vector2(muv.x * ov_size.x, muv.y * ov_size.y)

		# keep strokes within the overlay bounds if requested
		if clamp_to_overlay:
			if ov_px.x < 0.0 or ov_px.y < 0.0 or ov_px.x > ov_size.x or ov_px.y > ov_size.y:
				_close_stroke(i)
				continue

		if should_draw:
			_append_point(i, ov_px, drifting)
		else:
			_close_stroke(i)

func _append_point(i: int, px: Vector2, drifting: bool) -> void:
	var L := _lines[i]
	if L == null:
		L = _new_stroke(i, drifting)
	# add only if moved enough
	if L.points.size() == 0:
		L.add_point(px)
	else:
		var last := L.points[L.points.size() - 1]
		if last.distance_to(px) >= min_segment_px:
			L.add_point(px)

func _close_stroke(i: int) -> void:
	var L := _lines[i]
	if L == null:
		return
	if fade_seconds > 0.0:
		var tw := L.create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
		tw.tween_property(L, "modulate:a", 0.0, fade_seconds)
		tw.finished.connect(Callable(L, "queue_free"))
	_lines[i] = null

func _new_stroke(i: int, drifting: bool) -> Line2D:
	var L := Line2D.new()
	L.width = width_px
	L.antialiased = true
	L.joint_mode = Line2D.LINE_JOINT_ROUND
	L.begin_cap_mode = Line2D.LINE_CAP_ROUND
	L.end_cap_mode = Line2D.LINE_CAP_ROUND
	if drifting:
		L.default_color = color_drift
	else:
		L.default_color = color_offroad
	if brush_texture:
		L.texture = brush_texture
		L.texture_mode = Line2D.LINE_TEXTURE_TILE
	add_child(L)
	_lines[i] = L
	return L

func _is_offroadish(rt: int) -> bool:
	return rt == Globals.RoadType.OFF_ROAD or rt == Globals.RoadType.GRAVEL

func _get_rt() -> int:
	if _player and _player.has_method("ReturnOnRoadType"):
		return int(_player.call("ReturnOnRoadType"))
	return -1

func _get_drifting() -> bool:
	if _player and _player.has_method("ReturnIsDrifting"):
		return bool(_player.call("ReturnIsDrifting"))
	return false

func ClearAll() -> void:
	for i in range(4):
		if _lines[i]:
			_lines[i].queue_free()
			_lines[i] = null

# ---------------------- auto-discovery under player's RoadEffects ----------------------

func _all_wheels_found() -> bool:
	for i in range(4):
		if _wheels[i] == null:
			return false
	return true

func _auto_wire_wheels_from_player() -> void:
	if _player == null:
		return
	var re := _find_road_effects_node(_player)
	if re == null:
		return

	# Preferred: distinct front/rear wheel anchors
	if _wheels[0] == null: _wheels[0] = _find_first_of(re, ["FrontLeftWheel", "FrontLeft", "WheelFL", "FL"]) as Node2D
	if _wheels[1] == null: _wheels[1] = _find_first_of(re, ["FrontRightWheel","FrontRight","WheelFR","FR"]) as Node2D
	if _wheels[2] == null: _wheels[2] = _find_first_of(re, ["RearLeftWheel", "RearLeft", "WheelRL", "RL"]) as Node2D
	if _wheels[3] == null: _wheels[3] = _find_first_of(re, ["RearRightWheel","RearRight","WheelRR","RR"]) as Node2D

	# Fallback: only Left/Right exist (duplicate to front/rear)
	var lw := _find_first_of(re, ["LeftWheel", "WheelLeft"]) as Node2D
	var rw := _find_first_of(re, ["RightWheel","WheelRight"]) as Node2D
	if lw != null:
		if _wheels[0] == null: _wheels[0] = lw
		if _wheels[2] == null: _wheels[2] = lw
	if rw != null:
		if _wheels[1] == null: _wheels[1] = rw
		if _wheels[3] == null: _wheels[3] = rw

	# As an extra fallback, accept the "Special" nodes as anchors too
	var lws := _find_first_of(re, ["LeftWheelSpecial"]) as Node2D
	var rws := _find_first_of(re, ["RightWheelSpecial"]) as Node2D
	if lws != null:
		if _wheels[0] == null: _wheels[0] = lws
		if _wheels[2] == null: _wheels[2] = lws
	if rws != null:
		if _wheels[1] == null: _wheels[1] = rws
		if _wheels[3] == null: _wheels[3] = rws

func _find_road_effects_node(root: Node) -> Node:
	# Try common names first
	var n := root.get_node_or_null("RoadEffects")
	if n != null:
		return n
	n = root.get_node_or_null("Road Type Effects")
	if n != null:
		return n
	# Deep search by name (single pass)
	var hit := root.find_child("RoadEffects", true, false)
	if hit != null:
		return hit
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
