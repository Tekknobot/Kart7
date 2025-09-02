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

@onready var _player_script   := preload("res://Scripts/World Elements/Racers/Player.gd")
@onready var _opponent_script := preload("res://Scripts/World Elements/Racers/Opponent.gd")

func _apply_character_selection() -> void:
	var racers_root := get_node_or_null(^"Sprite Handler/Racers")
	if racers_root == null:
		return

	var choice := "Voltage"
	if _has_prop(Globals, "selected_racer"):
		choice = str(Globals.selected_racer)

	var new_player: Node = _player

	# Swap scripts so chosen racer is the Player; others are Opponents.
	for c in racers_root.get_children():
		if not (c is Node2D):
			continue
		if c.name == choice:
			if c.get_script() != _player_script:
				c.set_script(_player_script)
			new_player = c
		else:
			if c.get_script() != _opponent_script:
				c.set_script(_opponent_script)

	if new_player:
		_player = new_player
		# Update any node that has an exported `player_path` to point at the new player
		_retarget_player_paths(get_tree().current_scene, _player)

		# Keep HUD in sync immediately
		var hud := get_node_or_null(^"RaceHUD")
		if hud:
			hud.set("player_path", hud.get_path_to(_player))
			hud.set("_player", _player) # RaceHUD caches this in _ready(); set it directly here.

func _has_prop(obj: Object, prop: StringName) -> bool:
	for p in obj.get_property_list():
		if p.has("name") and p["name"] == prop:
			return true
	return false

func _retarget_player_paths(node: Node, player: Node) -> void:
	# Recursively set `player_path` export where present
	for child in node.get_children():
		var props := child.get_property_list()
		for p in props:
			if p.has("name") and p["name"] == "player_path":
				child.set("player_path", child.get_path_to(player))
				break
		_retarget_player_paths(child, player)

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
	_apply_character_selection()
	# (keep the rest of your existing _ready() as-is)
	
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
