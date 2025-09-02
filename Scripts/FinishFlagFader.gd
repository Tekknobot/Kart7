# Scripts/UI/FinishFlagFader.gd
extends ColorRect

@export var start_delay: float = 0.0
@export var rise_time:   float = 0.8   # 0 -> 1
@export var hold_full:   float = 0.15  # hold at 1
@export var fall_time:   float = 0.8   # 1 -> 0
@export var hold_zero:   float = 0.15  # hold at 0
@export var auto_start:  bool = true

var _tw: Tween
var _sm: ShaderMaterial

func _ready() -> void:
	_sm = material as ShaderMaterial
	if auto_start:
		Start()

func Start() -> void:
	if _sm == null:
		return
	Stop() # clear any old tween

	# ensure a defined starting point
	_set_fade(0.0)

	_tw = create_tween()
	_tw.set_loops()
	if start_delay > 0.0:
		_tw.tween_interval(start_delay)

	# 0 -> 1
	_tw.tween_method(_set_fade, 0.0, 1.0, rise_time)
	# hold at 1
	if hold_full > 0.0:
		_tw.tween_interval(hold_full)
	# 1 -> 0
	_tw.tween_method(_set_fade, 1.0, 0.0, fall_time)
	# hold at 0
	if hold_zero > 0.0:
		_tw.tween_interval(hold_zero)

func Stop() -> void:
	if _tw:
		_tw.kill()
		_tw = null

func _set_fade(v: float) -> void:
	if _sm:
		_sm.set_shader_parameter("fade", clamp(v, 0.0, 1.0))
