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
@export var player_radius_uv   : float = 0.035   # in UV units (0..1 across the map)
@export var opponent_radius_uv : float = 0.035   # in UV units (per opponent)
@export var separate_fraction  : float = 1.0     # 1.0 = full separation this frame
@export var bump_on_collision  : bool = true
@export var bump_strength_sign := 1.0            # 1.0 forward along normal, -1.0 opposite

# internal helpers
var _last_collision_time := {}   # id_pair_string -> float
@export var collision_cooldown_s := 0.12

# -----------------------------------------------------------------------------
# Lifecycle from your game script:
#   Setup(_map.ReturnWorldMatrix(), map_tex_size, _player)
#   then every frame: Update(_map.ReturnWorldMatrix())
# -----------------------------------------------------------------------------

func Setup(worldMatrix: Basis, mapSize: int, player: Racer) -> void:
	_worldMatrix = worldMatrix
	_mapSize = mapSize
	_player = player

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
		
	print("World elements:", _worldElements.size())
	for we in _worldElements:
		prints("  -", we.name, "spr:", we.ReturnSpriteGraphic())
		
	_smoothed_scale.clear()

func Update(worldMatrix: Basis) -> void:
	if _is_updating:
		return
	_is_updating = true

	_worldMatrix = worldMatrix

	for we in _worldElements:
		if not is_instance_valid(we):
			continue
		HandleSpriteDetail(we)
		WorldToScreenPosition(we)

	# Resolve player↔opponent collisions in map space
	if enable_player_opponent_collision:
		_resolve_player_opponent_collisions()

	# Defer overlay update to avoid recursion
	call_deferred("_notify_overlay")

	HandleYLayerSorting()
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
	s.region_enabled = true       # safe now

	var player_pos := Vector2(_player.ReturnMapPosition().x, _player.ReturnMapPosition().z)
	var target_pos := Vector2(target.ReturnMapPosition().x, target.ReturnMapPosition().z)
	var distance: float = target_pos.distance_to(player_pos) * _mapSize

	s.visible = (distance < _showSpriteInRangeOf)
	if not s.visible:
		return

	var detail_states := 1
	if target.has_method("ReturnTotalDetailStates"):
		detail_states = int(target.call("ReturnTotalDetailStates"))
	if detail_states <= 1:
		return

	var normalized := distance / float(_showSpriteInRangeOf)
	var exp_factor := pow(normalized, 0.75)
	var detail_level := int(clamp(exp_factor * float(detail_states), 0.0, float(detail_states - 1)))

	# shift the region vertically by rows
	var row_h := int(s.region_rect.size.y)
	var new_y := row_h * detail_level
	var rr := s.region_rect
	rr.position.y = float(new_y)
	s.region_rect = rr

func HandleYLayerSorting() -> void:
	_worldElements = _worldElements.filter(func(e): return is_instance_valid(e))
	_worldElements.sort_custom(Callable(self, "SortByScreenY"))

	# Apply z_index in sorted order
	for i in range(_worldElements.size()):
		var spr := _worldElements[i].ReturnSpriteGraphic()
		if spr != null:
			spr.z_index = i

	# Force the player to the very top if requested
	if force_player_on_top and is_instance_valid(_player):
		var pspr := _player.ReturnSpriteGraphic()
		if pspr != null:
			pspr.z_index = _worldElements.size() + player_on_top_margin

func SortByScreenY(a: WorldElement, b: WorldElement) -> int:
	var aPosY: float = a.ReturnScreenPosition().y
	var bPosY: float = b.ReturnScreenPosition().y
	if aPosY < bPosY:
		return -1
	elif aPosY > bPosY:
		return 1
	else:
		return 0

func WorldToScreenPosition(worldElement : WorldElement) -> void:
	if worldElement == null or _player == null:
		return

	var spr := worldElement.ReturnSpriteGraphic()
	var mp  := worldElement.ReturnMapPosition()   # UV (0..1)
	var dt  := get_process_delta_time()
	var id  := worldElement.get_instance_id()

	# ---- camera forward (smoothed) ----
	var p3d := get_node_or_null(pseudo3d_node)
	var cam_f_target := Vector2(0, 1)
	if p3d != null and p3d.has_method("get_camera_forward_map"):
		cam_f_target = (p3d.call("get_camera_forward_map") as Vector2)
	if cam_f_target.length() <= 0.0:
		cam_f_target = Vector2(0, 1)
	_cam_f_smooth = _exp_smooth_vec2(_cam_f_smooth, cam_f_target, dt, cam_half_life)

	# ---- scale: player fixed, opponent depth-based with turn damping ----
	if spr != null:
		var base3 := player_base_scale_abs
		var floor_abs := opponent_min_scale_abs

		if worldElement == _player:
			(spr as Node2D).scale = Vector2(base3, base3)
		else:
			# relative vector in map space
			var pl_uv := Vector2(_player.ReturnMapPosition().x, _player.ReturnMapPosition().z)
			var el_uv := Vector2(mp.x, mp.z)
			var rel   := el_uv - pl_uv

			# camera depth & lateral
			var depth_raw   := rel.dot(_cam_f_smooth)
			var right_axis  := Vector2(_cam_f_smooth.y, -_cam_f_smooth.x)
			var lateral_abs = abs(rel.dot(right_axis))

			# angle weight: reduce depth influence when mostly lateral (corners)
			var depth_abs = abs(depth_raw)
			var denom = depth_abs + lateral_abs + 0.0001
			var ratio = depth_abs / denom                      # ~cos(theta)
			var angle_w := pow(ratio, angle_power)
			if angle_w < min_angle_weight:
				angle_w = min_angle_weight

			# effective absolute distance (weighted)
			var d_abs = depth_abs * angle_w

			# smooth the distance itself to avoid spikes
			if _d_abs_smooth.has(id):
				d_abs = _exp_smooth_scalar(float(_d_abs_smooth[id]), d_abs, dt, depth_half_life)
			_d_abs_smooth[id] = d_abs

			# DEAD-ZONE: keep full size until clearly separated
			var d_eff = d_abs - shrink_deadzone_abs
			if d_eff < 0.0:
				d_eff = 0.0

			# smooth shrink curve (never > 1.0)
			var k := depth_gain
			if k <= 0.0:
				k = 0.0001
			var s_depth = 1.0 / (1.0 + k * d_eff)
			if s_depth > 1.0:
				s_depth = 1.0

			# target absolute scale
			var target_scale = base3 * s_depth
			if target_scale < floor_abs:
				target_scale = floor_abs
			if target_scale > base3:
				target_scale = base3

			# temporal smoothing + rate limit to avoid pops
			var sm := _smooth_scale_to(id, target_scale, dt)
			if sm < floor_abs: sm = floor_abs
			if sm > base3:     sm = base3
			(spr as Node2D).scale = Vector2(sm, sm)

	# ---- project to screen (unchanged) ----
	var transformed : Vector3 = _worldMatrix.inverse() * Vector3(mp.x, mp.z, 1.0)
	if transformed.z < 0.0:
		worldElement.SetScreenPosition(Vector2(-1000, -1000))
		if spr != null: spr.visible = false
		return

	var screen : Vector2 = Vector2(transformed.x / transformed.z, transformed.y / transformed.z)
	screen = (screen + Vector2(0.5, 0.5)) * _screen_size()

	if spr != null:
		var h := 0.0
		if "region_rect" in spr: h = spr.region_rect.size.y
		if h <= 0.0: h = 32.0
		screen.y -= (h * (spr as Node2D).scale.y) / 2.0

	if (screen.floor().x > _screen_size().x or screen.x < 0.0 or
		screen.floor().y > _screen_size().y or screen.y < 0.0):
		worldElement.SetScreenPosition(Vector2(-1000, -1000))
		if spr != null: spr.visible = false
		return

	worldElement.SetScreenPosition(screen.floor())
	if spr != null:
		(spr as Node2D).global_position = screen.floor()
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

	# Exponential smoothing with half-life: alpha = 1 - 0.5^(dt/half_life)
	var hl := scale_half_life
	if hl <= 0.0:
		hl = 0.0001
	var alpha := 1.0 - pow(0.5, dt / hl)

	var raw := prev + (target - prev) * alpha

	# Rate limit so big jumps are clamped per frame
	var max_step := scale_max_rate * dt
	var delta := raw - prev
	if delta >  max_step:
		raw = prev + max_step
	elif delta < -max_step:
		raw = prev - max_step

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

	# --- Player vs opponents (your existing code) ---
	var p3 := _player.ReturnMapPosition()
	var p_uv := Vector2(p3.x, p3.z)
	var r_p = max(0.0001, player_radius_uv)

	for opp in _opponents:
		if not is_instance_valid(opp) or opp == _player:
			continue
		var o3 := opp.ReturnMapPosition()
		var o_uv := Vector2(o3.x, o3.z)
		_resolve_circle_overlap(_player, p_uv, r_p, opp, o_uv, opponent_radius_uv, p3.y, o3.y)

	# --- Opponent vs opponent (new) ---
	for i in range(_opponents.size()):
		var a = _opponents[i]
		if not is_instance_valid(a): continue
		var a3 := a.ReturnMapPosition()
		var a_uv := Vector2(a3.x, a3.z)

		for j in range(i + 1, _opponents.size()):
			var b = _opponents[j]
			if not is_instance_valid(b): continue
			var b3 := b.ReturnMapPosition()
			var b_uv := Vector2(b3.x, b3.z)

			_resolve_circle_overlap(a, a_uv, opponent_radius_uv, b, b_uv, opponent_radius_uv, a3.y, b3.y)


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
