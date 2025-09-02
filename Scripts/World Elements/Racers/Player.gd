# Player.gd
extends "res://Scripts/World Elements/Racers/Racer.gd"

# === Controls & Drift/Hop Settings ===
const DRIFT_MIN_SPEED := 60.0
const DRIFT_STEER_MULT := 0.86
const DRIFT_SPEED_MULT := 0.92
const DRIFT_BUILD_RATE := 28.0
const TURBO_THRESHOLD_SMALL := 35.0
const TURBO_THRESHOLD_BIG := 80.0
const TURBO_SMALL_MULT := 1.005
const TURBO_BIG_MULT := 1.02
const TURBO_TIME := 0.25

# === Nitro (replaces hop) ===
const NITRO_DURATION := 0.32          # same window length as old hop
const NITRO_MULT := 1.002            # same tiny speed bump as old hop
const NITRO_MIN_ACTIVATE_FRAC := 0.01  # need ≥35% to engage AND to stay on
@export var NITRO_TEMP_CAP_FACTOR := 1.10  # brief headroom while nitro runs

var _nitro_timer := 0.0
var _nitro_latched := false             # persists until you toggle it off

# === Nitro gauge (hold-to-drain, release-to-refill) ===
@export var NITRO_CAPACITY_S := 3.0      # seconds of continuous nitro from full
@export var NITRO_REFILL_S   := 2.4      # seconds to refill from empty to full
var _nitro_charge: float = 1.0           # 0..1 gauge

# HUD hookup (set this to your RaceHUD node in the inspector)
@export var hud_path: NodePath
var _hud: Node = null

@export var TERRAIN_DECAY_HALF_LIFE := 0.016   # slows down over ~0.18s when terrain gets worse
@export var TERRAIN_RECOVER_HALF_LIFE := 0.008 # recovers a bit faster when terrain improves
var _terrain_mult_s := 1.0                    # smoothed terrain multiplier

var _turbo_pulse := 1.0
var _hop_timer := 0.0
var _hop_boost_timer := 0.0
var _is_drifting := false
var _drift_dir := 0
var _drift_charge := 0.0
var _turbo_timer := 0.0
var _base_sprite_offset_y := 0.0
const FRAMES_PER_ROW := 12

const TURN_STRAIGHT_INDEX := 0
const TURN_INCREASES_TO_RIGHT := true

const BASIC_MAX := 3
const DRIFT_MAX := 4
const LEAN_LERP_SPEED := 14.0
const STEER_SIGN := -1.0

var _lean_visual := 0.0
var _lean_left_visual := false

# === Sprite drift behavior (SNES-ish) ===
const DRIFT_WOBBLE_FREQ := 8
const DRIFT_WOBBLE_AMPL := 0.40
const DRIFT_BASE_BIAS := 0.7
const DRIFT_RELEASE_BURST_TIME := 0.24

@export var drift_particle_path: NodePath = ^"Road Type Effects/Right Wheel Special"
@export var sparks_particle_path: NodePath = ^"Road Type Effects/Left Wheel Special" # or a GPUParticles2D if you have one

var _drift_wobble_phase := 0.0
var _drift_release_timer := 0.0

const POST_DRIFT_SETTLE_TIME := 0.18
var _post_settle_time := 0.0

const DRIFT_STEER_DEADZONE := 0.25
const DRIFT_ARM_WINDOW := 0.20
var _drift_arm_timer := 0.0

const DRIFT_MIN_TURN_BIAS := 0.55
const DRIFT_VISUAL_STEER_GAIN := 0.22

const DRIFT_BREAK_DEADZONE := 0.12
const DRIFT_BREAK_GRACE := 0.10
const DRIFT_REVERSE_BREAK := 0.25
const POST_DRIFT_SETTLE_TIME_BREAK := 0.12

# --- Brief cap headroom when drift starts (avoids hard clamp) ---
@export var DRIFT_TEMP_CAP_FACTOR := 1.08
const DRIFT_CAP_ENTRY_TIME := 0.40  # seconds of extra headroom after drift starts

@export var RELEASE_BOOST_HALF_LIFE := 0.18   # seconds to halve the release boost
var _release_boost := 0.0                     # extra multiplier above 1.0 that decays

var _drift_cap_timer := 0.0

var _drift_break_timer := 0.0
const TAU := PI * 2.0

# --- SNES-ish feel controls ---
const DRIFT_GRIP := 0.55
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

var _dust_was_on := false
var _sparks_was_on := false

var _has_base_sprite_offset: bool = false
@onready var _sfx: Node = get_node_or_null(^"Audio")  # KartSFX.gd lives here

# --- Item boost terrain compensation (tune to taste) ---
@export var ITEM_COMP_OFF_ROAD := 1.40   # extra “anti-slow” while boosting on OFF_ROAD
@export var ITEM_COMP_GRAVEL  := 1.20   # extra “anti-slow” while boosting on GRAVEL

# --- Wall collision tuning ---
@export var WALL_RESTITUTION      := 0.35   # 0 = no bounce, 1 = perfectly bouncy
@export var WALL_SLIDE_KEEP       := 0.85   # keep this fraction of tangential speed
@export var WALL_SEPARATION_EPS   := 0.50   # small nudge away from wall (pixels)
@export var WALL_BUMP_STRENGTH    := 1.0    # impulse fed into SetCollisionBump()
@export var WALL_HIT_COOLDOWN_S   := 0.10   # min time between bumps

@export var REAR_BUMP_COOLDOWN_MULT := 2.4  # extend cooldown on rear shoves
var _last_map_forward: Vector3 = Vector3(0, 0, 1)  # cached last mapForward

var _wall_hit_cd := 0.0
var _primed_sprite := false

@export var ITEM_TEMP_CAP_FACTOR  := 1.60  # temporary headroom while item is active
@export var TURBO_TEMP_CAP_FACTOR := 1.45  # temporary headroom while turbo is active
@export var HOP_TEMP_CAP_FACTOR   := 1.10  # tiny headroom while hop is active

@export var BUMP_SFX_MIN_IMPULSE: float = 1.10   # >1.0 skips wall axis-bumps, catches racer bumps
@export var BUMP_SFX_COOLDOWN_S: float = 0.10    # avoid rapid repeats
var _bump_sfx_cd := 0.0

@export var DUST_ON_MULT := 3.0     # how dense when ON (try 2.0–5.0)
@export var DUST_OFF_MULT := 1.0    # base density when OFF
@export var DUST_SMOOTH_RATE := 10.0 # larger = snappier easing

var _dust_mult_target := 1.0
var _dust_mult := 1.0
var _dust_base := -1

# --- Per-entity collision size (used only when SpriteHandler.collision_radius_mode == 2)
@export var collision_radius_px: float = 8.0  # try 6–12 px until it feels right

@export var nitro_shader_path: String = "res://Scripts/Shaders/NitroPulse.gdshader"
@export var nitro_glow_color: Color = Color(0.55, 0.9, 1.0, 1.0)
@export var nitro_outline_px: float = 2.0
@export var nitro_chroma_max_px: float = 3.0     # how far RGB splits at peak
@export var nitro_intensity_max: float = 1.0     # cap the shader “strength”

var _nitro_mat: ShaderMaterial = null
var _nitro_prev_material: Material = null

# --- Character color (Yoshi-style hue swap) ---
@export_file("*.gdshader") var yoshi_shader_path: String = "res://Scripts/Shaders/YoshiSwap.gdshader"
@export var yoshi_source_hue: float = 0.333333
@export var yoshi_tolerance: float = 0.08
@export var yoshi_edge_soft: float = 0.20
var _yoshi_mat: ShaderMaterial = null

var DEFAULT_POINTS: PackedVector2Array = PackedVector2Array([
	Vector2(920, 584),
	Vector2(950, 607),
	Vector2(920, 631),
	Vector2(950, 655),
	Vector2(920, 679),
	Vector2(950, 703),
	Vector2(920, 727),
	Vector2(950, 751)
])

func ReturnCollisionRadiusUV() -> float:
	# Convert the pixel radius to UV using your map’s real width.
	var map_w := 1024.0
	var p := get_node_or_null(pseudo3d_ref)
	if p is Sprite2D and (p as Sprite2D).texture:
		map_w = float((p as Sprite2D).texture.get_size().x)
	return clamp(collision_radius_px / map_w, 0.0001, 0.05)

func _compute_temp_cap(base_cap: float) -> float:
	var cap := base_cap

	# item headroom
	if _item_boost_timer > 0.0:
		var c := base_cap * ITEM_TEMP_CAP_FACTOR
		if cap < c:
			cap = c

	# turbo headroom
	if _turbo_timer > 0.0:
		var c := base_cap * TURBO_TEMP_CAP_FACTOR
		if cap < c:
			cap = c

	# nitro (replaces hop) headroom
	if _nitro_timer > 0.0:
		var c := base_cap * NITRO_TEMP_CAP_FACTOR
		if cap < c:
			cap = c

	# brief headroom after drift starts
	if _drift_cap_timer > 0.0:
		var c := base_cap * DRIFT_TEMP_CAP_FACTOR
		if cap < c:
			cap = c

	# spin limits speed
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

	_prime_sprite_grid_once()
	_base_sprite_offset_y = spr.offset.y
	add_to_group("racers")

	# --- Apply selected racer color from Globals ---
	_ensure_yoshi_material()
	_apply_player_palette_from_globals()

	# HUD link
	_hud = get_node_or_null(hud_path)
	if _hud == null:
		_hud = get_tree().get_first_node_in_group("race_hud")  # optional group fallback

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
	if _is_drifting:
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
	_last_map_forward = mapForward  # cache player facing for SFX logic
	
	if _isPushedBack:
		ApplyCollisionBump()
	
	var dt := get_process_delta_time()
	_bump_sfx_cd = max(0.0, _bump_sfx_cd - dt)

	# Smoothly decay the post-drift release boost
	if _release_boost > 0.0:
		var a := 1.0 - pow(0.5, dt / max(0.0001, RELEASE_BOOST_HALF_LIFE))
		_release_boost = max(0.0, _release_boost - _release_boost * a)

	if _drift_cap_timer > 0.0:
		_drift_cap_timer = max(0.0, _drift_cap_timer - dt)

	if _post_spin_lock > 0.0:
		_post_spin_lock = max(0.0, _post_spin_lock - dt)

	# inputs
	var input_vec := ReturnPlayerInput()

	# spinout flow
	_spinout_update_meter(dt, input_vec)
	_spinout_tick(dt)

	# --- Item boost trigger (only item stuff lives here) ---
	if Input.is_action_just_pressed("Item"):
		if (not _is_spinning) and _item_cooldown_timer <= 0.0:
			_item_boost_timer = ITEM_BOOST_TIME
			_item_cooldown_timer = ITEM_BOOST_TIME + ITEM_COOLDOWN
			_emit_sparks(true)
			_set_sparks_color(Color(0.6, 1.0, 0.4)) # greenish boost flash

	# block drift/nitro while spinning
	if not _is_spinning:
		_handle_hop_and_drift(input_vec)  # drift + nitro (no hop)

	# Timers decay (non-nitro)
	if _item_boost_timer > 0.0:
		_item_boost_timer = max(0.0, _item_boost_timer - dt)
	if _turbo_timer > 0.0:
		_turbo_timer = max(0.0, _turbo_timer - dt)

	# === Nitro: hold/tap → only active with enough gauge; shader only while active ===
	var nitro_down := Input.is_action_pressed("Nitro")
	var nitro_tap  := Input.is_action_just_pressed("Nitro")

	# Tap cancels latch
	if _nitro_latched and nitro_tap:
		_nitro_latched = false

	var want_request := (_nitro_latched or nitro_down) and not _is_spinning
	var drain_rate  = 1.0 / max(0.001, NITRO_CAPACITY_S)
	var refill_rate = 1.0 / max(0.001, NITRO_REFILL_S)

	# Engage only if gauge ≥ threshold; also auto-drop below threshold
	var can_nitro := want_request and (_nitro_charge >= NITRO_MIN_ACTIVATE_FRAC)

	if can_nitro:
		# drain and show shader
		_nitro_charge = max(0.0, _nitro_charge - drain_rate * dt)
		_nitro_timer  = 1.0  # visual ON while active
		# if we run under threshold, we’ll flip off next frame
	else:
		# stop visuals, clear latch unless the button is still held
		_nitro_timer  = 0.0
		if not nitro_down:
			_nitro_latched = false
		# refill
		_nitro_charge = min(1.0, _nitro_charge + refill_rate * dt)

	_apply_nitro_fx(mapForward)
	_push_nitro_hud()

	# DRIFT side-slip feed (visual/feel), no change when spinning
	var right_vec := Vector3(-mapForward.z, 0.0, mapForward.x).normalized()
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

	# predict next pos
	var nextPos : Vector3 = _mapPosition + ReturnVelocity()
	var nextPixelPos : Vector2i = Vector2i(ceil(nextPos.x), ceil(nextPos.z))

	# --- X axis wall ---
	if _has_collision_api():
		if _collisionHandler.IsCollidingWithWall(Vector2i(ceil(nextPos.x), ceil(_mapPosition.z))):
			nextPos.x = _mapPosition.x
			SetCollisionBump(Vector3(-sign(ReturnVelocity().x), 0.0, 0.0))
			if _wall_hit_cd <= 0.0 and _sfx and _sfx.has_method("play_collision"):
				_sfx.play_collision()
				_wall_hit_cd = WALL_HIT_COOLDOWN_S

	# --- Z axis wall ---
	if _has_collision_api():
		if _collisionHandler.IsCollidingWithWall(Vector2i(ceil(_mapPosition.x), ceil(nextPos.z))):
			nextPos.z = _mapPosition.z
			SetCollisionBump(Vector3(0.0, 0.0, -sign(ReturnVelocity().z)))
			if _wall_hit_cd <= 0.0 and _sfx and _sfx.has_method("play_collision"):
				_sfx.play_collision()
				_wall_hit_cd = WALL_HIT_COOLDOWN_S

	# --- Terrain type ---
	var curr_rt := Globals.RoadType.ROAD
	if _has_collision_api():
		curr_rt = _collisionHandler.ReturnCurrentRoadType(Vector2i(ceil(nextPos.x), ceil(nextPos.z)))
	HandleRoadType(Vector2i(ceil(nextPos.x), ceil(nextPos.z)), curr_rt)

	# apply drift side-slip after wall clamps
	nextPos += right_vec * _drift_side_slip * dt

	var terrain_raw := _speedMultiplier
	if terrain_raw <= 0.0:
		terrain_raw = 1.0

	var hl: float
	if terrain_raw < _terrain_mult_s:
		hl = TERRAIN_DECAY_HALF_LIFE
	else:
		hl = TERRAIN_RECOVER_HALF_LIFE

	var a := 1.0 - pow(0.5, dt / max(0.0001, hl))
	_terrain_mult_s = _terrain_mult_s + (terrain_raw - _terrain_mult_s) * a

	# BOOST (separate from terrain)
	var boost_mult := _recompute_speed_multiplier()

	# combine
	_speedMultiplier = _terrain_mult_s
	_apply_item_terrain_comp(curr_rt)
	_speedMultiplier = _terrain_mult_s * boost_mult
	if _speedMultiplier < 0.01:
		_speedMultiplier = 0.01

	# Move
	SetMapPosition(nextPos)
	UpdateMovementSpeed()
	UpdateVelocity(mapForward)

	# Visuals / sprite
	_choose_and_apply_frame(get_process_delta_time())
	_wall_hit_cd = max(0.0, _wall_hit_cd - dt)

func _push_nitro_hud() -> void:
	if _hud == null:
		return
	# active if timer > 0 (shader on) OR latched/held with charge remaining
	var is_active := (_nitro_timer > 0.0) or (_nitro_latched and _nitro_charge > 0.0)
	if _hud.has_method("SetNitro"):
		# expects (level_0_1, active_bool) — see RaceHUD.gd below
		_hud.call("SetNitro", _nitro_charge, is_active)

func ReturnPlayerInput() -> Vector2:
	var raw_right := Input.get_action_strength("Right")
	var raw_left  := Input.get_action_strength("Left")
	var steer_raw := raw_right - raw_left

	var forward := Input.get_action_strength("Forward")
	var brake   := Input.get_action_strength("Brake")

	# brief steer lock after a spin
	if _post_spin_lock > 0.0:
		steer_raw = 0.0

	# Apply deadzone to the raw value
	if abs(steer_raw) < STEER_DEADZONE:
		steer_raw = 0.0

	# Response curve: soften around center so small inputs turn less
	var steer_mag = abs(steer_raw)
	if steer_mag > 0.0:
		steer_mag = pow(steer_mag, max(0.01, STEER_CURVE))  # 1.25 softens near center
	var steer_shaped = steer_mag
	if steer_raw < 0.0:
		steer_shaped = -steer_mag

	# Global steering gain for normal steering (non-drift path)
	var steer = steer_shaped * STEER_GAIN * STEER_SIGN

	# Throttle/brake (unchanged)
	var throttle := -forward
	if brake > 0.01:
		throttle = -brake

	# While spinning, ignore steer/throttle so the kart coasts under damped speed
	if _is_spinning:
		_inputDir = Vector2(0.0, 0.0)
		return _inputDir

	_inputDir = Vector2(steer, throttle)
	return _inputDir

func _handle_hop_and_drift(input_vec : Vector2) -> void:
	var dt := get_process_delta_time()

	# Inputs / gates
	var nitro_down := Input.is_action_pressed("Nitro")            # HOLD to keep nitro alive
	var nitro_just := Input.is_action_just_pressed("Nitro")       # only for arming drift / SFX once
	var drift_down := Input.is_action_pressed("Drift")
	var moving_fast := _movementSpeed >= DRIFT_MIN_SPEED
	var steer_abs = abs(input_vec.x)
	var steer_sign = sign(input_vec.x)

	_sfx.play_hop()
	
	# Nitro: HOLD keeps effect alive (timer is maintained in Update); first press arms drift
	if nitro_just and not _is_drifting:
		_drift_arm_timer = DRIFT_ARM_WINDOW
		if _sfx != null:
			if _sfx.has_method("play_boost"):
				_sfx.play_boost()
			elif _sfx.has_method("play_hop"):
				_sfx.play_hop()  # fallback sound if you want

	# Only kick the shader if we actually have enough gauge to run nitro
	if nitro_down and _nitro_charge >= NITRO_MIN_ACTIVATE_FRAC:
		_nitro_timer = 1.0   # simple “on” flag for visuals this frame
		
	# decay arm timer
	if _drift_arm_timer > 0.0:
		_drift_arm_timer = max(0.0, _drift_arm_timer - dt)

	# Start drift if armed, fast enough, and steering clearly
	if (not _is_drifting) and drift_down and (_drift_arm_timer > 0.0) and moving_fast and (steer_abs >= DRIFT_STEER_DEADZONE):
		var dir := 1
		if steer_sign < 0.0:
			dir = -1
		_start_drift_snes(dir)

	# While drifting and holding drift
	if _is_drifting and drift_down:
		# Outward bias + steer-shaped contribution (use raw steer, not smoothed)
		var sign_dir := float(_drift_dir)            # +1 right, -1 left
		var target_bias := DRIFT_MIN_TURN_BIAS       # baseline outward lean (e.g. 0.55)
		target_bias += steer_abs * DRIFT_STEER_MULT  # make the knob matter

		# Keep it in range and point outward, then ease in with grip
		var clamped = clamp(sign_dir * target_bias, -1.0, 1.0)
		var grip_t = clamp(dt * (DRIFT_GRIP * 10.0), 0.0, 1.0)
		_inputDir.x = lerp(_inputDir.x, clamped, grip_t)

		# Build drift charge faster with more steer pressure
		var add = (0.75 + 0.25 * steer_abs) * DRIFT_BUILD_RATE * dt
		_drift_charge = max(0.0, _drift_charge + add)

		# Quick-cancel rules
		if steer_sign != 0 and steer_sign == -_drift_dir and steer_abs >= DRIFT_REVERSE_BREAK:
			_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		elif steer_abs < DRIFT_BREAK_DEADZONE:
			_drift_break_timer += dt
			if _drift_break_timer >= DRIFT_BREAK_GRACE:
				_cancel_drift_no_award(POST_DRIFT_SETTLE_TIME_BREAK)
		else:
			_drift_break_timer = 0.0

	# Release drift
	if _is_drifting and not drift_down:
		_end_drift_with_award()

# SNES-like drift start: lock direction, fixed slip "set", reset counters.
func _start_drift_snes(dir: int) -> void:
	_is_drifting = true

	if _sfx and _sfx.has_method("set_drift_active"):
		_sfx.set_drift_active(true)
		
	if dir < 0:
		_drift_dir = -1
	else:
		_drift_dir = 1

	# brief headroom to avoid instant cap slap when entering drift fast
	_drift_cap_timer = DRIFT_CAP_ENTRY_TIME

	_drift_wobble_phase = 0.0
	_drift_break_timer = 0.0
	_drift_charge = 0.0
	_lean_left_visual = (_drift_dir < 0)
	_post_settle_time = 0.0

	# Fixed outward slip feel (SMK vibe): small one-off outward impulse
	var outward_sign := 1.0
	if _drift_dir >= 0:
		outward_sign = -1.0
	_drift_side_slip += outward_sign * 0.65

	# No drift slow here; drifting is speed-neutral
	_emit_dust(true)
	_emit_sparks(false)

func _register_default_actions() -> void:
	# Ensure actions exist once (now includes RearView + Nitro)
	for action in ["Forward", "Left", "Right", "Brake", "Hop", "Drift", "Item", "RearView", "Nitro"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)

	# --- Gamepad ---
	var jb := InputEventJoypadButton.new()
	jb.device = -1  # accept any controller (prevents Windows device-id mismatches)

	# Forward: A
	jb.button_index = JOY_BUTTON_A
	InputMap.action_add_event("Forward", jb.duplicate())

	# Hop / Drift / Nitro: Right Shoulder (RB)
	jb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("Hop", jb.duplicate())
	InputMap.action_add_event("Drift", jb.duplicate())
	InputMap.action_add_event("Nitro", jb.duplicate())

	# RearView: Left Shoulder (LB)
	jb.button_index = JOY_BUTTON_LEFT_SHOULDER
	InputMap.action_add_event("RearView", jb.duplicate())

	# Left / Right: D-Pad
	jb.button_index = JOY_BUTTON_DPAD_LEFT
	InputMap.action_add_event("Left", jb.duplicate())
	jb.button_index = JOY_BUTTON_DPAD_RIGHT
	InputMap.action_add_event("Right", jb.duplicate())

	# Item: B (pad)
	jb.button_index = JOY_BUTTON_B
	InputMap.action_add_event("Item", jb.duplicate())

	# --- Keyboard ---
	var ev: InputEventKey

	# Forward: W, Up
	ev = InputEventKey.new(); ev.keycode = KEY_W;     InputMap.action_add_event("Forward", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_UP;    InputMap.action_add_event("Forward", ev)

	# Brake: S, Down
	ev = InputEventKey.new(); ev.keycode = KEY_S;     InputMap.action_add_event("Brake", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_DOWN;  InputMap.action_add_event("Brake", ev)

	# Left / Right: A/D, ←/→
	ev = InputEventKey.new(); ev.keycode = KEY_A;     InputMap.action_add_event("Left", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_LEFT;  InputMap.action_add_event("Left", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_D;     InputMap.action_add_event("Right", ev)
	ev = InputEventKey.new(); ev.keycode = KEY_RIGHT; InputMap.action_add_event("Right", ev)

	# Drift: Shift (either)
	ev = InputEventKey.new(); ev.keycode = KEY_SHIFT; InputMap.action_add_event("Drift", ev)

	# Item: E (keyboard)
	ev = InputEventKey.new(); ev.keycode = KEY_E;     InputMap.action_add_event("Item", ev)

	# Nitro: Space (old Hop key)
	ev = InputEventKey.new(); ev.keycode = KEY_SPACE; InputMap.action_add_event("Nitro", ev)

	# RearView (keyboard): TAB (hold to look back)
	ev = InputEventKey.new(); ev.keycode = KEY_TAB;   InputMap.action_add_event("RearView", ev)

func _apply_hop_sprite_offset() -> void:
	# intentionally empty — nitro has no visual bob
	return

func _try_get_node(path: String) -> Node:
	if has_node(path):
		return get_node(path)
	return null
	
func _get_drift_node() -> Node:
	var n := get_node_or_null(drift_particle_path)
	if n == null: n = find_child("DriftDust", true, false)
	return n

func _get_sparks_node() -> Node:
	var n := get_node_or_null(sparks_particle_path)
	if n == null: n = find_child("DriftSparks", true, false)
	return n

func _set_sparks_color(col: Color) -> void:
	var p := _get_sparks_node()
	if p != null and p is GPUParticles2D:
		p.process_material.color = col

func _emit_sparks(on: bool) -> void:
	var p := _get_sparks_node()
	if p != null and p is GPUParticles2D:
		p.emitting = on
	elif p is CanvasItem:
		(p as CanvasItem).visible = on

func _emit_dust(on: bool) -> void:
	var p := _get_drift_node()
	if p == null:
		return

	# Set target density; don't yank the system immediately
	_dust_mult_target = DUST_ON_MULT if on else DUST_OFF_MULT

	# Rising edge detection
	var rising := on and (not _dust_was_on)
	_dust_was_on = on

	if p is GPUParticles2D:
		var gp := p as GPUParticles2D
		if _dust_base < 0:
			_dust_base = max(1, gp.amount)

		if on:
			# On edge only: force a fresh emission so it never looks stuck
			if rising:
				gp.emitting = false
				gp.emitting = true
				gp.restart()
		else:
			# Only turn OFF once we've eased back to base
			if gp.emitting and _dust_mult <= DUST_OFF_MULT + 0.01:
				gp.emitting = false
		return

	if p is AnimatedSprite2D:
		var aspr := p as AnimatedSprite2D
		if on:
			aspr.visible = true
			# Choose a default animation if none
			if aspr.sprite_frames != null and not aspr.sprite_frames.get_animation_names().is_empty():
				if aspr.animation == "":
					aspr.animation = aspr.sprite_frames.get_animation_names()[0]
			# On edge only: hard restart so it doesn't resume on the last frame
			if rising:
				aspr.play()
				aspr.frame = 0
			if not aspr.is_playing():
				aspr.play()
		else:
			# let smoothing reduce speed; hide once effectively off (done in smoother)
			pass
		return

	if p is Sprite2D:
		(p as Sprite2D).visible = on

func _cancel_drift_no_award(settle_time: float) -> void:
	_is_drifting = false
	
	if _sfx and _sfx.has_method("set_drift_active"):
		_sfx.set_drift_active(false)
		
	_speedMultiplier = 1.0
	_emit_dust(false)
	_emit_sparks(false)
	_drift_release_timer = 0.0
	_post_settle_time = settle_time
	_lean_left_visual = (_drift_dir < 0)
	_drift_charge = 0.0

func _end_drift_with_award() -> void:
	# End drift, but do not force sprite changes
	_is_drifting = false
	_emit_dust(false)
	_emit_sparks(false)

	var did_award := false

	# Award: smoothed boost + temporary cap headroom
	if _drift_charge >= TURBO_THRESHOLD_BIG:
		_turbo_timer = TURBO_TIME             # keeps headroom
		_release_boost = TURBO_BIG_MULT - 1.0 # temporary boost
		_drift_release_timer = DRIFT_RELEASE_BURST_TIME
		did_award = true
		if _sfx and _sfx.has_method("play_boost"):
			_sfx.play_boost()
	elif _drift_charge >= TURBO_THRESHOLD_SMALL:
		_turbo_timer = TURBO_TIME
		_release_boost = TURBO_SMALL_MULT - 1.0
		_drift_release_timer = DRIFT_RELEASE_BURST_TIME * 0.75
		did_award = true
		if _sfx and _sfx.has_method("play_boost"):
			_sfx.play_boost()
	else:
		_drift_release_timer = 0.0

	# Reset drift charge regardless
	_drift_charge = 0.0

func ReturnIsHopping() -> bool:
	return false

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

	if _sfx and _sfx.has_method("play_spin"):
		_sfx.play_spin()

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

func _recompute_speed_multiplier() -> float:
	var boost := 1.0

	# Nitro micro-boost (replaces hop)
	if _nitro_timer > 0.0:
		if NITRO_MULT > boost:
			boost = NITRO_MULT

	# Item mushroom
	if _item_boost_timer > 0.0:
		if ITEM_BOOST_MULT > boost:
			boost = ITEM_BOOST_MULT

	# Spin is a hard cap
	if _is_spinning:
		if SPIN_SPEED_MULT < boost:
			boost = SPIN_SPEED_MULT

	# Smoothed drift-release bonus
	if _release_boost > 0.0:
		var b := 1.0 + _release_boost
		if b > boost:
			boost = b

	return boost

func SetCollisionBump(bumpDir: Vector3) -> void:
	# keep impulse & pushback
	super.SetCollisionBump(bumpDir)

	# SFX: only from PLAYER (this script) with a cooldown
	if _bump_sfx_cd > 0.0:
		return
	if _sfx == null:
		return
	if not _sfx.has_method("play_bump"):
		return

	# Basic impulse gate you already exported (use magnitude of bumpDir)
	var impulse := bumpDir.length()
	if impulse < BUMP_SFX_MIN_IMPULSE:
		return

	# If the bump is pushing us in our own forward direction, it's a rear shove.
	# (rear shove → longer cooldown so repeated pushing doesn't spam)
	var rear_shove = false
	if _last_map_forward.length() > 0.0001:
		rear_shove = bumpDir.dot(_last_map_forward) > 0.0

	_sfx.play_bump()

	# base cooldown
	var cd := BUMP_SFX_COOLDOWN_S
	# stretch cooldown for rear shoves (AI riding your tail)
	if rear_shove:
		cd *= REAR_BUMP_COOLDOWN_MULT

	_bump_sfx_cd = cd


func _ensure_nitro_material() -> void:
	var sh := load(nitro_shader_path)
	if sh == null:
		push_warning("Nitro shader not found: " + nitro_shader_path)
		return
	if _nitro_mat == null:
		_nitro_mat = ShaderMaterial.new()
		_nitro_mat.shader = sh
		# static defaults; live values updated per-frame
		_nitro_mat.set_shader_parameter("glow_color", nitro_glow_color)
		_nitro_mat.set_shader_parameter("outline_px", nitro_outline_px)
		_nitro_mat.set_shader_parameter("chroma_px", 0.0)
		_nitro_mat.set_shader_parameter("intensity", 0.0)
		_nitro_mat.set_shader_parameter("dir2", Vector2(1, 0))

func _apply_nitro_fx(mapForward: Vector3) -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return

	# live 0..1 “how strong is nitro right now”
	var live := 0.0
	# treat _nitro_timer as a boolean ON flag from Update()
	if _nitro_timer > 0.0:
		live = 1.0

	if live > 0.0:
		# ensure material and attach if needed
		_ensure_nitro_material()
		if _nitro_mat == null:
			return

		if spr.material != _nitro_mat:
			# remember what was there (so we can restore exactly)
			if _nitro_prev_material == null:
				_nitro_prev_material = spr.material
			spr.material = _nitro_mat

		# ease: quicker rise, gentle fall
		var eased := pow(live, 0.5)  # 0..1 (sqrt for “punchy” start)
		var inten = clamp(eased * nitro_intensity_max, 0.0, 1.0)
		var chroma = nitro_chroma_max_px * inten

		# forward in screen-UV space: use your mapForward (XZ → screen x,y sign)
		# mapForward is already normalized in your Update() caller
		var dir2 := Vector2(mapForward.x, mapForward.z)
		if dir2.length() > 0.00001:
			dir2 = dir2.normalized()
		else:
			dir2 = Vector2(1, 0)

		# feed uniforms
		_nitro_mat.set_shader_parameter("intensity", inten)
		_nitro_mat.set_shader_parameter("chroma_px", chroma)
		_nitro_mat.set_shader_parameter("dir2", dir2)
	else:
		# nitro ended: cleanly restore the original material exactly once
		if spr.material == _nitro_mat:
			if _nitro_prev_material != null:
				spr.material = _nitro_prev_material
			else:
				spr.material = null
		_nitro_prev_material = null

func CancelNitro() -> void:
	_nitro_latched = false

func _ensure_yoshi_material() -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return

	# If Nitro is currently active, don't fight it here.
	if spr.material == _nitro_mat:
		return

	# Try to use whatever is already on the sprite if it's a ShaderMaterial.
	var sm: ShaderMaterial = null
	if spr.material != null and spr.material is ShaderMaterial:
		sm = spr.material as ShaderMaterial
		# Make it unique to this scene so multiple racers don't share uniforms.
		if !sm.resource_local_to_scene:
			var dupe := sm.duplicate(true) as ShaderMaterial
			dupe.resource_local_to_scene = true
			spr.material = dupe
			sm = dupe

	# If there's no ShaderMaterial, create one with your Yoshi shader.
	if sm == null:
		if !ResourceLoader.exists(yoshi_shader_path):
			return
		var sh := load(yoshi_shader_path) as Shader
		if sh == null:
			return
		sm = ShaderMaterial.new()
		sm.shader = sh
		sm.resource_local_to_scene = true
		spr.material = sm

	# Track the base material for sanity (not strictly required anymore).
	_yoshi_mat = sm

func _apply_player_palette_from_globals() -> void:
	var spr := ReturnSpriteGraphic()
	if spr == null:
		return
	# Skip while Nitro’s temp material is active; base will be restored later.
	if spr.material == _nitro_mat:
		return

	var name_now := String(Globals.selected_racer)
	var col := Globals.get_racer_color(name_now)

	_ensure_yoshi_material()

	var sm := spr.material
	if sm != null and sm is ShaderMaterial and (sm as ShaderMaterial).shader != null:
		var shmat := sm as ShaderMaterial
		shmat.set_shader_parameter("target_color", col)
		shmat.set_shader_parameter("src_hue",     yoshi_source_hue)
		shmat.set_shader_parameter("hue_tol",     yoshi_tolerance)
		shmat.set_shader_parameter("edge_soft",   yoshi_edge_soft)
	else:
		spr.modulate = col

func RefreshPaletteFromGlobals() -> void:
	_ensure_yoshi_material()
	_apply_player_palette_from_globals()

func IsUsingNitroMaterial() -> bool:
	var spr := ReturnSpriteGraphic()
	if spr == null: return false
	return spr.material == _nitro_mat

func _has_collision_api() -> bool:
	return _collisionHandler != null \
		and _collisionHandler.has_method("IsCollidingWithWall") \
		and _collisionHandler.has_method("ReturnCurrentRoadType")
