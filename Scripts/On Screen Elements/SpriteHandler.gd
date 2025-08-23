# SpriteHandler.gd
extends Node2D

@export var _showSpriteInRangeOf: int = 440
@export var _hazards: Array[Hazard]
@export var _opponents: Array[Racer]

var _worldElements: Array[WorldElement] = []
var _player: Racer
var _mapSize: int = 1024
var _worldMatrix: Basis

# ---- Scene refs for overlay ↔ pseudo3D handshake (optional but supported)
@export var pseudo3d_node: NodePath          # assign your Pseudo3D Sprite2D node
@export var path_overlay_node: NodePath      # assign your PathOverlay2D node
@export var auto_apply_path: bool = true     # auto-push overlay UVs into Pseudo3D once

# ---- Re-entrancy guard to avoid start-up ping-pong freezes
var _is_updating: bool = false
@export var sprite_graphic_path: NodePath = ^"GFX/AngleSprite"

@export var auto_collect_world_elements := true
@export var collect_under: NodePath       # set this to your "Racers" node (folder)
@export var debug_show_all := true        # TEMP: show sprites regardless of distance
@export var invert_depth_scale := true  # <- TRUE = larger when near, smaller when far

# --- scaling knobs ---
@export var player_base_scale_abs: float = 3.0      # player always this big
@export var opponent_min_scale_abs: float = 1.0     # absolute floor for opponent
@export var depth_gain: float = 1.8                 # >1.0 = hit the floor sooner
@export var shrink_when_away := true  # true = shrink when away; false = shrink when near

# --- auto-correct state (per racer) ---
var _last_absdot := {}      # instance_id -> float
var _last_scale  := {}      # instance_id -> float
const _AUTO_EPS := 0.0001

@export var shrink_start_abs: float = 0.00  # start shrinking only after this abs distance
@export var depth_gamma: float = 1.00       # curve exponent ( >1 gentler, <1 harsher )
@export var shrink_deadzone_abs: float = 0.03  # no shrink until |dot| >= this

# --- smoothing controls ---
@export var scale_half_life : float = 0.12   # seconds to move half the gap (higher = smoother)
@export var scale_max_rate  : float = 6.0    # absolute scale units per second (cap)

# --- per-instance smoothed scale cache ---
var _smoothed_scale := {}  # instance_id -> float
# --- smoothing / gating exports ---
@export var cam_half_life      : float = 0.12   # smooth camera forward
@export var depth_half_life    : float = 0.10   # smooth depth distance
@export var angle_power        : float = 1.40   # lateral suppression strength
@export var min_angle_weight   : float = 0.55   # never suppress more than this

var _cam_f_smooth : Vector2 = Vector2(0, 1)
var _d_abs_smooth := {}  # id -> float

# --- Z-order: keep player on top ---
@export var force_player_on_top := true
@export var player_on_top_margin := 10  # how far above the next sprite

# --- Player↔Opponent collision (map-space circle) ---
@export var enable_player_opponent_collision := true
@export var player_radius_uv   : float = 0.001   # in UV units (0..1 across the map)
@export var opponent_radius_uv : float = 0.001   # in UV units (per opponent)
@export var separate_fraction  : float = 1.0     # 1.0 = full separation this frame
@export var bump_on_collision  : bool = true
@export var bump_strength_sign := 1.0            # 1.0 forward along normal, -1.0 opposite

# internal helpers
var _last_collision_time := {}   # id_pair_string -> float
@export var collision_cooldown_s := 0.12

# --- NEW: asymmetric rate caps ---
@export var scale_max_rate_up   : float = 2.0   # units/s when getting bigger
@export var scale_max_rate_down : float = 6.0   # units/s when getting smaller

@export var turn_damp_enabled    := true
@export var turn_freeze_deg_per_s: float = 200.0  # above this, growth is heavily clamped
@export var growth_damp_gain     : float = 2.0    # stronger -> less growth while turning

var _cam_dir_prev : Vector2 = Vector2(0, 1)
var _turn_rate_s  : float   = 0.0
@export var turn_half_life  : float = 0.10

var _inv_world     : Basis
var _screen_cached : Vector2 = Vector2(640, 360)
var _dt_cached     : float = 0.016
var _right_axis    : Vector2 = Vector2(1, 0)

# --- intuitive scaling (pick model) ---
@export var scale_model: int = 0        # 0 = PerspectiveRatio, 1 = DistanceFalloff
@export var ref_distance_uv: float = 0.08  # only used for DistanceFalloff

@export var collision_radius_mode : int = 1  # 0=fixed (current), 1=auto from sprite, 2=custom per-entity
@export var radius_from_sprite_factor : float = 0.40  # ~40% of sprite height feels like “body”
@export var min_radius_uv_auto      : float = 0.010   # floor so tiny sprites still collide
@export var radius_scale_global     : float = 1.00    # quick global tweak (0.8 to shrink, 1.2 to grow)

# --- AI spawn knobs ---
@export var spawn_start_offset : int   = 0     # how far along the path we begin
@export var spawn_stride       : int   = 8     # how many path points to skip between spawns
@export var spawn_min_sep_uv   : float = 0.015 # minimum UV separation between spawns
@export var spawn_jitter_px    : float = 4.0   # small random jitter in px to avoid perfect overlap

# --- Launch (start acceleration) knobs ---
@export var launch_min_target_speed : float = 45.0   # px/s (or your speed unit)
@export var launch_max_target_speed : float = 65.0
@export var launch_min_accel_ps     : float = 60.0   # px/s^2 (or your speed unit^2)
@export var launch_max_accel_ps     : float = 120.0
@export var launch_bump_gain        : float = 1.0    # scale impulses if needed

@export var spawn_debug : bool = true
@export var spawn_debug_draw_markers : bool = true
@export var spawn_debug_color : Color = Color(0, 1, 0, 1)  # green

var _launch_profiles := {}  # id -> { "target": float, "accel": float, "dir": Vector3 }

# --- Yoshi color shader (per-AI recolor) ---
@export var yoshi_shader_path: String = "res://Scripts/Shaders/YoshiSwap.gdshader"

@export var yoshi_keys: PackedStringArray = PackedStringArray([
	"green","red","yellow","lightblue","pink","purple","black","white"
])

const _YOSHI_COLORS := {
	"green":      Color(0.60, 1.00, 0.60),
	"red":        Color(1.00, 0.40, 0.40),
	"yellow":     Color(1.00, 0.95, 0.40),
	"lightblue":  Color(0.50, 0.85, 1.00),
	"pink":       Color(1.00, 0.65, 0.90),
	"purple":     Color(0.75, 0.50, 1.00),
	"black":      Color(0.20, 0.20, 0.20),
	"white":      Color(0.95, 0.95, 0.95)
}

@export var force_player_on_top_unless_front: bool = true
@export var player_front_epsilon: float = 1.0   # “how much closer” counts as being in front (map px)

@export var player_front_screen_epsilon: float = 2.0  # pixels: how much lower counts as “in front”

# Depth along the camera forward (positive = in front of the player's position, negative = behind)
func _depth_along_camera(el: WorldElement) -> float:
	var p3d := get_node_or_null(pseudo3d_node)
	if p3d == null or not p3d.has_method("get_camera_forward_map"):
		return 0.0
	var cam_f: Vector2 = (p3d.call("get_camera_forward_map") as Vector2)
	var cf_len := cam_f.length()
	if cf_len > 0.00001:
		cam_f /= cf_len
	# Use the player's map position as the camera origin proxy (matches how Opponent does it)
	var pl: WorldElement = _player
	if pl == null:
		return 0.0
	var my3 := el.ReturnMapPosition()
	var pl3 := pl.ReturnMapPosition()
	return Vector2(my3.x - pl3.x, my3.z - pl3.z).dot(cam_f)

func _someone_in_front_of_player() -> bool:
	if _player == null:
		return false
	var p_depth := _depth_along_camera(_player)
	for opp in _opponents:
		if not is_instance_valid(opp):
			continue
		if opp == _player:
			continue
		var o_depth := _depth_along_camera(opp)
		# Closer to camera == “smaller” depth (because player is the origin)
		# If opponent is in front (closer by more than epsilon), return true
		if o_depth < p_depth - player_front_epsilon:
			return true
	return false

# -----------------------------------------------------------------------------
# Lifecycle from your game script:
#   Setup(_map.ReturnWorldMatrix(), map_tex_size, _player)
#   then every frame: Update(_map.ReturnWorldMatrix())
# -----------------------------------------------------------------------------

func Setup(worldMatrix: Basis, mapSize: int, player: Racer) -> void:
	_worldMatrix = worldMatrix
	_inv_world = _worldMatrix.inverse()      # NEW: cache inverse immediately
	_mapSize = mapSize
	_player = player
	_screen_cached = _screen_size()          # NEW: prime screen cache

	_worldElements.clear()
	if is_instance_valid(player): _worldElements.append(player)
	if _hazards != null and _hazards.size() > 0: _worldElements.append_array(_hazards)
	if _opponents != null and _opponents.size() > 0: _worldElements.append_array(_opponents)

	if auto_collect_world_elements:
		_collect_world_elements()

	# prime the player's screen position once
	if is_instance_valid(player):
		WorldToScreenPosition(player)

	# Defer one frame so overlay/pseudo3D are ready before we touch them
	if auto_apply_path:
		call_deferred("_apply_path_from_overlay")
		# Path is now applied → spawn
		call_deferred("SpawnOpponentsFromDefaults")

	print("World elements:", _worldElements.size())
	for we in _worldElements:
		prints("  -", we.name, "spr:", we.ReturnSpriteGraphic())
		
	_smoothed_scale.clear()

func Update(worldMatrix: Basis) -> void:
	if _is_updating: return
	_is_updating = true

	_worldMatrix = worldMatrix
	_inv_world = _worldMatrix.inverse()        # <- compute once
	_dt_cached = get_process_delta_time()      # <- compute once
	_screen_cached = _screen_size()            # <- compute once

	# Camera forward + turn rate (once)
	var p3d := get_node_or_null(pseudo3d_node)
	var cam_f_target := Vector2(0, 1)
	if p3d != null and p3d.has_method("get_camera_forward_map"):
		cam_f_target = (p3d.call("get_camera_forward_map") as Vector2)
	if cam_f_target.length() <= 0.0:
		cam_f_target = Vector2(0, 1)
	_cam_f_smooth = _exp_smooth_vec2(_cam_f_smooth, cam_f_target, _dt_cached, cam_half_life)
	_right_axis = Vector2(_cam_f_smooth.y, -_cam_f_smooth.x)

	# Turn rate (once)
	var curr_angle := atan2(_cam_f_smooth.y, _cam_f_smooth.x)
	var prev_angle := atan2(_cam_dir_prev.y, _cam_dir_prev.x)
	var dtheta := curr_angle - prev_angle
	if dtheta > PI:  dtheta -= TAU
	if dtheta < -PI: dtheta += TAU
	var turn_rate = abs(dtheta) / max(0.0001, _dt_cached)
	_turn_rate_s = _exp_smooth_scalar(_turn_rate_s, turn_rate, _dt_cached, turn_half_life)
	_cam_dir_prev = _cam_f_smooth

	# Update elements (stagger heavy work a bit; see §3)
	var batch_mod := 4  # try 3 if many sprites
	for i in range(_worldElements.size()):
		if (i % batch_mod) == (Engine.get_frames_drawn() % batch_mod):
			HandleSpriteDetail(_worldElements[i])
		WorldToScreenPosition(_worldElements[i])


	# Collisions, overlay, sorting
	if enable_player_opponent_collision:
		_resolve_player_opponent_collisions()

	# Update overlay less often to reduce churn
	if (Engine.get_frames_drawn() % 2) == 0:
		call_deferred("_notify_overlay")

	HandleYLayerSorting()
	_tick_launch_profiles(_dt_cached)
	_is_updating = false

# -----------------------------------------------------------------------------
# Overlay / Pseudo3D handshake (optional)
# -----------------------------------------------------------------------------

func _apply_path_from_overlay() -> void:
	var p3d := get_node_or_null(pseudo3d_node)
	if p3d == null:
		push_warning("SpriteHandler: pseudo3d_node not set (skipping path apply).")
		return
	var ov := get_node_or_null(path_overlay_node)
	if ov == null:
		push_warning("SpriteHandler: path_overlay_node not set (skipping path apply).")
		return

	# Pull UV points directly from the overlay
	var pts: PackedVector2Array
	if ov.has_method("get_path_points_uv_transformed"):
		pts = ov.call("get_path_points_uv_transformed")
	elif ov.has_method("get_path_points_uv"):
		pts = ov.call("get_path_points_uv")
	else:
		push_warning("SpriteHandler: overlay has no get_path_points_uv*() method.")
		return

	if pts.size() < 2:
		push_warning("SpriteHandler: overlay returned fewer than 2 path points.")
		return

	# Send points to Pseudo3D with whatever API it exposes
	if p3d.has_method("SetPathPointsUV"):
		p3d.call("SetPathPointsUV", pts)
	elif p3d.has_method("SetPathPoints"):
		p3d.call("SetPathPoints", pts)
	elif p3d.has_method("set_path_points_uv"):
		p3d.call("set_path_points_uv", pts)
	else:
		push_warning("SpriteHandler: Pseudo3D has no SetPathPoints*(UV) method; skipping.")

func _notify_overlay() -> void:
	var ov := get_node_or_null(path_overlay_node)
	if ov and ov.has_method("set_world_and_screen"):
		ov.call("set_world_and_screen", _worldMatrix, _screen_size())

# -----------------------------------------------------------------------------
# Detail, sorting, projection
# -----------------------------------------------------------------------------

func HandleSpriteDetail(target: WorldElement) -> void:
	if target == null or _player == null:
		return
	var spr := target.ReturnSpriteGraphic()
	if spr == null:
		return
	if debug_show_all:
		spr.visible = true
		return

	var s := spr as Sprite2D
	if s == null:
		return

	# --- DO NOT enable region if this sprite uses hframes/vframes (grid sheets) ---
	var uses_grid := (s.hframes > 1) or (s.vframes > 1)

	# Only use region rows for LOD when not using a grid
	if not uses_grid:
		s.region_enabled = true
	else:
		s.region_enabled = false  # <- crucial: let _set_frame_idx() control frames

	var player_pos := Vector2(_player.ReturnMapPosition().x, _player.ReturnMapPosition().z)
	var target_pos := Vector2(target.ReturnMapPosition().x, target.ReturnMapPosition().z)
	var distance: float = target_pos.distance_to(player_pos) * _mapSize

	s.visible = (distance < _showSpriteInRangeOf)
	if not s.visible:
		return

	# If this sprite uses grid frames, skip region-row LOD logic entirely.
	if uses_grid:
		return

	var detail_states := 1
	if target.has_method("ReturnTotalDetailStates"):
		detail_states = int(target.call("ReturnTotalDetailStates"))
	if detail_states <= 1:
		return

	var normalized := distance / float(_showSpriteInRangeOf)
	var exp_factor := pow(normalized, 0.75)
	var detail_level := int(clamp(exp_factor * float(detail_states), 0.0, float(detail_states - 1)))

	# --- row shift only for region-based sprites ---
	var rr := s.region_rect

	# If region_rect height isn’t initialized, derive a sane row height once.
	if rr.size.y <= 0.0 and s.texture:
		# assume full texture split into 'detail_states' vertical rows
		rr.size = Vector2(s.texture.get_width(), float(s.texture.get_height()) / float(detail_states))
		rr.position = Vector2(0, 0)
		s.region_rect = rr

	var row_h := int(s.region_rect.size.y)
	var new_y := row_h * detail_level
	rr = s.region_rect
	rr.position.y = float(new_y)
	s.region_rect = rr

func HandleYLayerSorting() -> void:
	_worldElements = _worldElements.filter(func(e): return is_instance_valid(e))

	# Sort by screen.y so lower-on-screen naturally goes on top.
	_worldElements.sort_custom(Callable(self, "SortByScreenY"))

	var base_i := 0
	for i in range(_worldElements.size()):
		var spr := _worldElements[i].ReturnSpriteGraphic()
		if spr == null: continue
		# Assign increasing z_index; later elements (lower on screen) get higher z
		if spr.z_index != base_i:
			spr.z_index = base_i
		base_i += 1

	# Player special rule:
	# "Player is on top unless there is a driver closer to the bottom of the screen."
	if force_player_on_top and is_instance_valid(_player):
		var pspr := _player.ReturnSpriteGraphic()
		if pspr != null:
			if _someone_lower_on_screen_than_player():
				# Someone is lower -> do not lift the player; natural order stands
				pass
			else:
				# No one lower -> float the player above all others by a small margin
				var want := _worldElements.size() + player_on_top_margin
				if pspr.z_index != want:
					pspr.z_index = want

	# (keep your existing refresh throttle)
	if (Engine.get_frames_drawn() % 2) != 0:
		return

func SortByScreenY(a: WorldElement, b: WorldElement) -> int:
	var aPosY: float = a.ReturnScreenPosition().y
	var bPosY: float = b.ReturnScreenPosition().y
	if aPosY < bPosY:
		return -1
	elif aPosY > bPosY:
		return 1
	else:
		return 0

func WorldToScreenPosition(worldElement: WorldElement) -> void:
	if worldElement == null or _player == null:
		return

	var spr := worldElement.ReturnSpriteGraphic()
	var mp  := worldElement.ReturnMapPosition()   # UV (0..1)
	var dt  := _dt_cached
	var id  := worldElement.get_instance_id()

	# ---- scaling (uses cached camera vectors & turn rate) ----
	if spr != null:
		var base3 := player_base_scale_abs
		var floor_abs := opponent_min_scale_abs

		if worldElement == _player:
			(spr as Node2D).scale = Vector2(base3, base3)
		else:
			var el_uv := Vector2(mp.x, mp.z)

			# --- intuitive target scale ---
			var target_scale := _scale_for_element(el_uv, base3, floor_abs)

			# --- smoothing + asymmetric rate limit you already have ---
			var sm := _smooth_scale_to(id, target_scale, dt)

			# (Optional) keep your turn-growth clamp if you like its feel:
			if turn_damp_enabled and sm > float(_smoothed_scale.get(id, sm)):
				var freeze_rad_s := deg_to_rad(turn_freeze_deg_per_s)
				var turn_norm = clamp(_turn_rate_s / max(0.0001, freeze_rad_s), 0.0, 1.0)
				var extra_clamp = growth_damp_gain * turn_norm * dt
				var allowed_up  = max(scale_max_rate_up * dt - extra_clamp, 0.0)
				var prev_scale  = float(_smoothed_scale[id])
				if sm - prev_scale > allowed_up:
					sm = prev_scale + allowed_up

			(spr as Node2D).scale = Vector2(sm, sm)


	# ---- project to screen (fast: reuse _inv_world & _screen_cached) ----
	var transformed: Vector3 = _inv_world * Vector3(mp.x, mp.z, 1.0)
	if transformed.z < 0.0:
		worldElement.SetScreenPosition(Vector2(-1000, -1000))
		if spr != null: spr.visible = false
		return

	var screen: Vector2 = Vector2(transformed.x / transformed.z, transformed.y / transformed.z)
	screen = (screen + Vector2(0.5, 0.5)) * _screen_cached

	if spr != null:
		var h := 0.0
		if "region_rect" in spr: h = spr.region_rect.size.y
		if h <= 0.0: h = 32.0
		screen.y -= (h * (spr as Node2D).scale.y) / 2.0

	if (screen.x < 0.0 or screen.y < 0.0 or
		screen.floor().x > _screen_cached.x or screen.floor().y > _screen_cached.y):
		worldElement.SetScreenPosition(Vector2(-1000, -1000))
		if spr != null: spr.visible = false
		return

	screen = screen.floor()
	worldElement.SetScreenPosition(screen)
	if spr != null:
		(spr as Node2D).global_position = screen
		spr.visible = true

# -----------------------------------------------------------------------------
# Utils
# -----------------------------------------------------------------------------

func _screen_size() -> Vector2:
	# Use viewport size; avoids dependency on a Globals singleton
	var vp := get_viewport()
	if vp:
		return vp.get_visible_rect().size
	return Vector2(640, 360)  # safe fallback

func _collect_world_elements() -> void:
	# Start with what you’ve wired explicitly
	_worldElements.clear()
	if is_instance_valid(_player): _worldElements.append(_player)
	if _hazards != null and _hazards.size() > 0: _worldElements.append_array(_hazards)
	if _opponents != null and _opponents.size() > 0: _worldElements.append_array(_opponents)

	if not auto_collect_world_elements:
		return

	var root := get_node_or_null(collect_under)
	if root == null:
		root = get_parent()  # fallback search starting here

	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is WorldElement and n != _player and not _worldElements.has(n):
			_worldElements.append(n)

func _smooth_scale_to(id: int, target: float, dt: float) -> float:
	var prev: float
	if _smoothed_scale.has(id):
		prev = float(_smoothed_scale[id])
	else:
		_smoothed_scale[id] = target
		return target

	var hl := scale_half_life
	if hl <= 0.0:
		hl = 0.0001
	var alpha := 1.0 - pow(0.5, dt / hl)
	var raw := prev + (target - prev) * alpha

	# Asymmetric rate limiting (stop "pop bigger")
	var up_cap   = max(scale_max_rate_up,   0.0001) * dt
	var down_cap = max(scale_max_rate_down, 0.0001) * dt
	var delta := raw - prev
	if delta > up_cap:
		raw = prev + up_cap
	elif delta < -down_cap:
		raw = prev - down_cap

	_smoothed_scale[id] = raw
	return raw

func _exp_smooth_scalar(prev: float, target: float, dt: float, half_life: float) -> float:
	if half_life <= 0.0:
		return target
	var alpha := 1.0 - pow(0.5, dt / half_life)
	return prev + (target - prev) * alpha

func _exp_smooth_vec2(prev: Vector2, target: Vector2, dt: float, half_life: float) -> Vector2:
	if half_life <= 0.0:
		return target.normalized() if target.length() > 0.0 else prev
	var alpha := 1.0 - pow(0.5, dt / half_life)
	var v := prev + (target - prev) * alpha
	return v.normalized() if v.length() > 0.00001 else prev

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _pair_key(a: int, b: int) -> String:
	return str(mini(a, b), "_", maxi(a, b))

func _uv_to_px(v: Vector2) -> Vector2:
	return Vector2(v.x * _mapSize, v.y * _mapSize)

func _px_to_uv(v: Vector2) -> Vector2:
	return Vector2(v.x / _mapSize, v.y / _mapSize)

func _resolve_player_opponent_collisions() -> void:
	if _player == null or _opponents == null or _opponents.size() == 0:
		return

	var p3 := _player.ReturnMapPosition()
	var p_uv := Vector2(p3.x, p3.z)
	var r_p := _get_collision_radius_uv(_player, true)

	for opp in _opponents:
		if not is_instance_valid(opp) or opp == _player:
			continue
		var o3 := opp.ReturnMapPosition()
		var o_uv := Vector2(o3.x, o3.z)
		var r_o := _get_collision_radius_uv(opp, false)
		_resolve_circle_overlap(_player, p_uv, r_p, opp, o_uv, r_o, p3.y, o3.y)

	# opponent ↔ opponent
	for i in range(_opponents.size()):
		var a = _opponents[i]
		if not is_instance_valid(a): continue
		var a3 := a.ReturnMapPosition()
		var a_uv := Vector2(a3.x, a3.z)
		var r_a := _get_collision_radius_uv(a, false)

		for j in range(i + 1, _opponents.size()):
			var b = _opponents[j]
			if not is_instance_valid(b): continue
			var b3 := b.ReturnMapPosition()
			var b_uv := Vector2(b3.x, b3.z)
			var r_b := _get_collision_radius_uv(b, false)

			_resolve_circle_overlap(a, a_uv, r_a, b, b_uv, r_b, a3.y, b3.y)

func _resolve_circle_overlap(a: WorldElement, a_uv: Vector2, a_r: float,
							 b: WorldElement, b_uv: Vector2, b_r: float,
							 a_y: float, b_y: float) -> void:
	var d_uv := b_uv - a_uv
	var dist := d_uv.length()
	var sum_r := a_r + b_r
	if dist <= 0.0:
		d_uv = Vector2(1, 0)
		dist = 0.00001

	if dist < sum_r:
		var n := d_uv / dist
		var overlap := sum_r - dist
		var push_uv := n * (overlap * 0.5 * separate_fraction)

		# cooldown check
		var key := _pair_key(a.get_instance_id(), b.get_instance_id())
		var tnow := _now()
		var last := -1000.0
		if _last_collision_time.has(key):
			last = float(_last_collision_time[key])
		if (tnow - last) < collision_cooldown_s:
			_apply_separation_uv(a, -push_uv, a_y)
			_apply_separation_uv(b,  push_uv, b_y)
			return
		_last_collision_time[key] = tnow

		# push both out
		_apply_separation_uv(a, -push_uv, a_y)
		_apply_separation_uv(b,  push_uv, b_y)

		# optional bump
		if bump_on_collision:
			var bump_dir := Vector3(n.x * bump_strength_sign, 0.0, n.y * bump_strength_sign)
			if a.has_method("SetCollisionBump"): a.call("SetCollisionBump", -bump_dir)
			if b.has_method("SetCollisionBump"): b.call("SetCollisionBump",  bump_dir)

func _apply_separation_uv(el: WorldElement, delta_uv: Vector2, y_uv: float) -> void:
	# Read current UV, convert to pixels, add delta
	var curr := el.ReturnMapPosition()
	var new_uv := Vector2(curr.x, curr.z) + delta_uv
	var new_px := _uv_to_px(new_uv)
	var y_px := y_uv * _mapSize
	el.SetMapPosition(Vector3(new_px.x, y_px, new_px.y))

func _scale_for_element(el_uv: Vector2, base3: float, floor_abs: float) -> float:
	# Perspective ratio (no tuning): scale = base * (z_player / z_elem)
	if scale_model == 0:
		var p3 := _player.ReturnMapPosition()
		var p_uv := Vector2(p3.x, p3.z)
		var Hp := _inv_world * Vector3(p_uv.x, p_uv.y, 1.0)
		var He := _inv_world * Vector3(el_uv.x, el_uv.y, 1.0)
		# if either behind/cull, just clamp to floor to be safe
		if Hp.z <= 0.0 or He.z <= 0.0:
			return floor_abs
		var s := base3 * (Hp.z / He.z)
		return clamp(s, floor_abs, base3)

	# Distance falloff (single intuitive knob): base * R/(R + d)
	# R is the distance at which size is ~0.5*base.
	else:
		var p3 := _player.ReturnMapPosition()
		var p_uv := Vector2(p3.x, p3.z)
		var d := (el_uv - p_uv).length()   # UV units
		var R = max(ref_distance_uv, 0.0001)
		var s = base3 * (R / (R + d))
		return clamp(s, floor_abs, base3)

func _get_collision_radius_uv(el: WorldElement, is_player: bool) -> float:
	# Mode 2: ask the element (per-entity)
	if collision_radius_mode == 2:
		if el.has_method("ReturnCollisionRadiusUV"):
			var r := float(el.call("ReturnCollisionRadiusUV"))
			return max(0.0001, r) * radius_scale_global

	# Mode 1: derive from sprite height in pixels -> UV
	if collision_radius_mode == 1:
		var spr := el.ReturnSpriteGraphic()
		if spr != null:
			var s2 := spr as Sprite2D
			var h_px := 0.0
			if "region_rect" in s2 and s2.region_rect.size.y > 0.0:
				h_px = s2.region_rect.size.y
			else:
				h_px = 32.0
			# use current on-screen scale so radius matches visual size
			var sc := (s2 as Node2D).scale.y
			var h_visual_px := h_px * sc
			var r_px := (h_visual_px * radius_from_sprite_factor)
			var r_uv := r_px / float(_mapSize)
			r_uv = max(min_radius_uv_auto, r_uv)
			return r_uv * radius_scale_global

	# Mode 0 (fallback): use fixed exports
	return (player_radius_uv if is_player else opponent_radius_uv) * radius_scale_global

func _get_path_points_uv() -> PackedVector2Array:
	var pts: PackedVector2Array
	var ov := get_node_or_null(path_overlay_node)
	if ov != null:
		if ov.has_method("get_path_points_uv_transformed"):
			pts = ov.call("get_path_points_uv_transformed")
		elif ov.has_method("get_path_points_uv"):
			pts = ov.call("get_path_points_uv")

	if pts == null or pts.size() == 0:
		pts = PackedVector2Array()

	return _unique_loop_points(pts)

func _is_far_enough(uv: Vector2, used: Array, min_sep_uv: float) -> bool:
	for u in used:
		var d = (uv - u).length()
		if d < min_sep_uv:
			return false
	return true

func SpawnOpponentsOnPath() -> void:
	var pts := _get_path_points_uv()
	if pts.size() == 0:
		push_warning("SpawnOpponentsOnPath: no path points available.")
		return
	if _opponents == null or _opponents.size() == 0:
		return

	# start with the player’s current UV to avoid spawning on top of them
	var used_uvs: Array = []
	if is_instance_valid(_player):
		var p3 := _player.ReturnMapPosition()
		used_uvs.append(Vector2(p3.x, p3.z))

	# derive a safe min separation from radius system (use the larger of derived and export)
	var base_sep := spawn_min_sep_uv
	if collision_radius_mode == 1 or collision_radius_mode == 2:
		var r_p := _get_collision_radius_uv(_player, true)
		base_sep = max(base_sep, r_p * 2.5)

	var jitter_uv := spawn_jitter_px / float(max(1, _mapSize))

	var idx := spawn_start_offset % pts.size()
	for opp in _opponents:
		if not is_instance_valid(opp):
			continue

		# scan forward until we find an available point
		var tries := pts.size()
		var placed := false
		while tries > 0 and not placed:
			var uv := pts[idx]
			# tiny jitter to avoid exact overlaps
			var jx := (randf() * 2.0 - 1.0) * jitter_uv
			var jy := (randf() * 2.0 - 1.0) * jitter_uv
			var uvj := Vector2(clamp(uv.x + jx, 0.0, 1.0), clamp(uv.y + jy, 0.0, 1.0))

			# expand sep by opponent radius if available
			var sep := base_sep
			if collision_radius_mode == 1 or collision_radius_mode == 2:
				var r_o := _get_collision_radius_uv(opp, false)
				sep = max(sep, r_o * 2.0)

			if _is_far_enough(uvj, used_uvs, sep):
				_place_world_element_uv(opp, uvj)
				used_uvs.append(uvj)
				placed = true
			else:
				# advance and try another point
				idx = (idx + 1) % pts.size()
				tries -= 1

		# stride forward for the next opponent even if we had to scan
		idx = (idx + max(1, spawn_stride)) % pts.size()

# ---------- PATH READ (prefer default Pseudo3D path) ----------

func _get_default_path_points_uv() -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()

	var p3d := get_node_or_null(pseudo3d_node)
	if p3d != null:
		if p3d.has_method("GetPathPointsUV"):
			pts = p3d.call("GetPathPointsUV")
		elif p3d.has_method("get_path_points_uv"):
			pts = p3d.call("get_path_points_uv")
		elif p3d.has_method("ReturnPathPointsUV"):
			pts = p3d.call("ReturnPathPointsUV")

	if pts == null or pts.size() == 0:
		var ov := get_node_or_null(path_overlay_node)
		if ov != null:
			if ov.has_method("get_path_points_uv_transformed"):
				pts = ov.call("get_path_points_uv_transformed")
			elif ov.has_method("get_path_points_uv"):
				pts = ov.call("get_path_points_uv")

	if pts == null:
		pts = PackedVector2Array()

	return _unique_loop_points(pts)

# ---------- PLACE/ORIENT HELPERS ----------

func _place_world_element_uv(el: WorldElement, uv: Vector2) -> void:
	# Keep current Y (already in pixels in your game), only move on map plane (x,z)
	var curr := el.ReturnMapPosition()        # Vector3 pixels
	var y_px := curr.y                        # keep height as-is
	var px := _uv_to_px(uv)                   # Vector2 pixels from 0..1 UV
	el.SetMapPosition(Vector3(px.x, y_px, px.y))

func _face_along_path_if_possible(el: WorldElement, pts: PackedVector2Array, idx: int) -> void:
	var n := pts.size()
	if n < 2:
		return
	var a := pts[idx]
	var b := pts[(idx + 1) % n]
	var tan := (b - a)
	if tan.length() <= 0.000001:
		return
	# If your racer exposes a heading setter in map space, call it:
	if el.has_method("SetHeadingFromMapTangent"):
		el.call("SetHeadingFromMapTangent", tan.normalized())
	elif el.has_method("set_heading_from_map_tangent"):
		el.call("set_heading_from_map_tangent", tan.normalized())
	# Otherwise we leave orientation to your usual update code.


# ---------- INDEX/AVAILABILITY ----------

func _nearest_free_index(pts: PackedVector2Array, start_idx: int, used: Dictionary, min_gap: int) -> int:
	# Scan outward from start_idx, skipping used indices and enforcing integer stride gap
	# used is a Dictionary[int] = true
	var n := pts.size()
	if n == 0:
		return -1

	var i := start_idx
	var tries := n
	while tries > 0:
		if not used.has(i):
			return i
		i = (i + max(1, min_gap)) % n
		tries -= 1
	return -1

func _index_of_closest_point(pts: PackedVector2Array, uv: Vector2) -> int:
	var best_i := -1
	var best_d := 1e9
	for i in range(pts.size()):
		var d := pts[i].distance_to(uv)
		if d < best_d:
			best_d = d
			best_i = i
	return best_i


# ---------- PUBLIC: SPAWN OPPONENTS ON DEFAULT PATH ----------

@export var spawn_stride_points : int = 6      # gap in path indices between AIs
@export var spawn_from_player   : bool = true  # start near the player’s current position
@export var spawn_start_index   : int = 0      # start here if not using player anchor

@export var spawn_block_neighborhood : int = 1   # also mark ±this many indices as used

func SpawnOpponentsOnDefaultPath() -> void:
	# hard reset any prior launch profiles & markers
	_launch_profiles.clear()
	if spawn_debug_draw_markers:
		var ov := get_node_or_null(path_overlay_node)
		if ov != null and ov.has_method("clear_debug_markers"):
			ov.call("clear_debug_markers")

	# fresh path read (deduped closing point)
	var pts := _get_default_path_points_uv()
	var N := pts.size()
	if N == 0:
		call_deferred("SpawnOpponentsOnDefaultPath")
		return
	if _opponents == null or _opponents.size() == 0:
		return

	# anchor near player or explicit index
	var anchor_idx := 0
	if spawn_from_player and is_instance_valid(_player):
		var p3 := _player.ReturnMapPosition()
		var p_uv := Vector2(p3.x / float(_mapSize), p3.z / float(_mapSize))
		anchor_idx = _index_of_closest_point(pts, p_uv)
	else:
		anchor_idx = clamp(spawn_start_index, 0, max(0, N - 1))

	# evenly spaced desired indices
	var M := _opponents.size()
	var desired: Array = []
	for k in range(M):
		var i := int(floor(float(k) * float(N) / float(M) + 0.5))
		var idx := (anchor_idx + i) % N
		desired.append(idx)

	# ensure none equals player's anchor; nudge +1 if needed
	for j in range(desired.size()):
		if desired[j] == anchor_idx:
			desired[j] = (desired[j] + 1) % N

	# boolean flags for used indices (fresh each run)
	var used_flags: Array = []
	used_flags.resize(N)
	for i2 in range(N):
		used_flags[i2] = false

	# reserve anchor neighborhood once
	_flag_neighborhood(used_flags, anchor_idx, N, spawn_block_neighborhood)

	# place each opponent with guaranteed uniqueness
	for ai_i in range(M):
		var opp := _opponents[ai_i]
		if not is_instance_valid(opp):
			continue

		var want = desired[ai_i]

		# find next free index (scans step=1)
		var idx_free := _next_free_index(used_flags, want, N)
		if idx_free == -1:
			# fully packed; fall back to want (worst-case)
			idx_free = want

		# mark index + neighborhood as used
		_flag_neighborhood(used_flags, idx_free, N, spawn_block_neighborhood)

		# place & orient
		var uv := pts[idx_free]
		if opp != null and opp.has_method("ApplySpawnFromPathIndex"):
			opp.call("ApplySpawnFromPathIndex", idx_free, 0.0)  # pass lane offset if you have one
		else:
			# fallback (if some AI isn’t using Opponent.gd):
			_place_world_element_uv(opp, uv)
			
		_face_along_path_if_possible(opp, pts, idx_free)

		# <<< RIGHT HERE is the safe place >>>
		var key := yoshi_keys[ai_i % yoshi_keys.size()]
		_attach_yoshi_shader(opp, key)		

		# debug name (no ternary)
		var name_str := ""
		if opp is Node and opp.has_method("get_name"):
			name_str = str(opp.name)
		else:
			name_str = "opp_" + str(opp.get_instance_id())

		_spawn_dbg_print("placed " + name_str + " at idx=" + str(idx_free) + " uv=" + str(uv))
		_spawn_dbg_marker(uv, name_str)

		# seed fresh launch profile along tangent
		var a := pts[idx_free]
		var b := pts[(idx_free + 1) % N]
		var tan := (b - a)
		var fwd := Vector3(tan.x, 0.0, tan.y).normalized()
		var target := randf_range(launch_min_target_speed, launch_max_target_speed)
		var accel  := randf_range(launch_min_accel_ps,     launch_max_accel_ps)
		_launch_profiles[opp.get_instance_id()] = {
			"target": target, "accel": accel, "dir": fwd
		}
		_spawn_dbg_print("launch " + name_str + " target=" + str(target) + " accel=" + str(accel))

	# summary (fresh only)
	_spawn_dbg_print("path_pts=" + str(N))
	_spawn_dbg_print("anchor_idx=" + str(anchor_idx))
	_spawn_dbg_print("even_spread_indices=" + str(desired))
	_spawn_dbg_print("opponent_count=" + str(M))

func _flag_neighborhood(flags: Array, center: int, N: int, radius: int) -> void:
	var r = max(0, radius)
	for k in range(center - r, center + r + 1):
		var i := k
		while i < 0:
			i += N
		i = i % N
		flags[i] = true

func _next_free_index(flags: Array, start_idx: int, N: int) -> int:
	var i := start_idx % N
	for _k in range(N):
		if not flags[i]:
			return i
		i = (i + 1) % N
	return -1

func _gcd(a: int, b: int) -> int:
	a = abs(a)
	b = abs(b)
	while b != 0:
		var t := b
		b = a % t
		a = t
	return max(1, a)

func _mark_used_with_neighborhood(used: Dictionary, center: int, N: int, radius: int) -> void:
	var r = max(0, radius)
	for k in range(center - r, center + r + 1):
		var i := k
		# wrap around [0, N)
		while i < 0:
			i += N
		i = i % N
		used[i] = true

func _current_speed_of(el: WorldElement) -> float:
	# Prefer a direct speed getter if available
	if el.has_method("ReturnMovementSpeed"):
		var ms_var: Variant = el.call("ReturnMovementSpeed")
		# If it’s numeric, return as float; otherwise fall through
		if typeof(ms_var) == TYPE_FLOAT or typeof(ms_var) == TYPE_INT:
			return float(ms_var)

	# Fallback to velocity length if available
	if el.has_method("ReturnVelocity"):
		var vel_var: Variant = el.call("ReturnVelocity")
		if vel_var is Vector3:
			var v3: Vector3 = vel_var
			return v3.length()

	return 0.0

func _tick_launch_profiles(dt: float) -> void:
	if _launch_profiles.is_empty():
		return
	var to_remove: Array = []
	for id in _launch_profiles.keys():
		var data = _launch_profiles[id]
		var el := instance_from_id(id)
		if el == null or not is_instance_valid(el):
			to_remove.append(id)
			continue

		var target  := float(data["target"])
		var accel   := float(data["accel"])
		var fwd     := data["dir"] as Vector3

		var curr_speed := _current_speed_of(el)

		if curr_speed >= target:
			to_remove.append(id)
			continue

		# apply forward impulse scaled by accel and dt
		var impulse := fwd * (accel * dt * launch_bump_gain)
		if el.has_method("SetCollisionBump"):
			el.call("SetCollisionBump", impulse)
		else:
			# ultra-safe fallback: tiny positional nudge if no bump method
			var curr3 = el.ReturnMapPosition()
			el.SetMapPosition(curr3 + impulse)

	for id in to_remove:
		_launch_profiles.erase(id)

func _spawn_dbg_print(msg: String) -> void:
	if spawn_debug:
		print("[Spawn]", msg)

func _spawn_dbg_marker(uv: Vector2, label: String) -> void:
	if not spawn_debug_draw_markers:
		return
	var ov := get_node_or_null(path_overlay_node)
	if ov == null:
		return
	# PathOverlay2D.gd already has add_debug_marker_uv(uv)
	if ov.has_method("add_debug_marker_uv"):
		ov.call("add_debug_marker_uv", uv)
		# optional: if your overlay supports colored markers, call a color-aware variant here

func _unique_loop_points(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() >= 2:
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[pts.size() - 1]
		if a.is_equal_approx(b):
			var out := PackedVector2Array()
			for i in range(pts.size() - 1):
				out.append(pts[i])
			return out
	return pts

func _attach_yoshi_shader(opp: WorldElement, color_key: String) -> void:
	if opp == null:
		return
	var spr := opp.ReturnSpriteGraphic()
	if spr == null:
		return

	var sh := load(yoshi_shader_path)
	if sh == null:
		push_warning("Yoshi shader not found: " + yoshi_shader_path)
		return

	var mat := ShaderMaterial.new()
	mat.shader = sh

	var col := Color(0.60, 1.00, 0.60)
	if _YOSHI_COLORS.has(color_key):
		col = _YOSHI_COLORS[color_key]
	mat.set_shader_parameter("target_color", col)

	# Defaults tuned for “green” source paint; tweak if your sheet differs
	mat.set_shader_parameter("src_hue", 0.33)
	mat.set_shader_parameter("hue_tol", 0.12)
	mat.set_shader_parameter("sat_min", 0.25)
	mat.set_shader_parameter("val_min", 0.12)
	mat.set_shader_parameter("edge_soft", 0.20)
	mat.set_shader_parameter("sat_boost", 1.00)
	mat.set_shader_parameter("val_mix", 0.50)

	# Apply to Sprite2D (grid frames, not regions)
	if spr is Sprite2D:
		var s := spr as Sprite2D
		s.region_enabled = false
		s.material = mat
	elif "material" in spr:
		spr.material = mat

func _someone_lower_on_screen_than_player() -> bool:
	if _player == null:
		return false

	var p_pos := _player.ReturnScreenPosition()
	# ignore when player is offscreen
	if p_pos.y < 0.0:
		return false

	for we in _worldElements:
		if not is_instance_valid(we) or we == _player:
			continue
		var sp := we.ReturnScreenPosition()
		# consider only visible-ish sprites
		if sp.y < 0.0:
			continue
		# If any opponent is lower (larger y) than player by epsilon → they should be on top
		if sp.y > p_pos.y + player_front_screen_epsilon:
			return true
	return false

func SpawnOpponentsFromDefaults() -> void:
	# reset any prior launch profiles & markers
	_launch_profiles.clear()
	if spawn_debug_draw_markers:
		var ov := get_node_or_null(path_overlay_node)
		if ov != null and ov.has_method("clear_debug_markers"):
			ov.call("clear_debug_markers")

	# we still read the live path to get forward tangents for launch
	var pts := _get_default_path_points_uv()
	var N := pts.size()
	if N == 0:
		# path not ready; try again next frame
		call_deferred("SpawnOpponentsFromDefaults")
		return
	if _opponents == null or _opponents.size() == 0:
		return

	for i in range(_opponents.size()):
		var opp := _opponents[i]
		if not is_instance_valid(opp):
			continue

		# pick which DEFAULT point to use for this opponent
		var di := i
		if opp.has_method("DefaultCount"):
			var cnt := int(opp.call("DefaultCount"))
			if cnt > 0:
				di = i % cnt

		# place at DEFAULT_POINTS[di] (exact pixels) and compute _s_px from the actual path
		if opp.has_method("ApplySpawnFromDefaultIndex"):
			opp.call("ApplySpawnFromDefaultIndex", di, 0.0)
		else:
			# Fallback: if the Opponent script hasn't been updated yet, use its old index-based spawner.
			# We project to the nearest path point to avoid crashes; it won't be exact defaults without the new method.
			var idx_fallback = i % max(1, N)
			if opp.has_method("ApplySpawnFromPathIndex"):
				opp.call("ApplySpawnFromPathIndex", idx_fallback, 0.0)

		# compute current UV (from placed pixel position) ONCE so it's in scope for both debug and launch
		var scale_px := float(_mapSize)
		var pos3: Vector3 = opp.ReturnMapPosition()
		var uv := Vector2(pos3.x / scale_px, pos3.z / scale_px)

		# debug marker at the exact default UV we just used
		if spawn_debug_draw_markers:
			_spawn_dbg_marker(uv, "opp_" + str(i))

		# seed a launch profile along the local path tangent nearest to our UV
		var idx := _index_of_closest_point(pts, uv)
		if idx < 0:
			idx = 0
		var a := pts[idx]
		var b := pts[(idx + 1) % N]
		var tan := (b - a)
		var fwd := Vector3(tan.x, 0.0, tan.y).normalized()
		var target := randf_range(launch_min_target_speed, launch_max_target_speed)
		var accel := randf_range(launch_min_accel_ps,     launch_max_accel_ps)
		_launch_profiles[opp.get_instance_id()] = { "target": target, "accel": accel, "dir": fwd }

		# optional debug output
		_spawn_dbg_print("spawned opp_" + str(i) + " at default UV=" + str(uv) + " (idx≈" + str(idx) + ")")

	# summary
	_spawn_dbg_print("opponent_count=" + str(_opponents.size()))
