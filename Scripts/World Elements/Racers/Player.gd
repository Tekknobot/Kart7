# Player.gd
extends "res://Scripts/World Elements/Racers/Racer.gd"

# === Controls & Drift/Hop Settings ===
const HOP_DURATION := 0.18
const HOP_HEIGHT := 10.0
const HOP_SPEED_BOOST := 1.08

const DRIFT_MIN_SPEED := 20.0
const DRIFT_STEER_MULT := 1.65
const DRIFT_SPEED_MULT := 0.92
const DRIFT_BUILD_RATE := 28.0
const TURBO_THRESHOLD_SMALL := 35.0
const TURBO_THRESHOLD_BIG := 80.0
const TURBO_SMALL_MULT := 1.15
const TURBO_BIG_MULT := 1.28
const TURBO_TIME := 0.45

var _hop_timer := 0.0
var _hop_boost_timer := 0.0
var _is_drifting := false
var _drift_dir := 0
var _drift_charge := 0.0
var _turbo_timer := 0.0
var _base_sprite_offset_y := 0.0

const FRAME_W := 32
const FRAME_H := 32
const FRAMES_PER_ROW := 12

const TURN_STRAIGHT_INDEX := 0
const TURN_INCREASES_TO_RIGHT := true

const BASIC_MAX := 3
const DRIFT_MAX := 4
const LEAN_LERP_SPEED := 14.0
const STEER_SIGN := -1.0

var _lean_visual := 0.0
var _lean_left_visual := false
var _frame_anim_time := 0.0

# === Sprite drift behavior (SNES-ish) ===
const DRIFT_WOBBLE_FREQ := 6.5
const DRIFT_WOBBLE_AMPL := 0.20
const DRIFT_BASE_BIAS := 0.68
const DRIFT_RELEASE_BURST_TIME := 0.12

const DRIFT_PARTICLE_NODE := "DriftDust"
const SPARKS_PARTICLE_NODE := "DriftSparks"

var _drift_wobble_phase := 0.0
var _drift_release_timer := 0.0

const POST_DRIFT_SETTLE_TIME := 0.18
var _post_settle_time := 0.0

const DRIFT_STEER_DEADZONE := 0.25
const DRIFT_ARM_WINDOW := 0.20
var _drift_arm_timer := 0.0

const DRIFT_MIN_TURN_BIAS := 0.55
const DRIFT_STEER_INFLUENCE := 0.65
const DRIFT_VISUAL_STEER_GAIN := 0.22

const DRIFT_BREAK_DEADZONE := 0.12
const DRIFT_BREAK_GRACE := 0.10
const DRIFT_REVERSE_BREAK := 0.25
const POST_DRIFT_SETTLE_TIME_BREAK := 0.12

var _drift_break_timer := 0.0
const TAU := PI * 2.0

# --- SNES-ish feel controls ---
const DRIFT_GRIP := 0.55
const DRIFT_COUNTERSTEER_GAIN := 1.6
const DRIFT_SLIP_GAIN := 0.9
const DRIFT_SLIP_DAMP := 6.0
var _drift_side_slip := 0.0

func _ready() -> void:
	_register_default_actions()
	_base_sprite_offset_y = ReturnSpriteGraphic().offset.y
	var spr := ReturnSpriteGraphic()
	spr.region_enabled = true

func _process(_dt: float) -> void:
	# publish camera/player position for pseudo-3D projection
	Globals.set_camera_map_position(get_player_map_position())

func _set_frame(idx: int) -> void:
	idx = clamp(idx, 0, FRAMES_PER_ROW - 1)
	var spr := ReturnSpriteGraphic()
	spr.region_enabled = true
	var x := idx * FRAME_W
	spr.region_rect = Rect2(x, 0, FRAME_W, FRAME_H)

func _set_turn_amount_in_range(right_amount: float, is_left: bool, range_max: int) -> void:
	right_amount = clamp(right_amount, 0.0, 1.0)
	range_max = clamp(range_max, 0, FRAMES_PER_ROW - 1)

	var steps := float(range_max)
	var delta := int(floor(right_amount * steps + 0.0001))

	var idx: int
	if TURN_INCREASES_TO_RIGHT:
		idx = TURN_STRAIGHT_INDEX + delta
	else:
		idx = TURN_STRAIGHT_INDEX - delta

	_set_frame(idx)

	if _is_drifting or _drift_release_timer > 0.0 or _post_settle_time > 0.0:
		ReturnSpriteGraphic().flip_h = not is_left
	else:
		ReturnSpriteGraphic().flip_h = is_left

func _choose_and_apply_frame(dt: float) -> void:
	var steer := _inputDir.x
	var target_left := steer > 0.0
	var target_mag = abs(steer)
	var max_range := BASIC_MAX

	if _is_drifting:
		_lean_left_visual = (_drift_dir < 0)
		_drift_wobble_phase += dt * DRIFT_WOBBLE_FREQ * TAU
		var wobble := sin(_drift_wobble_phase) * DRIFT_WOBBLE_AMPL
		var steer_intensity = abs(_inputDir.x)

		var cap := 0.93
		target_mag = clamp(DRIFT_BASE_BIAS + wobble + steer_intensity * DRIFT_VISUAL_STEER_GAIN, 0.0, cap)

		var steps := float(DRIFT_MAX)
		var frac := fmod(target_mag * steps, 1.0)
		if frac < 0.08:
			target_mag += 0.04
		elif frac > 0.92:
			target_mag -= 0.04
		target_mag = clamp(target_mag, 0.0, cap)

		max_range = DRIFT_MAX

		_emit_dust(true)
		if _drift_charge >= TURBO_THRESHOLD_BIG:
			_emit_sparks(true)
			_set_sparks_color(Color(0.35, 0.6, 1.0))
		elif _drift_charge >= TURBO_THRESHOLD_SMALL:
			_emit_sparks(true)
			_set_sparks_color(Color(1.0, 0.55, 0.2))
		else:
			_emit_sparks(false)
	else:
		var t = clamp(dt * LEAN_LERP_SPEED, 0.0, 1.0)
		_lean_visual = lerp(_lean_visual, target_mag, t)

		if target_left != _lean_left_visual and _lean_visual < 0.15:
			_lean_left_visual = target_left
		elif target_left != _lean_left_visual and target_mag > 0.35:
			_lean_left_visual = target_left

		max_range = BASIC_MAX
		target_mag = _lean_visual
		_emit_dust(false)
		_emit_sparks(false)

	if _drift_release_timer > 0.0:
		_drift_release_timer -= dt
		target_mag = 1.0
		max_range = DRIFT_MAX
	elif _post_settle_time > 0.0:
		_post_settle_time = max(0.0, _post_settle_time - dt)
		var u := 1.0 - (_post_settle_time / POST_DRIFT_SETTLE_TIME)
		var eased := 1.0 - pow(1.0 - u, 3)
		target_mag = lerp(1.0, 0.0, eased)
		max_range = DRIFT_MAX
		_lean_left_visual = (_drift_dir < 0)
		_emit_dust(false)
		_emit_sparks(false)

	_set_turn_amount_in_range(target_mag, _lean_left_visual, max_range)

func Setup(mapSize : int) -> void:
	SetMapSize(mapSize)

func Update(mapForward : Vector3) -> void:
	if _isPushedBack:
		ApplyCollisionBump()

	var input_vec := ReturnPlayerInput()
	_handle_hop_and_drift(input_vec)

	var nextPos : Vector3 = _mapPosition + ReturnVelocity()
	var nextPixelPos : Vector2i = Vector2i(ceil(nextPos.x), ceil(nextPos.z))

	var right_vec := Vector3(-mapForward.z, 0.0, mapForward.x).normalized()
	var dt := get_process_delta_time()
	if _is_drifting:
		var speed := ReturnVelocity().length()
		var steer_amt = abs(_inputDir.x)
		var feed = DRIFT_SLIP_GAIN * speed * steer_amt
		var outward_sign := 1.0
		if _drift_dir >= 0:
			outward_sign = -1.0
		_drift_side_slip = lerp(_drift_side_slip, outward_sign * feed, clamp(dt * 4.0, 0.0, 1.0))
	else:
		_drift_side_slip = lerp(_drift_side_slip, 0.0, clamp(dt * DRIFT_SLIP_DAMP, 0.0, 1.0))

	nextPos += right_vec * _drift_side_slip * dt

	if _collisionHandler.IsCollidingWithWall(Vector2i(ceil(nextPos.x), ceil(_mapPosition.z))):
		nextPos.x = _mapPosition.x 
		SetCollisionBump(Vector3(-sign(ReturnVelocity().x), 0.0, 0.0))
	if _collisionHandler.IsCollidingWithWall(Vector2i(ceil(_mapPosition.x), ceil(nextPos.z))):
		nextPos.z = _mapPosition.z
		SetCollisionBump(Vector3(0.0, 0.0, -sign(ReturnVelocity().z)))
	
	HandleRoadType(nextPixelPos, _collisionHandler.ReturnCurrentRoadType(nextPixelPos))
	
	SetMapPosition(nextPos)
	UpdateMovementSpeed()
	UpdateVelocity(mapForward)

	_apply_hop_sprite_offset()
	_choose_and_apply_frame(get_process_delta_time())

func ReturnPlayerInput() -> Vector2:
	var steer := 0.0
	var throttle := 0.0
	var brake := 0.0

	var pads := Input.get_connected_joypads()
	if pads.size() > 0:
		var dev := pads[0]
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_LEFT):
			steer = -1.0
		elif Input.is_joy_button_pressed(dev, JOY_BUTTON_DPAD_RIGHT):
			steer = 1.0
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_A):
			throttle = -1.0
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_X):
			brake = 1.0

	if brake > 0.01:
		throttle = -brake

	steer *= STEER_SIGN
	_inputDir = Vector2(steer, throttle)
	return _inputDir

func _handle_hop_and_drift(input_vec : Vector2) -> void:
	var dt := get_process_delta_time()

	var hop_pressed := Input.is_action_just_pressed("Hop")
	var drift_down := Input.is_action_pressed("Drift")
	var moving_fast := _movementSpeed >= DRIFT_MIN_SPEED
	var steer_abs = abs(input_vec.x)

	if hop_pressed and not _is_drifting:
		_hop_timer = HOP_DURATION
		_hop_boost_timer = HOP_DURATION
		_speedMultiplier = max(_speedMultiplier, HOP_SPEED_BOOST)
		_drift_arm_timer = DRIFT_ARM_WINDOW

	if _hop_boost_timer > 0.0:
		_hop_boost_timer -= dt
		if _hop_boost_timer <= 0.0:
			_speedMultiplier = 1.0

	if _drift_arm_timer > 0.0:
		_drift_arm_timer = max(0.0, _drift_arm_timer - dt)

	if (not _is_drifting) and drift_down and (_drift_arm_timer > 0.0) and moving_fast and (steer_abs >= DRIFT_STEER_DEADZONE):
		_is_drifting = true
		if input_vec.x < 0.0:
			_drift_dir = -1
		else:
			_drift_dir = 1
		_drift_wobble_phase = 0.0
		_drift_break_timer = 0.0
		_drift_charge = 0.0
		_lean_left_visual = (_drift_dir < 0)
		_post_settle_time = 0.0

	if _is_drifting and drift_down:
		_speedMultiplier = DRIFT_SPEED_MULT

		var bias := float(_drift_dir) * DRIFT_MIN_TURN_BIAS
		var steer_mod := input_vec.x * DRIFT_STEER_INFLUENCE
		var raw_target = clamp(bias + steer_mod, -1.0, 1.0)

		if sign(input_vec.x) == -_drift_dir:
			raw_target *= DRIFT_COUNTERSTEER_GAIN
		raw_target = clamp(raw_target, -1.0, 1.0)

		var grip_t = clamp(get_process_delta_time() * (DRIFT_GRIP * 10.0), 0.0, 1.0)
		_inputDir.x = lerp(_inputDir.x, raw_target * DRIFT_STEER_MULT, grip_t)

		_drift_charge += abs(input_vec.x) * DRIFT_BUILD_RATE * get_process_delta_time()

		var steer_sign = sign(input_vec.x)
		if steer_sign != 0 and steer_sign == -_drift_dir and abs(input_vec.x) >= DRIFT_REVERSE_BREAK:
			_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		elif abs(input_vec.x) < DRIFT_BREAK_DEADZONE:
			_drift_break_timer += get_process_delta_time()
			if _drift_break_timer >= DRIFT_BREAK_GRACE:
				_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		else:
			_drift_break_timer = 0.0

	if _is_drifting and not drift_down:
		_end_drift_with_award()

	if _turbo_timer > 0.0:
		_turbo_timer -= dt
		if _turbo_timer <= 0.0:
			_speedMultiplier = 1.0

func _register_default_actions() -> void:
	if not InputMap.has_action("Forward"):
		InputMap.add_action("Forward")
	if not InputMap.has_action("Left"):
		InputMap.add_action("Left")
	if not InputMap.has_action("Right"):
		InputMap.add_action("Right")
	if not InputMap.has_action("Brake"):
		InputMap.add_action("Brake")
	if not InputMap.has_action("Hop"):
		InputMap.add_action("Hop")
	if not InputMap.has_action("Drift"):
		InputMap.add_action("Drift")

	var jb := InputEventJoypadButton.new()
	jb.button_index = JOY_BUTTON_A
	InputMap.action_add_event("Forward", jb.duplicate())
	jb.button_index = JOY_BUTTON_X
	InputMap.action_add_event("Brake", jb.duplicate())
	jb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("Hop", jb.duplicate())
	jb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("Drift", jb.duplicate())
	jb.button_index = JOY_BUTTON_DPAD_LEFT
	InputMap.action_add_event("Left", jb.duplicate())
	jb.button_index = JOY_BUTTON_DPAD_RIGHT
	InputMap.action_add_event("Right", jb.duplicate())

func _apply_hop_sprite_offset() -> void:
	var dt := get_process_delta_time()
	if _hop_timer > 0.0:
		_hop_timer -= dt
		var t = clamp(1.0 - (_hop_timer / HOP_DURATION), 0.0, 1.0)
		var y := sin(PI * t) * HOP_HEIGHT
		ReturnSpriteGraphic().offset.y = _base_sprite_offset_y - y
	else:
		ReturnSpriteGraphic().offset.y = _base_sprite_offset_y

func _try_get_node(path: String) -> Node:
	if has_node(path):
		return get_node(path)
	return null

func _set_sparks_color(col: Color) -> void:
	var p := _try_get_node(SPARKS_PARTICLE_NODE)
	if p != null and p is GPUParticles2D:
		p.process_material.color = col

func _emit_sparks(on: bool) -> void:
	var p := _try_get_node(SPARKS_PARTICLE_NODE)
	if p != null and p is GPUParticles2D:
		p.emitting = on

func _emit_dust(on: bool) -> void:
	var p := _try_get_node(DRIFT_PARTICLE_NODE)
	if p == null:
		return

	if p is GPUParticles2D:
		p.emitting = on
		return

	if p is AnimatedSprite2D:
		p.visible = on
		if on:
			if p.sprite_frames == null or p.sprite_frames.get_animation_names().is_empty():
				return
			var anim = p.animation
			if anim == "" or not p.is_playing():
				anim = p.sprite_frames.get_animation_names()[0]
			p.animation = anim
			if not p.is_playing():
				p.play()
		else:
			if p.is_playing():
				p.stop()
		return

	if p is Sprite2D:
		p.visible = on

func _cancel_drift_no_award(settle_time: float) -> void:
	_is_drifting = false
	_speedMultiplier = 1.0
	_emit_dust(false)
	_emit_sparks(false)
	_drift_release_timer = 0.0
	_post_settle_time = settle_time
	_lean_left_visual = (_drift_dir < 0)
	_drift_charge = 0.0

func _end_drift_with_award() -> void:
	_is_drifting = false
	_speedMultiplier = 1.0
	_emit_dust(false)
	_emit_sparks(false)

	if _drift_charge >= TURBO_THRESHOLD_BIG:
		_turbo_timer = TURBO_TIME
		_speedMultiplier = TURBO_BIG_MULT
		_drift_release_timer = DRIFT_RELEASE_BURST_TIME
	elif _drift_charge >= TURBO_THRESHOLD_SMALL:
		_turbo_timer = TURBO_TIME
		_speedMultiplier = TURBO_SMALL_MULT
		_drift_release_timer = DRIFT_RELEASE_BURST_TIME * 0.75
	else:
		_drift_release_timer = 0.0

	_post_settle_time = POST_DRIFT_SETTLE_TIME
	_lean_left_visual = (_drift_dir < 0)
	_drift_charge = 0.0

func ReturnIsHopping() -> bool:
	return _hop_timer > 0.0

func ReturnIsDrifting() -> bool:
	return _is_drifting

# Return the player's map-space position (same space used for path/Pseudo3D)
func get_player_map_position() -> Vector2:
	return get_map_space_position()

# Return the camera forward vector in map space
func get_player_camera_forward(pseudo3d: Node) -> Vector2:
	return pseudo3d.get_camera_forward_map()
