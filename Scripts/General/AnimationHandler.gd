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

@export var _gravel_speed_threshold: float = 20.0  # don’t show gravel unless speed >= this

func Setup(player : Racer):
	_player = player
	_originalPlayerSpriteYPos = player.ReturnSpriteGraphic().position.y

func Update() -> void:
	if _player == null or _effectsPlayer == null or _effectsPlayer.get_parent() == null:
		return

	# z-index keep-alive
	if (_effectsPlayer.get_parent().z_index != _player.ReturnSpriteGraphic().z_index + 1):
		_effectsPlayer.get_parent().z_index = _player.ReturnSpriteGraphic().z_index + 1

	var is_hopping: bool = (_player.has_method("ReturnIsHopping") and _player.ReturnIsHopping())
	var is_drifting: bool = (_player.has_method("ReturnIsDrifting") and _player.ReturnIsDrifting())
	var rt := _player.ReturnOnRoadType()

	# HOP
	if is_hopping:
		_hide_all_effects_and_stop()
		_wasHopping = true
		return
	elif _wasHopping:
		_wasHopping = false
		PlaySpecificEffectAnimation(rt)

	# DRIFT
	if is_drifting and rt != Globals.RoadType.SINK and rt != Globals.RoadType.WALL:
		# If we're drifting *on gravel*, keep the gravel effect active/animated.
		# (Let the speed gate decide visibility & playback of Gravel_Anim.)
		if rt == Globals.RoadType.GRAVEL:
			_apply_gravel_speed_gate()
		else:
			_play_drift_effect()
		_wasDrifting = true
	else:
		if _wasDrifting:
			_wasDrifting = false
			PlaySpecificEffectAnimation(rt)

	# If road type changed, re-pick base effect
	if rt != _previousHandledRoadType:
		PlaySpecificEffectAnimation(rt)

	# --- NEW: enforce gravel speed gate every frame while on gravel ---
	if rt == Globals.RoadType.GRAVEL:
		_apply_gravel_speed_gate()

	# bounce (except in SINK)
	if rt != Globals.RoadType.SINK:
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
			# if we’re basically not moving, don’t display the gravel at all
			if _player.ReturnMovementSpeed() < _gravel_speed_threshold:
				_effectsPlayer.get_parent().visible = false
				# make sure any previously playing gravel anim is stopped
				if _effectsPlayer.is_playing() and _effectsPlayer.current_animation.begins_with("Gravel"):
					_effectsPlayer.stop()
				# hide wheel gas shader sprites if you were showing them for gravel
				if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
					_specialWheelEffect[0].visible = false
				if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
					_specialWheelEffect[1].visible = false
				_firstTimeSink = true
			else:
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

func _apply_gravel_speed_gate() -> void:
	var parent := _effectsPlayer.get_parent()
	var speed := _player.ReturnMovementSpeed()

	if speed < _gravel_speed_threshold:
		if parent: parent.visible = false
		# stop gravel anim if it’s playing
		if _effectsPlayer.is_playing() and _effectsPlayer.current_animation != "" and _effectsPlayer.current_animation.begins_with("Gravel"):
			_effectsPlayer.stop()
		# hide wheels
		if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
			_specialWheelEffect[0].visible = false
		if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
			_specialWheelEffect[1].visible = false
	else:
		if parent: parent.visible = true
		# show wheels
		if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
			_specialWheelEffect[0].visible = true
		if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
			_specialWheelEffect[1].visible = true
		# ensure Gravel_Anim is playing when we’re fast enough
		if _effectsPlayer.has_animation("Gravel_Anim"):
			if _effectsPlayer.current_animation != "Gravel_Anim" or !_effectsPlayer.is_playing():
				_effectsPlayer.stop()
				_effectsPlayer.play("Gravel_Anim")
