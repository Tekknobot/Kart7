#Player.gd
extends Racer

# === Controls & Drift/Hop Settings ===
const HOP_DURATION := 0.18
const HOP_HEIGHT := 10.0            # seconds airborne-ish
const HOP_SPEED_BOOST := 1.08         # temporary multiplier during hop
const DRIFT_MIN_SPEED := 20.0         # require some speed to start drift
const DRIFT_STEER_MULT := 1.65        # extra steering while drifting
const DRIFT_SPEED_MULT := 0.92        # slight slowdown while holding drift
const DRIFT_BUILD_RATE := 28.0        # how quickly mini-turbo charges
const TURBO_THRESHOLD_SMALL := 35.0
const TURBO_THRESHOLD_BIG := 80.0
const TURBO_SMALL_MULT := 1.15
const TURBO_BIG_MULT := 1.28
const TURBO_TIME := 0.45              # seconds turbo lasts

var _hop_timer := 0.0
var _hop_boost_timer := 0.0
var _is_drifting := false
var _drift_dir := 0                    # -1 left, +1 right
var _drift_charge := 0.0
var _turbo_timer := 0.0
var _base_sprite_offset_y := 0.0

const FRAME_W := 32
const FRAME_H := 32
const FRAMES_PER_ROW := 12

# Where is "straight" in your strip?
const TURN_STRAIGHT_INDEX := 0
const TURN_INCREASES_TO_RIGHT := true  # <-- flipped to fix reversed animation

const BASIC_MAX := 3   # frames 0..3 for normal turns
const DRIFT_MAX := 4   # frames 0..7 for drift turns
const LEAN_LERP_SPEED := 14.0  # higher = snappier; try 10–20
const STEER_SIGN := -1.0  # set to 1.0 if your world turns the other way

var _lean_visual := 0.0     # smoothed 0..1
var _lean_left_visual := false

var _frame_anim_time := 0.0

# === Sprite drift behavior (SNES-ish) ===
const DRIFT_WOBBLE_FREQ := 6.5          # Hz-ish feel
const DRIFT_WOBBLE_AMPL := 0.20         # how much of the range to wobble
const DRIFT_BASE_BIAS := 0.68           # base depth (0..1) while drifting
const DRIFT_RELEASE_BURST_TIME := 0.12  # seconds to snap to deepest frame on release

# Optional particles (only used if your scene has them)
const DRIFT_PARTICLE_NODE := "DriftDust"   # GPUParticles2D under the kart (optional)
const SPARKS_PARTICLE_NODE := "DriftSparks" # GPUParticles2D under the kart (optional)

var _drift_wobble_phase := 0.0
var _drift_release_timer := 0.0

const POST_DRIFT_SETTLE_TIME := 0.18   # time to ease from deep drift -> straight
var _post_settle_time := 0.0

const DRIFT_STEER_DEADZONE := 0.25     # min |steer| needed to commit a drift (0..1)
const DRIFT_ARM_WINDOW := 0.20         # seconds after hop where a held R + steer can start a drift

var _drift_arm_timer := 0.0            # counts down after hop; enables drift commit

const DRIFT_MIN_TURN_BIAS := 0.55    # guaranteed turn toward drift side while drifting (0..1)
const DRIFT_STEER_INFLUENCE := 0.65  # how much live steer modulates that bias (0..1)
const DRIFT_VISUAL_STEER_GAIN := 0.22  # how much |steer| deepens the skid frame

const DRIFT_BREAK_DEADZONE := 0.12        # |steer| below this counts as "straight"
const DRIFT_BREAK_GRACE := 0.10           # seconds you can be straight before the drift breaks
const DRIFT_REVERSE_BREAK := 0.25         # opposite steer past this cancels immediately
const POST_DRIFT_SETTLE_TIME_BREAK := 0.12# shorter settle when cancelled (no boost)

var _drift_break_timer := 0.0

func _ready() -> void:
	_register_default_actions()
	_base_sprite_offset_y = ReturnSpriteGraphic().offset.y
	# Ensure region mode is on
	var spr := ReturnSpriteGraphic()
	spr.region_enabled = true

func _set_frame(idx: int) -> void:
	idx = clamp(idx, 0, FRAMES_PER_ROW - 1)
	var spr := ReturnSpriteGraphic()
	spr.region_enabled = true
	var x := idx * FRAME_W
	spr.region_rect = Rect2(x, 0, FRAME_W, FRAME_H)

# Map a 0..1 "right-lean amount" into [0..range_max], then mirror for left
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

	# Normal steering uses "is_left".
	# Drifting, release-burst, and post-settle invert the flip (SNES-style skid).
	if _is_drifting or _drift_release_timer > 0.0 or _post_settle_time > 0.0:
		ReturnSpriteGraphic().flip_h = not is_left
	else:
		ReturnSpriteGraphic().flip_h = is_left

func _choose_and_apply_frame(dt: float) -> void:
	var steer := _inputDir.x            # -1..1
	var target_left := steer > 0.0
	var target_mag = abs(steer)        # 0..1
	var max_range := BASIC_MAX

	if _is_drifting:
		# SNES feel: lock side to drift dir, not current steer
		_lean_left_visual = (_drift_dir < 0)   # left drift if -1

		# Wobble around a deep base bias, react to steer, and avoid pinning
		_drift_wobble_phase += dt * DRIFT_WOBBLE_FREQ * TAU
		var wobble := sin(_drift_wobble_phase) * DRIFT_WOBBLE_AMPL
		var steer_intensity = abs(_inputDir.x)

		var cap := 0.93  # keep headroom so wobble shows
		target_mag = clamp(DRIFT_BASE_BIAS + wobble + steer_intensity * DRIFT_VISUAL_STEER_GAIN, 0.0, cap)

		# (Optional) help cross thresholds so you *see* frame swaps near the top
		var steps := float(DRIFT_MAX)
		var frac := fmod(target_mag * steps, 1.0)
		if frac < 0.08: target_mag += 0.04
		elif frac > 0.92: target_mag -= 0.04
		target_mag = clamp(target_mag, 0.0, cap)

		max_range = DRIFT_MAX

		# Visual charge: dust always, sparks by tier
		_emit_dust(true)
		if _drift_charge >= TURBO_THRESHOLD_BIG:
			_emit_sparks(true); _set_sparks_color(Color(0.35, 0.6, 1.0))  # blue
		elif _drift_charge >= TURBO_THRESHOLD_SMALL:
			_emit_sparks(true); _set_sparks_color(Color(1.0, 0.55, 0.2))  # orange
		else:
			_emit_sparks(false)
	else:
		# No drift: normal smooth lean toward current steer
		var t = clamp(dt * LEAN_LERP_SPEED, 0.0, 1.0)
		_lean_visual = lerp(_lean_visual, target_mag, t)

		# side switch smoothing
		if target_left != _lean_left_visual and _lean_visual < 0.15:
			_lean_left_visual = target_left
		elif target_left != _lean_left_visual and target_mag > 0.35:
			_lean_left_visual = target_left

		max_range = BASIC_MAX
		target_mag = _lean_visual
		_emit_dust(false)
		_emit_sparks(false)

	# Turbo release burst: snap to deepest few frames briefly
	if _drift_release_timer > 0.0:
		_drift_release_timer -= dt
		target_mag = 1.0
		max_range = DRIFT_MAX
	elif _post_settle_time > 0.0:
		# Post-drift settle: ease down from deep lean to straight
		_post_settle_time = max(0.0, _post_settle_time - dt)
		var u := 1.0 - (_post_settle_time / POST_DRIFT_SETTLE_TIME) # 0..1 elapsed
		var eased := 1.0 - pow(1.0 - u, 3) # cubicOut
		target_mag = lerp(1.0, 0.0, eased) # 1 -> 0 over settle
		max_range = DRIFT_MAX
		# Keep the side locked to drift side while we settle
		_lean_left_visual = (_drift_dir < 0)
		# No particles during settle
		_emit_dust(false)
		_emit_sparks(false)

	_set_turn_amount_in_range(target_mag, _lean_left_visual, max_range)

func Setup(mapSize : int):
	SetMapSize(mapSize)

func Update(mapForward : Vector3):
	# Handle collision pushback first (from base cl  ass flow)
	if(_isPushedBack):
		ApplyCollisionBump()
	
	# --- INPUT (analog + digital combined) ---
	var input_vec := ReturnPlayerInput() # x=steer, y=throttle(-)/brake(+)
	
	# --- Hop & Drift state machine ---
	_handle_hop_and_drift(input_vec)
	
	# --- Movement integration & collisions (preserve original flow) ---
	var nextPos : Vector3 = _mapPosition + ReturnVelocity()
	var nextPixelPos : Vector2i = Vector2i(ceil(nextPos.x), ceil(nextPos.z))
	
	if(_collisionHandler.IsCollidingWithWall(Vector2i(ceil(nextPos.x), ceil(_mapPosition.z)))):
		nextPos.x = _mapPosition.x 
		SetCollisionBump(Vector3(-sign(ReturnVelocity().x), 0, 0))
	if(_collisionHandler.IsCollidingWithWall(Vector2i(ceil(_mapPosition.x), ceil(nextPos.z)))):
		nextPos.z = _mapPosition.z
		SetCollisionBump(Vector3(0, 0, -sign(ReturnVelocity().z)))
	
	HandleRoadType(nextPixelPos, _collisionHandler.ReturnCurrentRoadType(nextPixelPos))
	
	SetMapPosition(nextPos)
	UpdateMovementSpeed()
	UpdateVelocity(mapForward)

	# Apply visual hop offset to sprite
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
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_A):  # B(South) accel
			throttle = -1.0
		if Input.is_joy_button_pressed(dev, JOY_BUTTON_X):  # Y(West) brake
			brake = 1.0

	if brake > 0.01:
		throttle = -brake

	# <<< FIX: flip steering for world/camera convention >>>
	steer *= STEER_SIGN

	_inputDir = Vector2(steer, throttle)
	return _inputDir

func _handle_hop_and_drift(input_vec : Vector2) -> void:
	var dt := get_process_delta_time()

	var hop_pressed := Input.is_action_just_pressed("Hop")
	# On SNES R is both hop (on press) and drift (when held). In your input map, Hop and Drift share the same button.
	var drift_down := Input.is_action_pressed("Drift")
	var moving_fast := _movementSpeed >= DRIFT_MIN_SPEED
	var steer_abs = abs(input_vec.x)

	# --- Hop (always occurs on press) ---
	if hop_pressed and not _is_drifting:
		# Visual hop + tiny boost
		_hop_timer = HOP_DURATION
		_hop_boost_timer = HOP_DURATION
		_speedMultiplier = max(_speedMultiplier, HOP_SPEED_BOOST)

		# Arm a short window where holding R + steering can commit a drift (SNES-like)
		_drift_arm_timer = DRIFT_ARM_WINDOW

	# Decay hop boost
	if _hop_boost_timer > 0.0:
		_hop_boost_timer -= dt
		if _hop_boost_timer <= 0.0:
			_speedMultiplier = 1.0

	# Decay drift arm window
	if _drift_arm_timer > 0.0:
		_drift_arm_timer = max(0.0, _drift_arm_timer - dt)

	# --- While drifting and R is held: build charge, slight slowdown, stronger steer ---
	if _is_drifting and drift_down:
		_speedMultiplier = DRIFT_SPEED_MULT

		# SNES-ish: always bias into the drift side, then let live steer modulate it.
		var bias := _drift_dir * DRIFT_MIN_TURN_BIAS
		var steer_mod := input_vec.x * DRIFT_STEER_INFLUENCE
		var drifted_steer = clamp(bias + steer_mod, -1.0, 1.0)

		# Optional extra yaw strength while drifting
		_inputDir.x = clamp(drifted_steer * DRIFT_STEER_MULT, -1.0, 1.0)

		# Charge grows with *actual* steer effort
		_drift_charge += abs(input_vec.x) * DRIFT_BUILD_RATE * dt

		# ---- NEW: break conditions ----
		var steer_sign = sign(input_vec.x)

		# 1) Immediate cancel if steering opposite past threshold
		if steer_sign != 0 and steer_sign == -_drift_dir and abs(input_vec.x) >= DRIFT_REVERSE_BREAK:
			_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		# 2) Graceful cancel if centered for a bit
		elif abs(input_vec.x) < DRIFT_BREAK_DEADZONE:
			_drift_break_timer += dt
			if _drift_break_timer >= DRIFT_BREAK_GRACE:
				_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		else:
			# reset grace when actively steering
			_drift_break_timer = 0.0

	# --- Release (stop drifting) when R is released -> award boost if eligible ---
	if _is_drifting and not drift_down:
		_end_drift_with_award()

	# --- No drift active (either never started or has finished) ---
	# If the arm window expired or conditions failed, it was just a hop.
	# Nothing special to do here.

	# Turbo decay (unchanged)
	if _turbo_timer > 0.0:
		_turbo_timer -= dt
		if _turbo_timer <= 0.0:
			_speedMultiplier = 1.0

func _register_default_actions() -> void:
	if not InputMap.has_action("Forward"): InputMap.add_action("Forward")
	if not InputMap.has_action("Left"):    InputMap.add_action("Left")
	if not InputMap.has_action("Right"):   InputMap.add_action("Right")
	if not InputMap.has_action("Brake"):   InputMap.add_action("Brake")
	if not InputMap.has_action("Hop"):     InputMap.add_action("Hop")
	if not InputMap.has_action("Drift"):   InputMap.add_action("Drift")

	# SNES gamepad only
	var jb := InputEventJoypadButton.new()

	# Forward: B (South) -> JOY_BUTTON_A
	jb.button_index = JOY_BUTTON_A;              InputMap.action_add_event("Forward", jb.duplicate())
	# Brake: Y (West) -> JOY_BUTTON_X
	jb.button_index = JOY_BUTTON_X;              InputMap.action_add_event("Brake", jb.duplicate())
	# Hop: R shoulder (same as MK hop)
	jb.button_index = JOY_BUTTON_RIGHT_SHOULDER; InputMap.action_add_event("Hop", jb.duplicate())
	# Drift: R shoulder (hold)
	jb.button_index = JOY_BUTTON_RIGHT_SHOULDER; InputMap.action_add_event("Drift", jb.duplicate())
	# Steering: D-Pad
	jb.button_index = JOY_BUTTON_DPAD_LEFT;      InputMap.action_add_event("Left", jb.duplicate())
	jb.button_index = JOY_BUTTON_DPAD_RIGHT;     InputMap.action_add_event("Right", jb.duplicate())

func _apply_hop_sprite_offset() -> void:
	# Visual hop arc using sprite offset so we don't fight AnimationHandler's .position.y
	var dt := get_process_delta_time()
	if _hop_timer > 0.0:
		_hop_timer -= dt
		var t = clamp(1.0 - (_hop_timer / HOP_DURATION), 0.0, 1.0)
		# Simple arc: sin(pi * t) for up-and-down
		var y := sin(PI * t) * HOP_HEIGHT
		ReturnSpriteGraphic().offset.y = _base_sprite_offset_y - y
	else:
		ReturnSpriteGraphic().offset.y = _base_sprite_offset_y

func _try_get_node(path: String) -> Node:
	if has_node(path): return get_node(path)
	return null

func _set_sparks_color(col: Color) -> void:
	var p := _try_get_node(SPARKS_PARTICLE_NODE)
	if p and p is GPUParticles2D:
		p.process_material.color = col

func _emit_sparks(on: bool) -> void:
	var p := _try_get_node(SPARKS_PARTICLE_NODE)
	if p and p is GPUParticles2D:
		p.emitting = on

func _emit_dust(on: bool) -> void:
	var p := _try_get_node(DRIFT_PARTICLE_NODE)
	if p and p is GPUParticles2D:
		p.emitting = on

func _cancel_drift_no_award(settle_time: float) -> void:
	_is_drifting = false
	_speedMultiplier = 1.0
	_emit_dust(false)
	_emit_sparks(false)
	_drift_release_timer = 0.0      # no burst frame
	_post_settle_time = settle_time # still glide back visually
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
