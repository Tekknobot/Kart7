extends Node2D
@export var _map : Node2D
@export var _collision : Node
@export var _player : Racer
@export var _spriteHandler : Node2D
@export var _animationHandler : Node
@export var _backgroundElements : Node2D
var _player_freeze_frames := 0  # frames to skip calling _player.Update after spawn

func _uniq_path_points_uv(overlay: Node) -> Array:
	# Returns Array[Vector2] of UVs with the closing duplicate removed.
	var out: Array = []
	if overlay == null or not overlay.has_method("get_path_points_uv"):
		return out
	var uv_all: PackedVector2Array = overlay.call("get_path_points_uv")
	if uv_all.size() == 0:
		return out

	var eps := 1.0 / 4096.0
	var n := uv_all.size()
	# If closed (last ~= first), drop the last one
	if n >= 2 and uv_all[0].distance_to(uv_all[n - 1]) <= eps:
		n -= 1
	for i in range(n):
		out.append(uv_all[i])
	return out

func _spawn_player_at_path_index(start_index: int) -> void:
	var overlay := _map.get_node_or_null(_map.path_overlay_node)
	if overlay == null:
		return
	var uv_list := _uniq_path_points_uv(overlay)
	if uv_list.size() < 2:
		return

	# clamp start index safely
	if start_index < 0:
		start_index = 0
	if start_index >= uv_list.size():
		start_index = uv_list.size() - 1

	var uv0: Vector2 = uv_list[start_index]
	var uv1: Vector2 = uv_list[(start_index + 1) % uv_list.size()]

	# Match Opponent.gd convention: flip UV.y once
	uv0.y = 1.0 - uv0.y
	uv1.y = 1.0 - uv1.y

	# Convert to map pixels (assumes square; if not, use width/height separately)
	var tex_w := float(_map.texture.get_size().x)
	var p0_px := uv0 * tex_w
	var p1_px := uv1 * tex_w

	# Place player exactly at p0, keep current Y
	var py := _player.ReturnMapPosition().y
	_player.SetMapPosition(Vector3(p0_px.x, py, p0_px.y))

	# Zero motion so they don't instantly step to the next vertex
	if _player.has_method("SetVelocity"):
		_player.call("SetVelocity", Vector3.ZERO)
	if _player.has_method("SetMovementSpeed"):
		_player.call("SetMovementSpeed", 0.0)

	# Freeze the manual Update() call for a couple of frames
	_player_freeze_frames = 2

	# Aim the map/camera along the first segment (p0 -> p1)
	var dir := p1_px - p0_px
	if dir.length() > 0.0001:
		dir = dir.normalized()
		var yaw := atan2(dir.x, dir.y)  # (x,z) forward = (sin(yaw), cos(yaw))
		if _map.has_method("SetYaw"):
			_map.call("SetYaw", yaw)

func _ready():
	_map.Setup(Globals.screenSize, _player)
	_collision.Setup()
	_player.Setup(_map.texture.get_size().x)
	_spriteHandler.Setup(_map.ReturnWorldMatrix(), _map.texture.get_size().x, _player)
	_animationHandler.Setup(_player)

	call_deferred("_push_path_points_once")
	call_deferred("_spawn_player_at_path_index", 0)  # 0 = very first unique point


func _spawn_player_at_first_path_point() -> void:
	var overlay := _map.get_node_or_null(_map.path_overlay_node)
	if overlay == null or not overlay.has_method("get_path_points_uv"):
		return
	var uv_all: PackedVector2Array = overlay.call("get_path_points_uv")
	if uv_all.size() < 2:
		return

	# 1) Drop the duplicate closing point if present (first ≈ last)
	var uv: Array = []
	var n := uv_all.size()
	var eps := 1.0 / 4096.0
	var first := uv_all[0]
	var last := uv_all[n - 1]
	if first.distance_to(last) <= eps:
		n -= 1  # ignore last
	for i in range(n):
		uv.append(uv_all[i])

	if uv.size() < 2:
		return

	# 2) First segment (unique)
	var uv0: Vector2 = uv[0]
	var uv1: Vector2 = uv[1]

	# Match Opponent.gd’s convention: flip UV.y once
	uv0.y = 1.0 - uv0.y
	uv1.y = 1.0 - uv1.y

	# 3) Convert to map pixels (assumes square track; use tex_h if not)
	var tex_w := float(_map.texture.get_size().x)
	var p0_px := uv0 * tex_w
	var p1_px := uv1 * tex_w

	# 4) Place player exactly at p0, keep current Y
	var py := _player.ReturnMapPosition().y
	_player.SetMapPosition(Vector3(p0_px.x, py, p0_px.y))

	# 5) Hard-stop any initial motion so it doesn't “jump” to p1 on frame 1
	if _player.has_method("SetVelocity"):
		_player.call("SetVelocity", Vector3.ZERO)
	if _player.has_method("SetMovementSpeed"):
		_player.call("SetMovementSpeed", 0.0)
	# (If your Racer exposes different names, call those similarly.)

	# 6) Aim the map/camera along the first segment (p0 -> p1)
	var dir := p1_px - p0_px
	if dir.length() > 0.0001:
		dir = dir.normalized()
		var yaw := atan2(dir.x, dir.y)  # forward (x,z) = (sin(yaw), cos(yaw))
		if _map.has_method("SetYaw"):
			_map.call("SetYaw", yaw)

func _push_path_points_once() -> void:
	if _map == null:
		return
	# Pseudo3D exports 'path_overlay_node' — use it to find the overlay
	var overlay := _map.get_node_or_null(_map.path_overlay_node) if _map.has_method("get") else null
	if overlay == null:
		return

	# Prefer UVs if available; fall back to pixel points
	var sent := false
	if overlay.has_method("get_path_points_uv"):
		var uv: PackedVector2Array = overlay.call("get_path_points_uv")
		if uv.size() > 1:
			_map.SetPathPoints(uv)
			sent = true
	if not sent and overlay.has_method("get_path_points"):
		var px: PackedVector2Array = overlay.call("get_path_points")
		if px.size() > 1:
			_map.SetPathPoints(px)
			sent = true

	# (Optional) live updates if you add this signal to PathOverlay2D:
	# signal path_points_changed(uv: PackedVector2Array)
	if overlay.has_signal("path_points_changed"):
		if not overlay.is_connected("path_points_changed", Callable(self, "_on_overlay_points_changed")):
			overlay.connect("path_points_changed", Callable(self, "_on_overlay_points_changed"))

func _on_overlay_points_changed(uv: PackedVector2Array) -> void:
	if uv.size() > 1:
		_map.SetPathPoints(uv)

func _process(delta):
	_map.Update(_player)

	if _player_freeze_frames > 0:
		_player_freeze_frames -= 1
	else:
		_player.Update(_map.ReturnForward())

	_spriteHandler.Update(_map.ReturnWorldMatrix())
	_animationHandler.Update()
	_backgroundElements.Update(_map.ReturnMapRotation())
