extends Node2D

@export var _map : Node2D
@export var _collision : Node
@export var _player : Racer
@export var _spriteHandler : Node2D
@export var _animationHandler : Node
@export var _backgroundElements : Node2D

# NEW: RaceManager
@export var _raceManager : RaceManager

var _player_freeze_frames := 0
@onready var _smoother := preload("res://addons/FrameSmoother.gd").new()

func _process(delta: float) -> void:
	var dt := _smoother.smooth_delta(delta)

	_map.Update(_player)
	if _player_freeze_frames > 0:
		_player_freeze_frames -= 1
	else:
		_player.Update(_map.ReturnForward())

	_spriteHandler.Update(_map.ReturnWorldMatrix())
	_animationHandler.Update()
	_backgroundElements.Update(_map.ReturnMapRotation())

	# NEW: advance standings & z-ordering
	if is_instance_valid(_raceManager):
		_raceManager.Update()

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

	# NEW: RaceManager boot
	if is_instance_valid(_raceManager):
		_raceManager.Setup()
		_raceManager.connect("standings_changed", Callable(self, "_on_standings_changed"))

	call_deferred("_push_path_points_once")
	call_deferred("_spawn_player_at_path_index", 1)

func _on_standings_changed(board: Array) -> void:
	# example: print leader name and lap
	if board.size() > 0:
		var lead = board[0]
		#print("P1:", lead["node"].name, "lap", lead["lap"])
		pass
