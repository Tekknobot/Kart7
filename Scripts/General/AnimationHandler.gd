extends Node

@export_category("Player Animation Settings")
@export var _effectsPlayer : AnimationPlayer
@export var _roadRoughness : int = 3
var _currBounceTime : float = 0.0
var _bouncedUp : bool = false

var _player : Racer
var _previousHandledRoadType : Globals.RoadType = Globals.RoadType.ROAD
var _originalPlayerSpriteYPos : float = 0

@export var _specialWheelEffect : Array[Sprite2D]
var _firstTimeSink : bool = true

# Which AnimationPlayer clip to use while drifting (without the "_Anim" suffix)
@export var _driftEffectAnimBaseName: String = "Drift"

# State trackers
var _wasHopping: bool = false
var _wasDrifting: bool = false

func Setup(player : Racer):
	_player = player
	_originalPlayerSpriteYPos = player.ReturnSpriteGraphic().position.y

func Update() -> void:
	if _player == null or _effectsPlayer == null or _effectsPlayer.get_parent() == null:
		return

	# keep effects layer above the sprite
	if (_effectsPlayer.get_parent().z_index != _player.ReturnSpriteGraphic().z_index + 1):
		_effectsPlayer.get_parent().z_index = _player.ReturnSpriteGraphic().z_index + 1

	# --- read hop & drift states (duck-typed so no class_name required) ---
	var is_hopping: bool = (_player.has_method("ReturnIsHopping") and _player.ReturnIsHopping())
	var is_drifting: bool = (_player.has_method("ReturnIsDrifting") and _player.ReturnIsDrifting())

	# HOP: hide effects; skip bounce; resume ground effect on landing
	if is_hopping:
		_hide_all_effects_and_stop()
		_wasHopping = true
		return
	elif _wasHopping:
		_wasHopping = false
		PlaySpecificEffectAnimation(_player.ReturnOnRoadType())

	# DRIFT: play chosen effect; toggle gas shader on wheels; restore on end
	var rt := _player.ReturnOnRoadType()
	if is_drifting and rt != Globals.RoadType.SINK and rt != Globals.RoadType.WALL:
		_play_drift_effect()
		_wasDrifting = true
	else:
		if _wasDrifting:
			_wasDrifting = false
			PlaySpecificEffectAnimation(rt)

	# --- normal ground-effect flow ---
	if (_player.ReturnOnRoadType() != _previousHandledRoadType):
		PlaySpecificEffectAnimation(_player.ReturnOnRoadType())

	# keep the bounce unless we're in SINK
	if (_player.ReturnOnRoadType() != Globals.RoadType.SINK):
		PlayerRoadBounceAnimation()

func PlaySpecificEffectAnimation(roadType : Globals.RoadType):
	var animName := ""
	_effectsPlayer.get_parent().visible = true

	# defensively handle wheel array size
	if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
		_specialWheelEffect[0].visible = false
	if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
		_specialWheelEffect[1].visible = false
	
	match roadType:
		Globals.RoadType.ROAD:
			_effectsPlayer.get_parent().visible = false
			_firstTimeSink = true
		Globals.RoadType.GRAVEL:
			_effectsPlayer.get_parent().visible = true
			if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
				_specialWheelEffect[0].visible = true
			if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
				_specialWheelEffect[1].visible = true
			animName = "Gravel"
			_firstTimeSink = true
		Globals.RoadType.OFF_ROAD:
			animName = "Idle_Off_Road" if _player.ReturnMovementSpeed() < 1 else "Driving_Off_Road"
			_firstTimeSink = true
		Globals.RoadType.WALL:
			if (_effectsPlayer.current_animation == "Sink_Anim"):
				_player.ReturnSpriteGraphic().self_modulate.a = 0
			else:
				_effectsPlayer.get_parent().visible = false
		Globals.RoadType.SINK:
			if (_firstTimeSink):
				if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
					_specialWheelEffect[0].visible = true
				if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
					_specialWheelEffect[1].visible = true
				animName = "Sink_Splash"

	if animName != "":
		animName += "_Anim"

	_previousHandledRoadType = roadType

	# only play if valid & not already the same
	if animName != "" and _effectsPlayer.has_animation(animName):
		if animName != _effectsPlayer.current_animation:
			_effectsPlayer.stop()
			_effectsPlayer.play(animName)

func PlayerRoadBounceAnimation():
	_currBounceTime += get_process_delta_time() * _player.ReturnMovementSpeed()
	if (_currBounceTime > 1.0):
		_currBounceTime = 0.0
		_bouncedUp = !_bouncedUp

	if _bouncedUp:
		_player.ReturnSpriteGraphic().position.y = _originalPlayerSpriteYPos - _roadRoughness
	else:
		_player.ReturnSpriteGraphic().position.y = _originalPlayerSpriteYPos

func SetFirstTimeSink(input : bool): _firstTimeSink = input
func PlaySinkAnimation(): _effectsPlayer.play("Sink_Anim")

# --- helpers ---
func _hide_all_effects_and_stop() -> void:
	var parent: Node = _effectsPlayer.get_parent()
	if parent: parent.visible = false
	if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
		_specialWheelEffect[0].visible = false
	if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
		_specialWheelEffect[1].visible = false
	if _effectsPlayer and _effectsPlayer.is_playing():
		_effectsPlayer.stop()

func _play_drift_effect() -> void:
	var anim_base := _driftEffectAnimBaseName.strip_edges()
	if anim_base == "":
		return
	var anim_name := anim_base + "_Anim"

	var parent: Node = _effectsPlayer.get_parent()
	if parent: parent.visible = true

	# show wheels while drifting (so gas shader visuals are visible on them)
	if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
		_specialWheelEffect[0].visible = true
	if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
		_specialWheelEffect[1].visible = true

	if _effectsPlayer.has_animation(anim_name):
		if _effectsPlayer.current_animation != anim_name or !_effectsPlayer.is_playing():
			_effectsPlayer.stop()
			_effectsPlayer.play(anim_name)
