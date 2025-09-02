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
@export var broadcast_view_to_opponents := false  # default off

# --- Intro spin (pre-race) ---
signal intro_spin_finished

@export var intro_spin_enabled := true
@export var intro_spin_spins    : float = 1.0     # 1 = full 360°
@export var intro_spin_duration : float = 2.0     # seconds total
@export var intro_spin_zoom_k   : float = 1.25    # quick zoom during spin

var _intro_mode: bool = false
var _intro_tween: Tween
var _finish_mode: bool = false

var REARVIEW_ACTION: StringName = "RearView"

# ---- Player facing during intro spin ----
@export var player_angle_frame_offset_deg: float = 0.0  # rotate mapping if your "front" isn't frame 0
@export var player_angle_clockwise: bool = true         # set false if your sheet is CCW
@export var player_angle_frames_hint: int = 16          # used if we can’t detect from hframes

# Player angle-sheet model (half-turn ping-pong)
@export var player_frames_half_turn := true      # true = frames cover ~180° then mirror
@export var player_halfturn_frames  : int = 12   # your sheet’s columns for the half-turn

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

	if intro_spin_enabled:
		call_deferred("PlayIntroSpin", player)
		
func Update(player: Racer) -> void:
	if _rearview_on():
		if Engine.get_frames_drawn() % 15 == 0:
			print("RearView held")

	# NEW: intro mode — steady orbit driven by tween; just keep bindings fresh
	if _intro_mode:
		KeepRotationDistance(player)
		UpdateShader()
		_update_opponents_view_bindings()
		return
			
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

	# Temporarily yaw 180Â° for rendering when rear view is held.
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
	if _finalMatrix != _last_matrix:
		_last_matrix = _finalMatrix
		var scr: Vector2 = get_viewport_rect().size

		if _overlay_node != null and _overlay_node.has_method("set_world_and_screen"):
			_overlay_node.call("set_world_and_screen", _finalMatrix, scr)

		if broadcast_view_to_opponents:
			for n in _opponents:
				if n == null: continue
				if n.has_method("set_world_and_screen"):
					n.call("set_world_and_screen", _finalMatrix, scr)
					
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
	var yaw := _mapRotationAngle.y
	if _rearview_on():
		yaw = WrapAngle(yaw + PI)

	var v := Vector2(sin(yaw), cos(yaw))  # (x,z)
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

func PlayIntroSpin(player: Racer) -> void:
	if not intro_spin_enabled or player == null:
		emit_signal("intro_spin_finished")
		return

	_intro_mode = true

	# freeze any existing rotation and keep centered on player
	_mapRotSpeed = 0.0
	KeepRotationDistance(player)
	UpdateShader()
	_update_opponents_view_bindings()

	# animate yaw for N spins (TAU = 2π radians)
	var start_yaw := _mapRotationAngle.y
	var end_yaw   := start_yaw + TAU * intro_spin_spins

	# tween yaw via SetYaw so matrix/overlay get updated every step
	_intro_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_intro_tween.tween_method(
		func(v: float) -> void:
			# v is the camera yaw we’re animating to
			SetYaw(v)
			KeepRotationDistance(player)
			_set_player_facing_for_camera_yaw(player, v)
			UpdateShader()
			_update_opponents_view_bindings()
	, start_yaw, end_yaw, intro_spin_duration)

	# parallel “punch-in then out” zoom
	var size_start := size_k
	_intro_tween.parallel().tween_property(self, "size_k", intro_spin_zoom_k, intro_spin_duration * 0.45)
	_intro_tween.parallel().tween_property(self, "size_k", size_start,        intro_spin_duration * 0.55).set_delay(intro_spin_duration * 0.45)

	_intro_tween.finished.connect(func() -> void:
		_intro_mode = false
		emit_signal("intro_spin_finished")
	)

func _set_player_facing_for_camera_yaw(player: Racer, cam_yaw: float) -> void:
	if player == null:
		return

	# Prefer a custom hook on the player if available
	if player.has_method("SetFacingRadiansFromCameraYaw"):
		player.call("SetFacingRadiansFromCameraYaw", cam_yaw)
		return
	if player.has_method("SetFacingRadians"):
		var rel := _view_angle_from_camera_yaw(cam_yaw)
		player.call("SetFacingRadians", rel)
		return

	# Generic Sprite2D angle sheet
	var spr = player.ReturnSpriteGraphic()
	if spr is Sprite2D:
		var s := spr as Sprite2D

		# Base angle we want to display (0 = looking at front)
		var rel := _view_angle_from_camera_yaw(cam_yaw)

		# Apply user offset and winding
		var offset_rad := deg_to_rad(player_angle_frame_offset_deg)
		var dir := -1.0 if player_angle_clockwise else 1.0
		var theta := fposmod((rel + offset_rad) * dir, TAU)  # [0, 2π)

		if player_frames_half_turn:
			# Half-turn sheet (front->right->back), then keep spinning by
			# playing the same sheet reversed for the second 180° (back->left->front).
			var N = (s.hframes if s.hframes > 1 else max(1, player_halfturn_frames))  # e.g., 12
			var phi := fposmod(theta, TAU)  # 0..2π

			var idx_sheet := 0
			if phi < PI:
				# 0..π :  0 -> N-1
				var u := phi / PI                     # [0,1)
				idx_sheet = int(floor(u * N))
				s.flip_h = true
			else:
				# π..2π : N-1 -> 0
				var u := (phi - PI) / PI              # [0,1)
				idx_sheet = int(floor((1.0 - u) * N))

			# clamp (avoid N on exact boundary)
			if idx_sheet >= N: idx_sheet = N - 1
			if idx_sheet < 0:  idx_sheet = 0

			s.frame = idx_sheet
		else:
			# full-circle unique frames (unchanged)
			var F = (s.hframes if s.hframes > 1 else max(1, player_angle_frames_hint))
			var idx = int(round((theta / TAU) * F)) % F
			s.frame = idx

func _view_angle_from_camera_yaw(cam_yaw: float) -> float:
	# Define 0 rad = camera looking at player's FRONT.
	# If the player’s “forward” is along +Z in map space (as your code suggests),
	# then when camera yaw = 0 we’re looking at player’s front.
	# As camera yaw increases, we walk around the player, so the *viewed* angle equals cam_yaw.
	# If your asset is authored differently, adjust with player_angle_frame_offset_deg above.
	return fposmod(cam_yaw, TAU)
