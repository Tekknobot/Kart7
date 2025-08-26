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

var _opponents: Array[Node] = []
var _overlay_node: Node = null
var _last_matrix: Basis

# --- Finish Camera ---
@export var finish_orbit_speed: float = 0.4    # rad/s around player
@export var finish_zoom_k: float = 1.5         # bigger = closer look (affects depth_scale)
@export var finish_duration: float = 3.0       # seconds for zoom ease

var _finish_mode: bool = false

const REARVIEW_ACTION: StringName = "RearView"
func _rearview_on() -> bool:
	return Input.is_action_pressed(REARVIEW_ACTION)

func _ready():
	# cache once
	for np in opponent_nodes:
		var n := get_node_or_null(np)
		if n != null:
			_opponents.append(n)
	_overlay_node = get_node_or_null(path_overlay_node)
	_last_matrix = Basis()
	
	_ensure_rearview_binding()

func _process(_dt):
	if not InputMap.has_action(REARVIEW_ACTION):
		if Engine.get_frames_drawn() % 30 == 0:
			print("Missing action: ", REARVIEW_ACTION)
	else:
		if Input.is_action_pressed(REARVIEW_ACTION):
			if Engine.get_frames_drawn() % 15 == 0:
				print(REARVIEW_ACTION, " held")

func _ensure_rearview_binding() -> void:
	# Create the action if it doesn't exist
	if not InputMap.has_action(REARVIEW_ACTION):
		InputMap.add_action(REARVIEW_ACTION)

	# Clear duplicates so we don't pile up bindings in hot-reload
	for ev in InputMap.action_get_events(REARVIEW_ACTION):
		InputMap.action_erase_event(REARVIEW_ACTION, ev)

	# Keyboard: Shift (Godot 4 doesn't distinguish left/right shift in the keycode API)
	var k := InputEventKey.new()
	k.keycode = Key.KEY_SHIFT
	InputMap.action_add_event(REARVIEW_ACTION, k)

	# Gamepad: Left Shoulder (L1/LB)
	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_LEFT_SHOULDER
	InputMap.action_add_event(REARVIEW_ACTION, jb)
		
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
	if _rearview_on():
		if Engine.get_frames_drawn() % 15 == 0:
			print("RearView held")
	
	if _finish_mode:
		# Ignore input; do a steady cinematic orbit around the player
		_mapRotSpeed = abs(finish_orbit_speed)
		_currRotDir = 1
		var incrementAngle: float = float(_currRotDir) * _mapRotSpeed * get_process_delta_time()
		_mapRotationAngle.y = WrapAngle(_mapRotationAngle.y + incrementAngle)

		KeepRotationDistance(player)
		UpdateShader()
		_update_opponents_view_bindings()
		return

	# --- Normal gameplay mode ---
	var steer = player.ReturnPlayerInput().x
	var speed := player.ReturnMovementSpeed()

	# While rear view is active, invert steer so controls feel right.
	if _rearview_on():
		steer = -steer

	RotateMap(steer, speed)
	KeepRotationDistance(player)

	# Temporarily yaw 180° for rendering when rear view is held.
	if _rearview_on():
		_mapRotationAngle.y = WrapAngle(_mapRotationAngle.y + PI)
		UpdateShader()
		_mapRotationAngle.y = WrapAngle(_mapRotationAngle.y - PI)
	else:
		UpdateShader()

	_update_opponents_view_bindings()

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
	# Only update if matrix changed meaningfully
	if _finalMatrix != _last_matrix:
		_last_matrix = _finalMatrix
		var scr: Vector2 = get_viewport_rect().size
		if _overlay_node != null and _overlay_node.has_method("set_world_and_screen"):
			_overlay_node.call("set_world_and_screen", _finalMatrix, scr)
	# (avoid get_node_or_null in a loop every frame)

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

func StartFinishCamera(player: Racer) -> void:
	_finish_mode = true
	# Smoothly zoom in by animating size_k
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "size_k", finish_zoom_k, finish_duration)
	# Optional: bleed off any existing rotation speed so the orbit feels consistent
	_mapRotSpeed = abs(finish_orbit_speed)
	_currRotDir = 1
	# Immediately re-center to player
	KeepRotationDistance(player)
	UpdateShader()
	_update_opponents_view_bindings()
