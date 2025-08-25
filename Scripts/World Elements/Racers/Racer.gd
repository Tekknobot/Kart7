# Racer.gd
class_name Racer
extends WorldElement

var _inputDir : Vector2 = Vector2.ZERO

@export_category("Racer Movement Settings")
@export var _maxMovementSpeed : float = 150.0
@export var _movementAccel : float = 120.0
@export var _movementDeaccel : float = 120.0
var _currentMoveDirection : int = 0
var _movementSpeed : float = 0.0
var _speedMultiplier : float = 1.0
var _velocity : Vector3 = Vector3.ZERO
var _onRoadType : Globals.RoadType = Globals.RoadType.VOID

@export_category("Racer Collision Settings")
@export var _collisionHandler : Node
var _bumpDir : Vector3 = Vector3.ZERO
var _isPushedBack : bool = false
var _pushbackTime : float = 0.3
var _currPushbackTime : float = 0.0
var _bumpIntensity : float = 2.0

# --- DROP-IN: references required by helpers ---
@export var path_ref: NodePath
@export var pseudo3d_ref: NodePath
@export var angle_sprite_path: NodePath = ^"GFX/AngleSprite"
@export var lane_offset: float = 0.0   # +right, -left relative to path tangent

# --- Path-following state (if used by AI) ---
var _uv_points: PackedVector2Array = PackedVector2Array()
var _s: float = 0.0         # distance along path
var _heading: float = 0.0   # cached facing in map space (radians)

var _path = null
var _pseudo = null
var _ang = null

const DIRECTIONS: int = 12
@export var sheet_uses_mirroring := false  # set true only if you have a 6-frame sheet mirrored

# --- AI auto-launch (ignored for player unless you enable it) ---
@export var ai_auto_launch        : bool  = true     # enable for AI racers
@export var ai_launch_delay_s     : float = 2    # wait after spawn
@export var ai_launch_time_s      : float = 5     # time to reach target speed
@export var ai_target_speed       : float = 1.0    # px/s (or whatever your units are)

# --- AI auto-throttle (simple ramp from 0 to a target speed) ---
@export var ai_auto_throttle      : bool  = false     # enable for AI racers
@export var ai_throttle_delay_s   : float = 2     # wait after spawn
@export var ai_accel_per_sec      : float = 1.0    # how fast we ramp (units/s^2)

var _ai_timer_s    : float = -1.0
var _ai_launched   : bool  = false

# --- scale stabilizers (for pseudo-3D) ---
@export var scale_near_soft   : float = 128.0   # px of "soft near plane" for scale
@export var scale_use_abs     : bool  = false   # true = scale by |depth| (symmetric forward/back)
@export var scale_half_life_s : float = 0.12   # smooth scale target (seconds to move half the gap)

var _sc_smooth: float = 0.0
var _nodes_ready := false

var _seg_i: int = 0         # cached segment index for _s
var _last_s: float = -1.0   # last distance used (px), to detect direction

@export_category("Racer Surface Multipliers")
@export var mult_road: float     = 1.00
@export var mult_gravel: float   = 0.85
@export var mult_offroad: float  = 0.70
@export var mult_sink: float     = 0.20
@export var mult_void: float     = 0.00

# Optional: also scale acceleration by surface grip
@export var accel_surface_gain: float = 1.0  # 0=no effect, 1=full effect

func _ensure_nodes() -> void:
	if _nodes_ready:
		return
	_path = get_node_or_null(path_ref)
	_pseudo = get_node_or_null(pseudo3d_ref)
	if angle_sprite_path != NodePath():
		_ang = get_node_or_null(angle_sprite_path)
	_nodes_ready = true

func _smooth_scalar(prev: float, target: float, dt: float, half_life: float) -> float:
	if half_life <= 0.0:
		return target
	var a := 1.0 - pow(0.5, dt / half_life)
	return prev + (target - prev) * a

func _spr_or_null() -> CanvasItem:
	return ReturnSpriteGraphic()

func _set_frame_idx(dir_idx: int) -> void:
	var spr := _spr_or_null()
	if spr == null: return
	if spr is Sprite2D:
		var s := spr as Sprite2D
		if sheet_uses_mirroring:
			var HALF := 6
			var idx := (dir_idx % (HALF * 2) + (HALF * 2)) % (HALF * 2)
			var left_side := idx >= HALF
			var col := idx % HALF
			if s.hframes != HALF:
				s.hframes = HALF; s.vframes = 1
			s.frame = col
			s.flip_h = left_side
		else:
			if s.hframes != DIRECTIONS:
				s.hframes = DIRECTIONS; s.vframes = 1
			s.flip_h = false
			s.frame = clamp(dir_idx, 0, DIRECTIONS - 1)
	elif "frame" in spr:
		spr.frame = clamp(dir_idx, 0, DIRECTIONS - 1)

func _set_turn_angle(angle_deg: float) -> void:
	var step := 360.0 / float(DIRECTIONS)  # 30°
	var idx := int(floor((wrapf(angle_deg, 0.0, 360.0) + step * 0.5) / step)) % DIRECTIONS
	_set_frame_idx(idx)

func _choose_and_set_direction(cam_yaw: float, heading: float, angle_offset_deg: float = 0.0, clockwise := true) -> void:
	var theta_cam := wrapf(heading - cam_yaw, -PI, PI)
	var deg := rad_to_deg(theta_cam)
	deg = wrapf(deg + angle_offset_deg, 0.0, 360.0)
	if not clockwise: deg = 360.0 - deg
	_set_turn_angle(deg)

func _ready() -> void:
	_path = get_node_or_null(path_ref)
	_pseudo = get_node_or_null(pseudo3d_ref)
	if angle_sprite_path != NodePath():
		_ang = get_node_or_null(angle_sprite_path)

func _process(dt: float) -> void:
	_ensure_nodes()
	if _pseudo != null:
		var cam_pos := Globals.get_camera_map_position()
		update_screen_transform(cam_pos)
		update_angle_sprite()
	_tick_auto_throttle(dt)

func set_points_uv(uv: PackedVector2Array) -> void:
	_uv_points = uv

func _get_nodes() -> Dictionary:
	var result: Dictionary = {}
	result["path"] = get_node_or_null(path_ref)
	result["pseudo"] = get_node_or_null(pseudo3d_ref)
	if angle_sprite_path != NodePath():
		result["angle_sprite"] = get_node_or_null(angle_sprite_path)
	else:
		result["angle_sprite"] = null
	return result

# Position on the map from (distance along path + lateral lane offset)
func get_map_space_position() -> Vector2:
	var P: Vector2 = _path_point_at_distance(_s)
	var T: Vector2 = _path_tangent_at_distance(_s)
	if T.length_squared() == 0.0:
		T = Vector2.RIGHT
	else:
		T = T.normalized()
	var N: Vector2 = Vector2(-T.y, T.x)
	return P + N * lane_offset

# Kart forward = path tangent (good enough for SNES-style billboards)
func get_kart_forward_map() -> Vector2:
	var T: Vector2 = _path_tangent_at_distance(_s)
	if T.length_squared() == 0.0:
		return Vector2.RIGHT
	return T.normalized()

# Compute camera-space components for projection
func _camera_components(camera_pos: Vector2, cam_f: Vector2, world: Vector2) -> Dictionary:
	var cam_to := world - camera_pos
	var depth := cam_to.dot(cam_f)                            # forward (z-like)
	var right := Vector2(cam_f.y, -cam_f.x)                   # camera right (x-like)
	var lateral := cam_to.dot(right)
	var out: Dictionary = {}
	out["depth"] = depth
	out["lateral"] = lateral
	return out

# Place & scale the racer on screen based on depth and lateral
func update_screen_transform(camera_pos: Vector2) -> void:
	var d := _get_nodes()
	var pseudo = d["pseudo"]
	_ensure_nodes()
	if _pseudo == null:
		return

	var cam_f: Vector2 = pseudo.get_camera_forward_map()
	var world: Vector2 = get_map_space_position()
	var comps := _camera_components(camera_pos, cam_f, world)

	var horizon_y := 100.0           # pixels from top for horizon
	var focal := 220.0               # perspective multiplier
	var min_depth := 20.0            # avoid absurd scale near zero

	var depth_val = comps["depth"]
	if depth_val < min_depth:
		depth_val = min_depth

	var lateral_val = comps["lateral"]

	# --- projection (unchanged, but guard tiny depth) ---
	var depth_proj = depth_val
	if depth_proj < 0.0001:
		depth_proj = 0.0001   # avoid division blow-up for screen placement

	var screen_x =  (lateral_val * focal) / depth_proj
	var screen_y =  horizon_y + (focal / depth_proj)

	# --- scale: use soft-clamped depth, optionally absolute, then smooth ---
	var depth_for_scale = depth_val
	if scale_use_abs:
		depth_for_scale = abs(depth_for_scale)
	if depth_for_scale < scale_near_soft:
		depth_for_scale = scale_near_soft

	var sc_target = pseudo.depth_scale(depth_for_scale)
	_sc_smooth = _smooth_scalar(_sc_smooth, sc_target, get_process_delta_time(), scale_half_life_s)

	global_position = pseudo.global_position + Vector2(screen_x, screen_y)
	scale = Vector2.ONE * _sc_smooth


	var zi := int(100000.0 - comps["depth"])
	z_index = zi

	visible = comps["depth"] > 0.0

# Drive the angle-animated sprite (right-frames + flip for left handled in the script)
func update_angle_sprite() -> void:
	var d := _get_nodes()
	var ang = d["angle_sprite"]
	var pseudo = d["pseudo"]
	if ang == null or pseudo == null:
		return
	var cam_f = pseudo.get_camera_forward_map()
	var kart_f := get_kart_forward_map()
	if ang.has_method("set_camera_forward"):
		ang.call("set_camera_forward", cam_f)
	if ang.has_method("set_kart_forward"):
		ang.call("set_kart_forward", kart_f)
	if ang.has_method("update_from_relative_angle"):
		ang.call("update_from_relative_angle")

# --- Movement API you already had ---

func ReturnMovementSpeed() -> float:
	return _movementSpeed 

func ReturnCurrentMoveDirection() -> int:
	return _currentMoveDirection

func UpdateVelocity(mapForward : Vector3) -> void:
	_velocity = Vector3.ZERO
	if _movementSpeed == 0.0:
		return
	var forward : Vector3 = mapForward * float(_currentMoveDirection)
	_velocity = (forward * _movementSpeed) * get_process_delta_time()

func ReturnVelocity() -> Vector3:
	return _velocity

func HandleRoadType(nextPixelPos : Vector2i, roadType : Globals.RoadType) -> void:
	if roadType == _onRoadType:
		return
	_onRoadType = roadType
	_spriteGFX.self_modulate.a = 1.0

	match roadType:
		Globals.RoadType.VOID:
			_spriteGFX.self_modulate.a = 0.0
			_speedMultiplier = mult_void
		Globals.RoadType.ROAD:
			_speedMultiplier = mult_road
		Globals.RoadType.GRAVEL:
			_speedMultiplier = mult_gravel
		Globals.RoadType.OFF_ROAD:
			_speedMultiplier = mult_offroad
		Globals.RoadType.SINK:
			_spriteGFX.self_modulate.a = 0.0
			_speedMultiplier = mult_sink
		Globals.RoadType.WALL:
			# keep current multiplier (bounce/stop handled elsewhere)
			_speedMultiplier = _speedMultiplier

func ReturnOnRoadType() -> Globals.RoadType:
	return _onRoadType

func UpdateMovementSpeed() -> void:
	if _inputDir.y != 0.0:
		if _inputDir.y != float(_currentMoveDirection) and _movementSpeed > 0.0:
			Deaccelerate()
		else:
			Accelerate()
	else:
		if abs(_movementSpeed) > 0.0:
			Deaccelerate()

func Accelerate() -> void:
	_movementSpeed += _movementAccel * get_process_delta_time()
	_movementSpeed = min(_movementSpeed, _maxMovementSpeed * _speedMultiplier)
	if _currentMoveDirection == int(_inputDir.y):
		return
	_currentMoveDirection = int(_inputDir.y)

func Deaccelerate() -> void:
	_movementSpeed -= _movementDeaccel * get_process_delta_time()
	_movementSpeed = max(_movementSpeed, 0.0)
	if _movementSpeed == 0.0 and _currentMoveDirection != int(_inputDir.y):
		_currentMoveDirection = int(_inputDir.y)

func SetCollisionBump(bumpDir : Vector3) -> void:
	if not _isPushedBack:
		_bumpDir = bumpDir
		_isPushedBack = true
		_currPushbackTime = _pushbackTime

func ApplyCollisionBump() -> void:
	_currPushbackTime -= get_process_delta_time()
	if _currPushbackTime <= 0.0:
		_isPushedBack = false
	else:
		var bumpVelocity : Vector3 = _bumpDir * (_bumpIntensity * (_currPushbackTime / _pushbackTime))
		Deaccelerate()
		SetMapPosition(_mapPosition + bumpVelocity)

var _path_pts: PackedVector2Array = PackedVector2Array()
var _path_tan: PackedVector2Array = PackedVector2Array()
var _path_len: PackedFloat32Array = PackedFloat32Array()
var _path_total: float = 0.0
var _path_ready: bool = false

func _ensure_path_cached() -> void:
	if _path_ready:
		return
	var d := _get_nodes()
	var overlay = d["path"]
	var pseudo  = d["pseudo"]
	if overlay == null or pseudo == null:
		return
	if not (pseudo is Sprite2D):
		return
	var tex: Texture2D = (pseudo as Sprite2D).texture
	if tex == null:
		return
	var tex_w := float(tex.get_size().x)

	var uv: PackedVector2Array = PackedVector2Array()
	if overlay.has_method("get_path_points_uv_transformed"):
		uv = overlay.call("get_path_points_uv_transformed")
	elif overlay.has_method("get_path_points_uv"):
		uv = overlay.call("get_path_points_uv")
	if uv.size() < 2:
		return

	var pts := PackedVector2Array()
	for u in uv:
		var v := Vector2(u.x, 1.0 - u.y)
		pts.append(v * tex_w)

	if pts.size() >= 2:
		var a := pts[0]
		var b := pts[pts.size() - 1]
		if a.distance_to(b) <= (1.0 / 1024.0):
			pts.remove_at(pts.size() - 1)
	if pts.size() < 2:
		return

	var tans := PackedVector2Array()
	var lens := PackedFloat32Array()
	lens.resize(pts.size())
	lens[0] = 0.0
	var total := 0.0
	for i in range(pts.size()):
		var j := (i + 1) % pts.size()
		var seg := pts[j] - pts[i]
		var t := seg
		if t.length_squared() > 0.0:
			t = t.normalized()
		else:
			t = Vector2.RIGHT
		tans.append(t)
		if i < pts.size() - 1:
			total += seg.length()
			lens[i + 1] = total
	total += (pts[0] - pts[pts.size() - 1]).length()

	_path_pts = pts
	_path_tan = tans
	_path_len = lens
	_path_total = total
	_path_ready = true

func _path_point_at_distance(s: float) -> Vector2:
	_ensure_path_cached()
	if not _path_ready or _path_pts.size() == 0:
		return Vector2.ZERO

	_seek_segment_for_s(s)
	var i := _seg_i
	var a := _path_len[i]
	var b := _path_len[i + 1] if (i + 1) < _path_len.size() else _path_total
	var denom = max(b - a, 0.0001)
	var t = (fposmod(s, _path_total) - a) / denom
	var p0 := _path_pts[i]
	var p1 := _path_pts[(i + 1) % _path_pts.size()]
	return p0.lerp(p1, t)

func _path_tangent_at_distance(s: float) -> Vector2:
	_ensure_path_cached()
	if not _path_ready or _path_tan.size() == 0:
		return Vector2.RIGHT

	_seek_segment_for_s(s)
	return _path_tan[_seg_i]

func _path_tangent_at_index(i: int) -> Vector2:
	_ensure_path_cached()
	if not _path_ready or _path_tan.size() == 0:
		return Vector2.RIGHT
	var n := _path_tan.size()
	var k := i % n
	if k < 0:
		k += n
	return _path_tan[k]

func ArmAutoThrottle(delay_s: float = -1.0) -> void:
	# Call this right after you place the AI on the track
	if delay_s >= 0.0:
		_ai_timer_s = delay_s
	else:
		_ai_timer_s = ai_throttle_delay_s
	_ai_launched = false
	_movementSpeed = 0.0
	_currentMoveDirection = 1
	_inputDir.y = 0.0   # hold until timer elapses

func _tick_auto_throttle(dt: float) -> void:
	if not ai_auto_throttle:
		return

	if _ai_timer_s > 0.0:
		_ai_timer_s = max(0.0, _ai_timer_s - dt)
		return

	if _movementSpeed >= ai_target_speed:
		_ai_launched = false
		return

	if not _ai_launched:
		_ai_launched = true
		_currentMoveDirection = 1
		if _inputDir.y != 1.0:
			_inputDir.y = 1.0

	# ramp
	_movementSpeed = min(ai_target_speed, _movementSpeed + ai_accel_per_sec * dt)

func _seek_segment_for_s(s: float) -> void:
	_ensure_path_cached()
	if not _path_ready or _path_len.size() <= 1:
		_seg_i = 0
		return

	var total := _path_total
	var ss := fposmod(s, total)

	# If first time, binary-ish find (coarse); else step locally
	if _last_s < 0.0:
		_seg_i = 0
		while _seg_i < _path_len.size() - 1 and _path_len[_seg_i + 1] < ss:
			_seg_i += 1
	else:
		# Move forward or backward a few steps
		if ss >= _last_s:
			# advancing
			while _seg_i < _path_len.size() - 1 and _path_len[_seg_i + 1] < ss:
				_seg_i += 1
		else:
			# going backward
			while _seg_i > 0 and _path_len[_seg_i] > ss:
				_seg_i -= 1

	# Guard bounds
	if _seg_i < 0: _seg_i = 0
	if _seg_i > _path_len.size() - 2: _seg_i = _path_len.size() - 2
	_last_s = ss
