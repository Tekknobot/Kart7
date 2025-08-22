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

	# Defer overlay notification to avoid recursion during Update
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

	for i in range(_worldElements.size()):
		var spr := _worldElements[i].ReturnSpriteGraphic()
		if spr != null:   # only if there’s a valid sprite
			spr.z_index = i

func SortByScreenY(a: WorldElement, b: WorldElement) -> int:
	var aPosY: float = a.ReturnScreenPosition().y
	var bPosY: float = b.ReturnScreenPosition().y
	if aPosY < bPosY:
		return -1
	elif aPosY > bPosY:
		return 1
	else:
		return 0

func WorldToScreenPosition(worldElement : WorldElement):
	if worldElement == null or _player == null:
		return

	var spr := worldElement.ReturnSpriteGraphic()
	var mp := worldElement.ReturnMapPosition()  # normalized UV (0..1)

	# ---- depth-based SCALE first ----
	var p3d := get_node_or_null(pseudo3d_node)
	if spr != null:
		var cam_f := Vector2(0, 1)
		if p3d != null and p3d.has_method("get_camera_forward_map"):
			cam_f = (p3d.call("get_camera_forward_map") as Vector2).normalized()

		var pl_uv := Vector2(_player.ReturnMapPosition().x, _player.ReturnMapPosition().z)
		var el_uv := Vector2(mp.x, mp.z)

		# Flip sign if you want near = larger
		var forward_dot := (el_uv - pl_uv).dot(cam_f)
		if invert_depth_scale:
			forward_dot = -forward_dot

		var d = max(forward_dot, 0.0)

		var s: float = 1.0
		if p3d != null and p3d.has_method("depth_scale"):
			# reuse your Pseudo3D curve but with our 'd'
			# (depth_scale clamps internally)
			s = float(p3d.call("depth_scale", d))
		else:
			# fallback curve
			var size_k := 0.9
			var size_min := 0.35
			var size_max := 2.0
			s = clamp(size_k / (size_k + d), size_min, size_max)

		spr.scale = Vector2(s, s)

	# ---- project to screen ----
	var transformed : Vector3 = _worldMatrix.inverse() * Vector3(mp.x, mp.z, 1.0)
	if transformed.z < 0.0:
		worldElement.SetScreenPosition(Vector2(-1000, -1000))
		if spr != null: spr.visible = false
		return

	var screen : Vector2 = Vector2(transformed.x / transformed.z, transformed.y / transformed.z)
	screen = (screen + Vector2(0.5, 0.5)) * _screen_size()

	# foot anchor (after scale)
	if spr != null:
		var h = spr.region_rect.size.y
		if h <= 0.0: h = 32.0
		screen.y -= (h * spr.scale.y) / 2.0

	# cull
	if (screen.floor().x > _screen_size().x or screen.x < 0.0 or screen.floor().y > _screen_size().y or screen.y < 0.0):
		worldElement.SetScreenPosition(Vector2(-1000, -1000))
		if spr != null: spr.visible = false
		return

	worldElement.SetScreenPosition(screen.floor())
	if spr != null:
		spr.global_position = screen.floor()
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
