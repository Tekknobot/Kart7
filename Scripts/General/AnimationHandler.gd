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
	var spr := _player.ReturnSpriteGraphic()
	_originalPlayerSpriteYPos = spr.position.y if spr != null else 0.0

func Update() -> void:
	if _player == null or _effectsPlayer == null or _effectsPlayer.get_parent() == null:
		return

	# z-index keep-alive
	var parent := _effectsPlayer.get_parent()
	var pspr := _player.ReturnSpriteGraphic()
	if parent != null and pspr != null:
		var want := pspr.z_index + 1
		if parent.z_index != want:
			parent.z_index = want

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
		if rt == Globals.RoadType.GRAVEL:
			_apply_gravel_speed_gate()
		else:
			_play_drift_effect()
		_wasDrifting = true
	else:
		if _wasDrifting:
			_wasDrifting = false
			PlaySpecificEffectAnimation(rt)

	if rt != _previousHandledRoadType:
		PlaySpecificEffectAnimation(rt)

	if rt == Globals.RoadType.GRAVEL:
		_apply_gravel_speed_gate()

	if rt != Globals.RoadType.SINK:
		PlayerRoadBounceAnimation()

func PlaySpecificEffectAnimation(roadType : Globals.RoadType):
	var animName := ""
	_effectsPlayer.get_parent().visible = true

	if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
		_specialWheelEffect[0].visible = false
	if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
		_specialWheelEffect[1].visible = false
	
	match roadType:
		Globals.RoadType.ROAD:
			_effectsPlayer.get_parent().visible = false
			_firstTimeSink = true
		Globals.RoadType.GRAVEL:
			if _player.ReturnMovementSpeed() < _gravel_speed_threshold:
				_effectsPlayer.get_parent().visible = false
				# if gravel anim was playing, stop it
				if _effectsPlayer.is_playing() and _effectsPlayer.current_animation.begins_with("Gravel"):
					_effectsPlayer.stop()
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
				var pspr := _player.ReturnSpriteGraphic()
				if pspr != null:
					pspr.self_modulate.a = 0.0
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

	if animName != "" and _effectsPlayer.has_animation(animName):
		# RESTART if stopped, even if it's already current; force loop
		if animName != _effectsPlayer.current_animation or !_effectsPlayer.is_playing():
			_effectsPlayer.stop()
			_set_anim_loop(animName, true)
			_effectsPlayer.play(animName)

func PlayerRoadBounceAnimation():
	_currBounceTime += get_process_delta_time() * _player.ReturnMovementSpeed()
	if (_currBounceTime > 1.0):
		_currBounceTime = 0.0
		_bouncedUp = !_bouncedUp

	var spr := _player.ReturnSpriteGraphic()
	if spr == null:
		return

	if _bouncedUp:
		spr.position.y = _originalPlayerSpriteYPos - _roadRoughness
	else:
		spr.position.y = _originalPlayerSpriteYPos

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
			_set_anim_loop(anim_name, true)
			_effectsPlayer.play(anim_name)

func _apply_gravel_speed_gate() -> void:
	var parent := _effectsPlayer.get_parent()
	var speed := _player.ReturnMovementSpeed()

	# If drifting, do NOT let gravel logic stop the effect; keep drift playing.
	if _player.has_method("ReturnIsDrifting") and _player.ReturnIsDrifting():
		if parent: parent.visible = true
		# wheels visible while drifting
		if _specialWheelEffect.size() > 0 and _specialWheelEffect[0]:
			_specialWheelEffect[0].visible = true
		if _specialWheelEffect.size() > 1 and _specialWheelEffect[1]:
			_specialWheelEffect[1].visible = true
		_play_drift_effect()
		return

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
		# ensure Gravel_Anim is playing when we’re fast enough and NOT drifting
		if _effectsPlayer.has_animation("Gravel_Anim"):
			if _effectsPlayer.current_animation != "Gravel_Anim" or !_effectsPlayer.is_playing():
				_effectsPlayer.stop()
				_set_anim_loop("Gravel_Anim", true)
				_effectsPlayer.play("Gravel_Anim")

func _set_anim_loop(anim_name: String, on: bool) -> void:
	var a := _effectsPlayer.get_animation(anim_name)
	if a != null:
		a.loop = on
