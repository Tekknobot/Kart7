# SkidTrailWorld.gd (Godot 4)
# Skid marks that stay on the ground while the map moves (Mode 7).
# Stores wheel positions in MAP SPACE (Vector3 x,z) and reprojects to screen each frame.

extends Line2D

@export var player: Racer                  # drag your Player
@export var map_node: Node                 # drag the Pseudo3D node (has ReturnWorldMatrix/ReturnForward)
@export var map_size: int = 1024           # full texture size (e.g. 1024)
@export var is_left_wheel: bool = true

# Emission & shaping
@export var min_speed_to_emit: float = 10.0
@export var spacing_map_px: float = 4.0    # add history point every N pixels of MAP-space movement
@export var max_history_points: int = 160  # history length cap (map points)
@export var fade_points_per_sec: float = 80.0
@export var fade_when_off: bool = true

# Wheel local offsets in MAP pixels relative to kart center
@export var lateral_offset_px: float = 10.0
@export var longitudinal_offset_px: float = -6.0

# Visual width
@export var base_width: float = 3.0
@export var max_width: float = 6.0
@export var width_scales_with_speed: bool = true

# Projection centering (many mode-7 setups expect origin at map center)
@export var center_on_map: bool = true

# Debug
@export var debug_always_emit: bool = false
@export var debug_color: Color = Color(0,0,0,1.0)  # set alpha; gradient handles fade to 0

var _emitting: bool = false
var _history: Array[Vector3] = []     # store MAP-space wheel positions (x, 0, z)
var _last_sample: Vector3 = Vector3.INF

func _ready() -> void:
	antialiased = true
	joint_mode = LINE_JOINT_ROUND
	begin_cap_mode = LINE_CAP_ROUND
	end_cap_mode = LINE_CAP_ROUND
	set_as_top_level(true)
	global_position = Vector2.ZERO
	z_as_relative = false
	z_index = 1000

	# Simple dark -> transparent gradient (you can style neon here)
	var g := Gradient.new()
	g.colors  = PackedColorArray([debug_color, Color(debug_color.r, debug_color.g, debug_color.b, 0.0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	gradient = g

	clear_points()
	visible = false

func set_emitting(on: bool) -> void:
	_emitting = on
	if on:
		visible = true
	else:
		if not fade_when_off:
			_history.clear()
			clear_points()
			visible = false

func _process(delta: float) -> void:
	if player == null or map_node == null:
		return

	# Width vs speed
	if width_scales_with_speed:
		var t: float = clampf(player.ReturnMovementSpeed() / player._maxMovementSpeed, 0.0, 1.0)
		width = lerp(base_width, max_width, t)
	else:
		width = base_width

	var want_emit: bool = (_emitting and player.ReturnMovementSpeed() >= min_speed_to_emit) or debug_always_emit

	# Sample current wheel position in MAP space
	var wheel_map: Vector3 = _compute_wheel_map_position()

	# Append sample if moved enough in map space
	if want_emit:
		if _last_sample == Vector3.INF or _map_distance_xz(_last_sample, wheel_map) >= spacing_map_px:
			_history.append(wheel_map)
			_last_sample = wheel_map
			# Cap history
			while _history.size() > max_history_points:
				_history.pop_front()
	else:
		# Fade: trim from the head
		if fade_when_off and _history.size() > 0:
			var rm: int = int(fade_points_per_sec * delta)
			while rm > 0 and _history.size() > 0:
				_history.pop_front()
				rm -= 1
			if _history.size() == 0:
				visible = false
				_last_sample = Vector3.INF

	# Reproject whole history to screen and draw it "backwards"
	# (older points behind, latest near the wheel)
	if _history.size() > 0:
		visible = true
		var pts := PackedVector2Array()
		pts.resize(_history.size())
		var wm: Basis = map_node.ReturnWorldMatrix()
		for i in _history.size():
			var p: Vector3 = _history[i]
			var pp: Vector3 = p
			if center_on_map:
				pp.x -= map_size * 0.5
				pp.z -= map_size * 0.5
			var tp: Vector3 = wm * pp
			if tp.z <= 0.0001:
				# behind camera; skip by reusing prior or clamp
				var idx_prev: int = max(i-1, 0)
				pts[i] = pts[idx_prev] if i > 0 else Vector2(-9999, -9999)
			else:
				var screen: Vector2 = Vector2(tp.x / tp.z, tp.y / tp.z)
				screen = (screen + Vector2(0.5, 0.5)) * Globals.screenSize
				pts[i] = screen
		points = pts
	else:
		clear_points()

func _compute_wheel_map_position() -> Vector3:
	# Kart center in MAP px (x,z)
	var center01: Vector3 = player.ReturnMapPosition()  # (0..1)
	var center_px: Vector3 = Vector3(center01.x * map_size, 0.0, center01.y * map_size)

	# Map-space basis
	var fwd: Vector3 = map_node.ReturnForward().normalized()
	var right: Vector3 = Vector3(fwd.z, 0.0, -fwd.x)    # flip if your handedness disagrees

	var lat: float
	if is_left_wheel:
		lat = -abs(lateral_offset_px)
	else:
		lat = abs(lateral_offset_px)

	return center_px + right * lat + fwd * longitudinal_offset_px

func _map_distance_xz(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return sqrt(dx * dx + dz * dz)
