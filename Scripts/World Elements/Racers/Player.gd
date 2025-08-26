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
const DRIFT_WOBBLE_FREQ := 8
const DRIFT_WOBBLE_AMPL := 0.40
const DRIFT_BASE_BIAS := 0.7
const DRIFT_RELEASE_BURST_TIME := 0.24

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

# === Drift Spin-out ===
const SPIN_MIN_STEER := 0.55          # must steer at least this hard while drifting
const SPIN_BUILD_BASE := 10.0         # base fill per second while drifting
const SPIN_BUILD_STEER_GAIN := 26.0   # extra fill scaled by |steer|
const SPIN_THRESHOLD := 100.0         # trip point
const SPIN_DURATION := 0.80           # total time of the spin state
const SPIN_SPEED_MULT := 0.60         # slow-down while spinning
const SPIN_ANIM_CYCLES := 2.0         # how many “L→R” swaps during SPIN_DURATION
const SPIN_RECOVER_STEER_LOCK := 0.12 # brief steer lock after recovery

var _spin_meter := 0.0
var _is_spinning := false
var _spin_timer := 0.0
var _spin_phase := 0.0
var _post_spin_lock := 0.0

# === Item (Mushroom) Boost ===
const ITEM_BOOST_MULT := 6.75     # how strong the mushroom boost is
const ITEM_BOOST_TIME := 0.35     # how long it lasts (seconds)
const ITEM_COOLDOWN := 3       # small cooldown before you can use another

var _item_boost_timer := 0.0
var _item_cooldown_timer := 0.0

var _has_base_sprite_offset: bool = false

# --- Item boost terrain compensation (tune to taste) ---
@export var ITEM_COMP_OFF_ROAD := 1.40   # extra “anti-slow” while boosting on OFF_ROAD
@export var ITEM_COMP_GRAVEL  := 1.20   # extra “anti-slow” while boosting on GRAVEL

# --- Wall collision tuning ---
@export var WALL_RESTITUTION      := 0.35   # 0 = no bounce, 1 = perfectly bouncy
@export var WALL_SLIDE_KEEP       := 0.85   # keep this fraction of tangential speed
@export var WALL_SEPARATION_EPS   := 0.50   # small nudge away from wall (pixels)
@export var WALL_BUMP_STRENGTH    := 1.0    # impulse fed into SetCollisionBump()
@export var WALL_HIT_COOLDOWN_S   := 0.10   # min time between bumps

var _wall_hit_cd := 0.0
var _primed_sprite := false

@export var ITEM_TEMP_CAP_FACTOR  := 1.60  # temporary headroom while item is active
@export var TURBO_TEMP_CAP_FACTOR := 1.45  # temporary headroom while turbo is active
@export var HOP_TEMP_CAP_FACTOR   := 1.10  # tiny headroom while hop is active

func _compute_temp_cap(base_cap: float) -> float:
	var cap := base_cap

	# raise cap only for the duration of the boost; we don't touch the saved base cap
	if _item_boost_timer > 0.0:
		var c := base_cap * ITEM_TEMP_CAP_FACTOR
		if cap < c:
			cap = c
	if _turbo_timer > 0.0:
		var c := base_cap * TURBO_TEMP_CAP_FACTOR
		if cap < c:
			cap = c
	if _hop_timer > 0.0:
		var c := base_cap * HOP_TEMP_CAP_FACTOR
		if cap < c:
			cap = c

	# spin should never be fast — temporarily *lower* cap if spinning
	if _is_spinning:
		var c := base_cap * SPIN_SPEED_MULT
		if cap > c:
			cap = c

	return cap

func _prime_sprite_grid_once() -> void:
	if _primed_sprite:
		return
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return

	# Sprite2D (grid sheet)
	if spr is Sprite2D:
		var s := spr as Sprite2D
		# force grid mode; showing the whole texture for a frame is the usual culprit
		s.region_enabled = false
		if s.hframes != DIRECTIONS:
			s.hframes = DIRECTIONS
			s.vframes = 1
		s.flip_h = false
		s.frame = TURN_STRAIGHT_INDEX  # single frame (front)
		_primed_sprite = true
		return

	# AnimatedSprite2D (fallback)
	if spr.has_method("stop"):
		spr.stop()
	if "frame" in spr:
		spr.frame = TURN_STRAIGHT_INDEX
	_primed_sprite = true
	
func _apply_item_terrain_comp(rt: int) -> void:
	if _item_boost_timer <= 0.0:
		return
	# Don’t compensate for SINK/WALL; they’re “hard stops”.
	if rt == Globals.RoadType.OFF_ROAD:
		_speedMultiplier = max(_speedMultiplier, ITEM_BOOST_MULT * ITEM_COMP_OFF_ROAD)
	elif rt == Globals.RoadType.GRAVEL:
		_speedMultiplier = max(_speedMultiplier, ITEM_BOOST_MULT * ITEM_COMP_GRAVEL)

func _spr_or_null() -> CanvasItem:
	return ReturnSpriteGraphic()

func _set_frame_idx(dir_idx: int) -> void:
	var spr := _spr_or_null()
	if spr == null: return

	if spr is Sprite2D:
		var s := spr as Sprite2D
		if sheet_uses_mirroring:
			# 6 columns on sheet; use flip for the other 6
			var HALF := 12
			var idx := (dir_idx % (HALF * 2) + (HALF * 2)) % (HALF * 2)
			var left_side := idx >= HALF
			var col := idx % HALF
			if s.hframes != HALF:
				s.hframes = HALF
				s.vframes = 1
			s.frame = col
			s.flip_h = left_side
		else:
			# full 12 unique frames — no flip needed
			if s.hframes != DIRECTIONS:
				s.hframes = DIRECTIONS
				s.vframes = 1
			s.flip_h = false
			s.frame = clamp(dir_idx, 0, DIRECTIONS - 1)
	elif "frame" in spr:
		spr.frame = clamp(dir_idx, 0, DIRECTIONS - 1)

func _ready() -> void:
	_register_default_actions()
	var spr := ReturnSpriteGraphic()
	if spr == null:
		await get_tree().process_frame
		spr = ReturnSpriteGraphic()
	if spr == null:
		push_error("Player.gd: sprite_graphic_path is not set or node missing: %s" % str(get("sprite_graphic_path")))
		return

	_prime_sprite_grid_once()   # <- ensure single frame, grid mode, no region
	_base_sprite_offset_y = spr.offset.y

func _process(_dt: float) -> void:
	# publish camera/player position for pseudo-3D projection
	Globals.set_camera_map_position(get_player_map_position())
	if Engine.get_process_frames() % 30 == 0:
		var v := ReturnPlayerInput()
		#print("INPUT steer=", v.x, " throttle=", v.y)

func _set_frame(idx: int) -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return   # sprite not ready this frame

	# Sprite2D sheet (preferred)
	if spr is Sprite2D:
		var s := spr as Sprite2D
		# ensure grid; safe to repeat
		if s.hframes != DIRECTIONS:
			s.hframes = DIRECTIONS
			s.vframes = 1
		# DO NOT touch s.region_enabled here; not needed for hframes/vframes
		s.frame = clamp(idx, 0, DIRECTIONS - 1)
		return

	# AnimatedSprite2D fallback
	if spr.has_method("set_frame"):
		spr.frame = clamp(idx, 0, DIRECTIONS - 1)

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

	# SAFELY set flip (no direct ReturnSpriteGraphic().flip_h)
	if _is_drifting or _drift_release_timer > 0.0 or _post_settle_time > 0.0:
		_set_flip_h(not is_left)
	else:
		_set_flip_h(is_left)

# --- helper: null-safe flip ---
func _set_flip_h(val: bool) -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return
	if spr is Sprite2D:
		(spr as Sprite2D).flip_h = val
	elif "flip_h" in spr:
		spr.flip_h = val

func _choose_and_apply_frame(dt: float) -> void:
	var steer := _inputDir.x
	var target_left := steer > 0.0
	var target_mag = abs(steer)
	var max_range := BASIC_MAX

	# SPIN VISUAL: play left turn frames, then a flipped version, repeatedly.
	if _is_spinning:
		# phase in [0,1); first half = sweep A, second half = sweep B
		var ph := fposmod(_spin_phase, 1.0)
		var first_half := ph < 0.5
		var t := 0.0
		if first_half:
			t = ph * 2.0
		else:
			t = (ph - 0.5) * 2.0  # 0..1 within each half

		var frames := FRAMES_PER_ROW
		var steps := frames - 1
		var step := int(floor(t * steps + 0.0001))  # 0..steps

		# Decide direction: right-first = forward (0..11), left-first = backward (11..0)
		var dir_right_first := (_drift_dir >= 0)

		var seq_a := 0         # first-half sweep
		var seq_b := 0         # second-half sweep (reverse of A)

		if dir_right_first:
			# RIGHT-FIRST: 0..11 then 11..0
			seq_a = step
			seq_b = steps - step
		else:
			# LEFT-FIRST: 11..0 then 0..11
			seq_a = steps - step
			seq_b = step

		var seq := 0
		if first_half:
			seq = seq_a
		else:
			seq = seq_b

		# Map to actual sheet direction (if your sheet increases to the right or left)
		var inc_right := TURN_INCREASES_TO_RIGHT
		var idx := seq
		if not inc_right:
			idx = steps - seq

		# Safety
		idx = clamp(idx, 0, steps)

		# Use mirroring-aware setter so 6+flip sheets animate correctly
		_set_frame(idx)
		return

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

	var dt := get_process_delta_time()

	if _post_spin_lock > 0.0:
		_post_spin_lock = max(0.0, _post_spin_lock - dt)

	var input_vec := ReturnPlayerInput()

	# build spin meter only while drifting
	_spinout_update_meter(dt, input_vec)
	_spinout_tick(dt)

	# --- Item boost trigger ---
	if _item_cooldown_timer > 0.0:
		_item_cooldown_timer = max(0.0, _item_cooldown_timer - dt)

	if Input.is_action_just_pressed("Item"):
		# Optional: block during spin so you can't cheese out of it.
		if not _is_spinning and _item_cooldown_timer <= 0.0:
			_item_boost_timer = ITEM_BOOST_TIME
			_item_cooldown_timer = ITEM_BOOST_TIME + ITEM_COOLDOWN
			# (Optional FX)
			_emit_sparks(true)
			_set_sparks_color(Color(0.6, 1.0, 0.4)) # greenish boost flash

	# if spinning, block the hop/drift system entirely
	if not _is_spinning:
		_handle_hop_and_drift(input_vec)

	# --- Timers decay (do NOT write _speedMultiplier here) ---
	if _item_boost_timer > 0.0:
		_item_boost_timer = max(0.0, _item_boost_timer - dt)

	# ✅ TURBO DECAY (the missing bit that caused speed creep)
	if _turbo_timer > 0.0:
		_turbo_timer = max(0.0, _turbo_timer - dt)

	# unify ALL stacking here (hop/item/turbo/drift/spin)
	_recompute_speed_multiplier()

	var nextPos : Vector3 = _mapPosition + ReturnVelocity()
	var nextPixelPos : Vector2i = Vector2i(ceil(nextPos.x), ceil(nextPos.z))

	var right_vec := Vector3(-mapForward.z, 0.0, mapForward.x).normalized()

	# keep your drift side-slip, but never add extra while spinning
	if _is_drifting and not _is_spinning:
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

	# (collision & movement unchanged)
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
	_wall_hit_cd = max(0.0, _wall_hit_cd - dt)

func ReturnPlayerInput() -> Vector2:
	var steer := Input.get_action_strength("Right") - Input.get_action_strength("Left")
	var forward := Input.get_action_strength("Forward")
	var brake := Input.get_action_strength("Brake")

	# brief steer lock after a spin
	if _post_spin_lock > 0.0:
		steer = 0.0

	var throttle := -forward
	if brake > 0.01:
		throttle = -brake

	steer *= STEER_SIGN

	# while spinning, ignore steer/throttle so the kart coasts under damped speed
	if _is_spinning:
		_inputDir = Vector2(0.0, 0.0)
		return _inputDir

	_inputDir = Vector2(steer, throttle)
	return _inputDir

func _handle_hop_and_drift(input_vec : Vector2) -> void:
	var dt := get_process_delta_time()

	# --- Inputs / gates ---
	var hop_pressed := Input.is_action_just_pressed("Hop")
	var drift_down := Input.is_action_pressed("Drift")
	var moving_fast := _movementSpeed >= DRIFT_MIN_SPEED
	var steer_abs = abs(input_vec.x)
	var steer_sign = sign(input_vec.x)

	# --- Hop: arm a short window where drift can begin (SNES-style) ---
	if hop_pressed and not _is_drifting:
		_hop_timer = HOP_DURATION
		_hop_boost_timer = HOP_DURATION
		# NOTE: no speed boost from hop anymore
		_drift_arm_timer = DRIFT_ARM_WINDOW

	# decay hop window/timer (no speed resets)
	if _hop_boost_timer > 0.0:
		_hop_boost_timer = max(0.0, _hop_boost_timer - dt)

	# keep arm window alive briefly after hop
	if _drift_arm_timer > 0.0:
		_drift_arm_timer = max(0.0, _drift_arm_timer - dt)

	# --- Start DRIFT: only if armed by hop, fast enough, and steering clearly ---
	if (not _is_drifting) and drift_down and (_drift_arm_timer > 0.0) and moving_fast and (steer_abs >= DRIFT_STEER_DEADZONE):
		var dir := 1
		if steer_sign < 0.0:
			dir = -1
		_start_drift_snes(dir)

	# --- While DRIFTING (SNES-style fixed slip) ---
	if _is_drifting and drift_down:
		# Keep speed almost intact while drifting (classic SMK keeps momentum)
		#_speedMultiplier = DRIFT_SPEED_MULT

		var bias := float(_drift_dir) * DRIFT_MIN_TURN_BIAS
		var raw_target = clamp(bias, -1.0, 1.0)

		var grip_t = clamp(dt * (DRIFT_GRIP * 10.0), 0.0, 1.0)
		_inputDir.x = lerp(_inputDir.x, raw_target * DRIFT_STEER_MULT, grip_t)

		_drift_charge += (0.75 + 0.25 * steer_abs) * DRIFT_BUILD_RATE * dt

		if steer_sign != 0 and steer_sign == -_drift_dir and steer_abs >= DRIFT_REVERSE_BREAK:
			_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		elif steer_abs < DRIFT_BREAK_DEADZONE:
			_drift_break_timer += dt
			if _drift_break_timer >= DRIFT_BREAK_GRACE:
				_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		else:
			_drift_break_timer = 0.0

	# --- Release drift button: award mini-boost / turbo ---
	if _is_drifting and not drift_down:
		_end_drift_with_award()

# SNES-like drift start: lock direction, fixed slip "set", reset counters.
func _start_drift_snes(dir: int) -> void:
	_is_drifting = true

	if dir < 0:
		_drift_dir = -1
	else:
		_drift_dir = 1

	_drift_wobble_phase = 0.0
	_drift_break_timer = 0.0
	_drift_charge = 0.0
	_lean_left_visual = (_drift_dir < 0)
	_post_settle_time = 0.0

	# Fixed outward slip feel (stronger for SNES vibe; adjust to taste)
	# You already add side-slip in Update(), so seed it harder at start:
	var outward_sign := 1.0
	if _drift_dir >= 0:
		outward_sign = -1.0
	_drift_side_slip += outward_sign * 0.65  # one-off impulse

	# Keep speed nearly intact while drifting
	#_speedMultiplier = DRIFT_SPEED_MULT

func _register_default_actions() -> void:
	# Ensure actions exist once
	for action in ["Forward", "Left", "Right", "Brake", "Hop", "Drift", "Item"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	# Gamepad
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

	# Keyboard
	var ev: InputEventKey

	# Forward: W, Up
	ev = InputEventKey.new(); ev.keycode = KEY_W;       InputMap.action_add_event("Forward", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_UP;      InputMap.action_add_event("Forward", ev)

	# Brake: S, Down
	ev = InputEventKey.new(); ev.keycode = KEY_S;       InputMap.action_add_event("Brake", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_DOWN;    InputMap.action_add_event("Brake", ev)

	# Left / Right: A/D, ←/→
	ev = InputEventKey.new(); ev.keycode = KEY_A;       InputMap.action_add_event("Left", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_LEFT;    InputMap.action_add_event("Left", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_D;       InputMap.action_add_event("Right", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_RIGHT;   InputMap.action_add_event("Right", ev)

	# Hop: Space
	ev = InputEventKey.new(); ev.keycode = KEY_SPACE;   InputMap.action_add_event("Hop", ev)

	# Drift: Shift (both)
	ev = InputEventKey.new(); ev.keycode = KEY_SHIFT;  InputMap.action_add_event("Drift", ev)

	# Item: E (keyboard) / B (pad)
	ev = InputEventKey.new(); ev.keycode = KEY_E;       InputMap.action_add_event("Item", ev)
	jb.button_index = JOY_BUTTON_B
	InputMap.action_add_event("Item", jb.duplicate())

func _apply_hop_sprite_offset() -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return  # sprite not ready yet; try next frame

	# lazily capture the base offset once
	if not _has_base_sprite_offset:
		_base_sprite_offset_y = spr.offset.y
		_has_base_sprite_offset = true

	var dt: float = get_process_delta_time()

	if _hop_timer > 0.0:
		_hop_timer = max(0.0, _hop_timer - dt)
		var t: float = clamp(1.0 - (_hop_timer / HOP_DURATION), 0.0, 1.0)
		var y: float = sin(PI * t) * HOP_HEIGHT

		var off: Vector2 = spr.offset
		off.y = _base_sprite_offset_y - y
		spr.offset = off
	else:
		var off: Vector2 = spr.offset
		off.y = _base_sprite_offset_y
		spr.offset = off

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

@export var DUST_ON_MULT := 3.0     # how dense when ON (try 2.0–5.0)
@export var DUST_OFF_MULT := 1.0    # base density when OFF
@export var DUST_SMOOTH_RATE := 10.0 # larger = snappier easing

var _dust_mult_target := 1.0
var _dust_mult := 1.0
var _dust_base := -1

func _emit_dust(on: bool) -> void:
	var p := _try_get_node(DRIFT_PARTICLE_NODE)
	if p == null:
		return

	# Set target density; don't yank the system immediately
	_dust_mult_target = DUST_ON_MULT if on else DUST_OFF_MULT

	if p is GPUParticles2D:
		var gp := p as GPUParticles2D
		if _dust_base < 0:
			_dust_base = max(1, gp.amount)

		# Ensure emitting when turning ON
		if on and not gp.emitting:
			gp.emitting = true

		# Only turn OFF once we've eased back to base
		if (not on) and gp.emitting and _dust_mult <= DUST_OFF_MULT + 0.01:
			gp.emitting = false
		return

	if p is AnimatedSprite2D:
		var aspr := p as AnimatedSprite2D
		# visibility handled by easing below; ensure an anim exists
		if on:
			aspr.visible = true
			if aspr.sprite_frames != null and not aspr.sprite_frames.get_animation_names().is_empty():
				if aspr.animation == "":
					aspr.animation = aspr.sprite_frames.get_animation_names()[0]
				if not aspr.is_playing(): aspr.play()
		else:
			# let easing fade the speed; we’ll hide when near zero below
			pass
		return

	if p is Sprite2D:
		(p as Sprite2D).visible = on

func _update_drift_dust_smoothing(dt: float) -> void:
	var p := _try_get_node(DRIFT_PARTICLE_NODE)
	if p == null:
		return

	# Exponential smoothing toward target
	var a = clamp(dt * DUST_SMOOTH_RATE, 0.0, 1.0)
	_dust_mult = lerp(_dust_mult, _dust_mult_target, a)

	if p is GPUParticles2D:
		var gp := p as GPUParticles2D
		if _dust_base < 0:
			_dust_base = max(1, gp.amount)
		var desired = max(1, int(round(_dust_base * _dust_mult)))
		if gp.amount != desired:
			gp.amount = desired
		return

	if p is AnimatedSprite2D:
		var aspr := p as AnimatedSprite2D
		aspr.speed_scale = max(0.01, _dust_mult)  # fade rate
		# hide when effectively off
		aspr.visible = _dust_mult > 0.05

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

func _spinout_update_meter(dt: float, input_vec: Vector2) -> void:
	if _is_spinning:
		return

	# Require active drift AND real steering pressure to build meter
	var steer := input_vec.x
	var steer_abs = abs(steer)

	if _is_drifting and steer_abs >= SPIN_MIN_STEER:
		var add = SPIN_BUILD_BASE + SPIN_BUILD_STEER_GAIN * steer_abs
		_spin_meter += add * dt

		if _spin_meter >= SPIN_THRESHOLD:
			# require a non-zero steer to trip; define spin direction now
			if steer > 0.0:
				_drift_dir = 1
			elif steer < 0.0:
				_drift_dir = -1
			else:
				_spin_meter = SPIN_THRESHOLD - 0.01
				return
			_spinout_start()
	else:
		# quick forgiveness when you’re not applying enough steer or not drifting
		_spin_meter = max(0.0, _spin_meter - 30.0 * dt)

func _spinout_start() -> void:
	# end drift immediately, no turbo award
	_cancel_drift_no_award(0.0)

	# if somehow unset, derive from current steer so left/right is defined
	if _drift_dir == 0:
		var steer_now := ReturnPlayerInput().x
		if steer_now > 0.0:
			_drift_dir = 1
		elif steer_now < 0.0:
			_drift_dir = -1
		else:
			_drift_dir = 1  # safe default

	_is_spinning = true
	_spin_timer = SPIN_DURATION
	_spin_phase = 0.0
	_spin_meter = 0.0
	#_speedMultiplier = SPIN_SPEED_MULT

	_emit_dust(true)
	_emit_sparks(true)
	_set_sparks_color(Color(1.0, 0.95, 0.65))

func _spinout_tick(dt: float) -> void:
	if not _is_spinning:
		return
	_spin_timer -= dt
	# advance phase so we can swap left/right a few times over the duration
	_spin_phase += (SPIN_ANIM_CYCLES / SPIN_DURATION) * dt  # cycles per duration

	if _spin_timer <= 0.0:
		_is_spinning = false
		_speedMultiplier = 1.0
		_emit_dust(false)
		_emit_sparks(false)
		_post_spin_lock = SPIN_RECOVER_STEER_LOCK

# Call this from Update() after computing nextPos and doing wall checks/side-slip:
# _finalize_move_with_item_comp(nextPos, mapForward)
func _finalize_move_with_item_comp(nextPos: Vector3, mapForward: Vector3) -> void:
	var nextPixelPos := Vector2i(ceil(nextPos.x), ceil(nextPos.z))
	var curr_rt = _collisionHandler.ReturnCurrentRoadType(nextPixelPos)

	# Apply terrain effects first
	HandleRoadType(nextPixelPos, curr_rt)

	# Then compensate terrain if item boost is active (requires _apply_item_terrain_comp from step 2)
	_apply_item_terrain_comp(curr_rt)

	# Finish movement for this frame
	SetMapPosition(nextPos)
	UpdateMovementSpeed()
	UpdateVelocity(mapForward)

func _recompute_speed_multiplier() -> void:
	var boost := 1.0

	# hop boost
	if _hop_timer > 0.0:
		if boost < HOP_SPEED_BOOST:
			boost = HOP_SPEED_BOOST

	# item boost (already timed)
	if _item_boost_timer > 0.0:
		if boost < ITEM_BOOST_MULT:
			boost = ITEM_BOOST_MULT

	# turbo boost (already timed)
	if _turbo_timer > 0.0:
		# pick the bigger turbo mult based on what you last awarded
		var maybe_turbo = max(TURBO_SMALL_MULT, TURBO_BIG_MULT)
		if boost < maybe_turbo:
			boost = maybe_turbo		

	# drift: treat as a floor (classic slight slow), but don't suppress stronger boosts
	if _is_drifting:
		if boost < DRIFT_SPEED_MULT:
			boost = DRIFT_SPEED_MULT

	# spin: hard cap (spin must be slow)
	if _is_spinning:
		boost = min(boost, SPIN_SPEED_MULT)

	_speedMultiplier = boost
