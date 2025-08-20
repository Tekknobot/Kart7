# Scripts/World Elements/Racers/Opponent.gd
extends Racer

@export_category("Scene References")
@export var path_node: NodePath
@export var map_node: NodePath
@export var sprite_handler_node: NodePath

@export_category("Path Following")
@export var lookahead_pixels := 80.0   # tune to match WaypointPath units
@export var waypoint_radius := 24.0
@export var steering_gain := 2.0
@export var steering_damp := 0.40
@export var base_target_speed := 120.0
@export var slow_down_on_turns := true
@export var turn_slowdown_mul := 0.75

var _path_ref: Node = null
var _map_ref: Node = null
var _sprite_handler_ref: Node = null
var _wp_idx := 0
var _last_lateral := 0.0

func _ready() -> void:
	if path_node != NodePath():
		_path_ref = get_node_or_null(path_node)
	if map_node != NodePath():
		_map_ref = get_node_or_null(map_node)
	if sprite_handler_node != NodePath():
		_sprite_handler_ref = get_node_or_null(sprite_handler_node)

	# Infer map size from texture width if available (optional, for your Racer base)
	var map_size := 1024
	if _map_ref and ("texture" in _map_ref):
		var tex = _map_ref.texture
		if tex:
			map_size = tex.get_size().x
	Setup(map_size)

	_register_with_sprite_handler()

func _register_with_sprite_handler() -> void:
	if _sprite_handler_ref == null:
		return
	if _sprite_handler_ref.has_method("AddWorldElement"):
		_sprite_handler_ref.AddWorldElement(self)
		return
	var candidates := ["_worldElements", "worldElements", "elements"]
	for c in candidates:
		if c in _sprite_handler_ref:
			var arr = _sprite_handler_ref.get(c)
			if arr is Array and not arr.has(self):
				arr.append(self)
				_sprite_handler_ref.set(c, arr)
			return

func Setup(mapSize: int) -> void:
	SetMapSize(mapSize)

func _process(_delta: float) -> void:
	var fwd := Vector3(0,0,1)
	if _map_ref and _map_ref.has_method("ReturnForward"):
		fwd = _map_ref.ReturnForward()
	Update(fwd)

func Update(map_forward: Vector3) -> void:
	if _path_ref == null:
		return
	if _isPushedBack:
		ApplyCollisionBump()

	# --- 1) Path points ---
	var wp: PackedVector2Array = PackedVector2Array()
	if _path_ref and ("points" in _path_ref):
		wp = _path_ref.points
	if wp.size() == 0:
		return

	# world/map position in the same 2D plane as path points
	var pos2 := Vector2(_mapPosition.x, _mapPosition.z)

	# choose lookahead index
	if _path_ref.has_method("find_lookahead_index"):
		_wp_idx = _path_ref.find_lookahead_index(pos2, lookahead_pixels, _wp_idx)
		_wp_idx = clampi(_wp_idx, 0, wp.size() - 1)
	else:
		# naive: advance when close
		if pos2.distance_to(wp[_wp_idx]) <= waypoint_radius:
			_wp_idx = (_wp_idx + 1) % wp.size()

	# get target point
	var tgt2: Vector2
	if _path_ref.has_method("get_point"):
		tgt2 = _path_ref.get_point(_wp_idx)
	else:
		tgt2 = wp[_wp_idx]

	# --- 2) Steering using lateral error ---
	var to_tgt := Vector3(tgt2.x - _mapPosition.x, 0.0, tgt2.y - _mapPosition.z)
	var dist := to_tgt.length()
	if dist > 0.001:
		to_tgt /= dist

	var right_vec := Vector3(-map_forward.z, 0.0, map_forward.x).normalized()
	var lateral := to_tgt.dot(right_vec)
	var dt = max(get_process_delta_time(), 0.0001)
	var d_lat = (lateral - _last_lateral) / dt
	_last_lateral = lateral

	var steer = clamp(-steering_gain * lateral - steering_damp * d_lat, -1.0, 1.0)
	_inputDir.x = steer

	# --- 3) Throttle control ---
	var target_speed := base_target_speed
	if slow_down_on_turns:
		target_speed = lerp(base_target_speed * turn_slowdown_mul, base_target_speed, 1.0 - clamp(abs(steer), 0.0, 1.0))

	_inputDir.y = 1.0 if ReturnMovementSpeed() < target_speed else 0.0
	UpdateMovementSpeed()

	# --- 4) Integrate & collisions (unchanged) ---
	UpdateVelocity(map_forward)
	var next_pos := _mapPosition + ReturnVelocity()
	var next_px := Vector2i(ceil(next_pos.x), ceil(next_pos.z))

	if _collisionHandler and _collisionHandler.IsCollidingWithWall(Vector2i(ceil(next_pos.x), ceil(_mapPosition.z))):
		next_pos.x = _mapPosition.x
		SetCollisionBump(Vector3(-sign(ReturnVelocity().x), 0, 0))
	if _collisionHandler and _collisionHandler.IsCollidingWithWall(Vector2i(ceil(_mapPosition.x), ceil(next_pos.z))):
		next_pos.z = _mapPosition.z
		SetCollisionBump(Vector3(0, 0, -sign(ReturnVelocity().z)))

	SetMapPosition(next_pos)
	if _collisionHandler:
		HandleRoadType(next_px, _collisionHandler.ReturnCurrentRoadType(next_px))

	# --- 5) Advance waypoint when close (backup if no lookahead) ---
	if pos2.distance_to(tgt2) <= waypoint_radius:
		_wp_idx = (_wp_idx + 1) % wp.size()
