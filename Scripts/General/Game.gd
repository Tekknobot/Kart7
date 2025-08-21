extends Node2D

@export var _map : Node2D                # Pseudo3D.gd on a Sprite2D
@export var _collision : Node
@export var _player : Racer
@export var _spriteHandler : Node2D
@export var _animationHandler : Node
@export var _backgroundElements : Node2D

var _player_freeze_frames := 0  # frames to skip calling _player.Update after spawn

func _uniq_path_points_uv(overlay: Node) -> Array:
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
	if _map == null or _player == null:
		return
	if not _map is Sprite2D:
		return
	if (_map as Sprite2D).texture == null:
		push_error("Pseudo3D Sprite2D has no texture; cannot place player.")
		return

	var overlay := _map.get_node_or_null(_map.path_overlay_node)
	if overlay == null:
		return
	var uv_list := _uniq_path_points_uv(overlay)
	if uv_list.size() < 2:
		return

	if start_index < 0:
		start_index = 0
	if start_index >= uv_list.size():
		start_index = uv_list.size() - 1

	var uv0: Vector2 = uv_list[start_index]
	var uv1: Vector2 = uv_list[(start_index + 1) % uv_list.size()]

	# Match Opponent.gd convention: flip UV.y once
	uv0.y = 1.0 - uv0.y
	uv1.y = 1.0 - uv1.y

	var tex_w := float((_map as Sprite2D).texture.get_size().x)
	var p0_px := uv0 * tex_w
	var p1_px := uv1 * tex_w

	var py := _player.ReturnMapPosition().y
	_player.SetMapPosition(Vector3(p0_px.x, py, p0_px.y))

	if _player.has_method("SetVelocity"):
		_player.call("SetVelocity", Vector3.ZERO)
	if _player.has_method("SetMovementSpeed"):
		_player.call("SetMovementSpeed", 0.0)

	_player_freeze_frames = 2

	var dir := p1_px - p0_px
	if dir.length() > 0.0001:
		dir = dir.normalized()
		var yaw := atan2(dir.x, dir.y)  # (x,z) forward = (sin(yaw), cos(yaw))
		if _map.has_method("SetYaw"):
			_map.call("SetYaw", yaw)

func _ready() -> void:
	if _map == null or _player == null:
		push_error("World: _map or _player is null.")
		return
	if not _map is Sprite2D:
		push_error("World: _map is not a Sprite2D (Pseudo3D.gd).")
		return
	if (_map as Sprite2D).texture == null:
		push_error("World: _map Sprite2D has no texture.")
		return

	_map.Setup(Globals.screenSize, _player)
	if _collision != null and _collision.has_method("Setup"):
		_collision.call("Setup")

	_player.Setup((_map as Sprite2D).texture.get_size().x)
	_spriteHandler.Setup(_map.ReturnWorldMatrix(), (_map as Sprite2D).texture.get_size().x, _player)
	_animationHandler.Setup(_player)

	# Defer so the overlay is present and Pseudo3D has finished Setup()
	call_deferred("_push_path_points_once")
	call_deferred("_spawn_player_at_path_index", 0)

func _push_path_points_once() -> void:
	if _map == null:
		return
	var overlay := _map.get_node_or_null(_map.path_overlay_node)
	if overlay == null:
		return

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

	# (Optional) live updates if PathOverlay2D emits this signal
	if overlay.has_signal("path_points_changed"):
		if not overlay.is_connected("path_points_changed", Callable(self, "_on_overlay_points_changed")):
			overlay.connect("path_points_changed", Callable(self, "_on_overlay_points_changed"))

func _on_overlay_points_changed(uv: PackedVector2Array) -> void:
	if uv.size() > 1:
		_map.SetPathPoints(uv)

func _process(delta: float) -> void:
	_map.Update(_player)

	if _player_freeze_frames > 0:
		_player_freeze_frames -= 1
	else:
		_player.Update(_map.ReturnForward())

	_spriteHandler.Update(_map.ReturnWorldMatrix())
	_animationHandler.Update()
	_backgroundElements.Update(_map.ReturnMapRotation())
