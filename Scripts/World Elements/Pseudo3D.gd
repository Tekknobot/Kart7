# Pseudo3D.gd
extends Sprite2D

@export_category("Map Settings : Rotation")
@export var _mapStartRotationAngle : Vector2
@export var _mapMaxRotationSpeed : float
@export var _mapAccelRotationSpeed : float
@export var _mapDeaccelRotationSpeed : float
@export var _rotationRadius : float
var _mapRotSpeed : float
var _currRotDir := 0

# Perspective sizing
@export var gfx_path: NodePath         # drag your Sprite2D child here (e.g., "GFX")
@export var size_k: float = 0.9        # scale factor numerator
@export var size_min: float = 0.35     # clamp min scale
@export var size_max: float = 2.0      # clamp max scale

# Path overlay & opponents
@export var path_overlay_viewport: SubViewport
@export var path_overlay_node: NodePath  # the PathOverlay2D inside that SubViewport
@export var opponent_nodes: Array[NodePath] = []

@export_category("Map Settings : Position")
@export var _mapVerticalPosition : float
var _mapPosition : Vector3
var _mapRotationAngle : Vector2
var _finalMatrix : Basis

func _bind_path_overlay_texture() -> void:
	if material != null and path_overlay_viewport != null:
		var tex := path_overlay_viewport.get_texture()
		if tex != null:
			material.set_shader_parameter("pathOverlay", tex)

func Setup(screenSize : Vector2, player : Racer) -> void:
	scale = screenSize / texture.get_size().x
	_mapPosition = Vector3(player.ReturnMapPosition().x, _mapVerticalPosition, player.ReturnMapPosition().z)
	_mapRotationAngle = _mapStartRotationAngle
	KeepRotationDistance(player)
	_bind_path_overlay_texture()
	UpdateShader()
	_update_opponents_view_bindings()   # prime once

func Update(player: Racer) -> void:
	RotateMap(player.ReturnPlayerInput().x, player.ReturnMovementSpeed())
	KeepRotationDistance(player)
	UpdateShader()
	_update_opponents_view_bindings()   # every frame

func RotateMap(rotDir : int, speed : float) -> void:
	if rotDir != 0 and abs(speed) > 0.0:
		AccelMapRotation(rotDir)
	else:
		DeaccelMapRotation()

	if abs(_mapRotSpeed) > 0.0:
		var incrementAngle : float = float(_currRotDir) * _mapRotSpeed * get_process_delta_time()
		_mapRotationAngle.y += incrementAngle
		_mapRotationAngle.y = WrapAngle(_mapRotationAngle.y)

func AccelMapRotation(rotDir : int) -> void:
	if rotDir != _currRotDir and _mapRotSpeed > 0.0:
		DeaccelMapRotation()
		if _mapRotSpeed == 0.0:
			_currRotDir = rotDir
	else:
		_mapRotSpeed += _mapAccelRotationSpeed * get_process_delta_time()
		_mapRotSpeed = min(_mapRotSpeed, _mapMaxRotationSpeed)
		_currRotDir = rotDir

func DeaccelMapRotation() -> void:
	if abs(_mapRotSpeed) > 0.0:
		_mapRotSpeed -= _mapDeaccelRotationSpeed * get_process_delta_time()
		_mapRotSpeed = max(_mapRotSpeed, 0.0)

func KeepRotationDistance(racer : Racer) -> void:
	var relPos : Vector3 = Vector3(
		(_rotationRadius / texture.get_size().x) * sin(_mapRotationAngle.y),
		_mapPosition.y - racer.ReturnMapPosition().y,
		(_rotationRadius / texture.get_size().x) * cos(_mapRotationAngle.y)
	)
	_mapPosition = racer.ReturnMapPosition() + relPos

func UpdateShader() -> void:
	var yawMatrix : Basis = Basis(
		Vector3(cos(_mapRotationAngle.y), -sin(_mapRotationAngle.y), 0.0),
		Vector3(sin(_mapRotationAngle.y),  cos(_mapRotationAngle.y), 0.0),
		Vector3(0.0, 0.0, 1.0)
	)

	var pitchMatrix : Basis = Basis(
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, cos(_mapRotationAngle.x), -sin(_mapRotationAngle.x)),
		Vector3(0.0, sin(_mapRotationAngle.x),  cos(_mapRotationAngle.x))
	)

	var rotationMatrix : Basis = yawMatrix * pitchMatrix

	var e := _safe_exp(_mapPosition.y)
	var translationMatrix : Basis = Basis(
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.0, 1.0, 0.0),
		Vector3(_mapPosition.x * e, _mapPosition.z * e, e)
	)

	_finalMatrix = translationMatrix * rotationMatrix
	if material != null:
		material.set_shader_parameter("mapMatrix", _finalMatrix)

func WrapAngle(angle : float) -> float: 
	if rad_to_deg(angle) > 360.0:
		return angle - deg_to_rad(360.0)
	elif rad_to_deg(angle) < 0.0:
		return angle + deg_to_rad(360.0)
	return angle

func ReturnForward() -> Vector3: return Vector3(sin(_mapRotationAngle.y), 0.0, cos(_mapRotationAngle.y))
func ReturnWorldMatrix() -> Basis: return _finalMatrix
func ReturnMapRotation() -> float: return _mapRotationAngle.y

func _update_opponents_view_bindings() -> void:
	var scr: Vector2 = get_viewport_rect().size
	var f3: Vector3 = ReturnForward()
	var cam_f: Vector2 = Vector2(f3.x, f3.z).normalized()

	var overlay := get_node_or_null(path_overlay_node)
	if overlay != null and overlay.has_method("set_world_and_screen"):
		overlay.call("set_world_and_screen", _finalMatrix, scr)

	for np in opponent_nodes:
		var ai: Node = get_node_or_null(np)
		if ai != null:
			if ai.has_method("set_world_and_screen"):
				ai.call("set_world_and_screen", _finalMatrix, scr)
			if ai.has_method("set_camera_forward"):
				ai.call("set_camera_forward", cam_f)

func SetYaw(angle: float) -> void:
	_mapRotationAngle.y = angle
	UpdateShader()
	_update_opponents_view_bindings()

func _safe_exp(y: float) -> float:
	return exp(clamp(y, -6.0, 6.0))

func SetPathPoints(p: PackedVector2Array) -> void:
	var n := get_node_or_null(path_overlay_node)
	if n != null:
		if n.has_method("set_points"):
			n.call("set_points", p)
		elif n.has_method("set_points_uv"):
			n.call("set_points_uv", p)
	_bind_path_overlay_texture()

	if n != null:
		var uv: PackedVector2Array = PackedVector2Array()
		if n.has_method("get_path_points_uv_transformed"):
			uv = n.call("get_path_points_uv_transformed")
		elif n.has_method("get_path_points_uv"):
			uv = n.call("get_path_points_uv")

		if uv.size() > 1:
			for np in opponent_nodes:
				var ai2: Node = get_node_or_null(np)
				if ai2 != null and ai2.has_method("set_points_uv"):
					ai2.call("set_points_uv", uv)

# Forward direction of the "camera" in MAP space, derived from yaw
func get_camera_forward_map() -> Vector2:
	var f3: Vector3 = ReturnForward()   # (sin(yaw), 0, cos(yaw))
	var v := Vector2(f3.x, f3.z)
	if v.length_squared() == 0.0:
		return Vector2(0, 1)
	return v.normalized()

# Projective scale by forward depth; tune with your existing exports (size_k/min/max)
func depth_scale(depth: float) -> float:
	var d := depth
	if d < 0.0:
		d = 0.0
	return clamp(size_k / (size_k + d), size_min, size_max)
