# Scripts/AI/AngleSprite.gd
extends Sprite2D

# Right-half framing (left is handled by flip_h)
@export var right_frames: int = 8            # number of frames for the RIGHT half
@export var first_right_frame: int = 0       # index of the first right-side frame
@export var right_front_at_index0: bool = true  # true: frame0 is front-right; false: back-right

# Optional smoothing
@export var angular_lerp := 0.25

var _cam_f := Vector2(0, 1)   # camera forward in map space (x,z)
var _kart_f := Vector2(1, 0)  # kart forward in map space
var _rel := 0.0               # relative angle (-π..π)

func set_camera_forward(cam_forward_map: Vector2) -> void:
	_cam_f = cam_forward_map.normalized()

func set_kart_forward(kart_forward_map: Vector2) -> void:
	_kart_f = kart_forward_map.normalized()

func _process(_dt: float) -> void:
	# relative angle (-π..π). sign>0 => kart is to the LEFT of camera forward
	var dot := _cam_f.dot(_kart_f)
	var det := _cam_f.x * _kart_f.y - _cam_f.y * _kart_f.x
	var target_rel := atan2(det, dot)
	_rel = lerp_angle(_rel, target_rel, clamp(angular_lerp, 0.0, 1.0))
	_apply_angle_to_frame(_rel)

func _apply_angle_to_frame(rel_angle: float) -> void:
	var a = abs(rel_angle)                               # 0..π
	var steps = max(1, right_frames - 1)
	var idx := int(round(a / PI * float(steps)))
	idx = clamp(idx, 0, max(0, right_frames - 1))

	# Choose ordering on the right side
	if not right_front_at_index0:
		idx = (right_frames - 1) - idx

	# Flip for left side
	flip_h = (rel_angle > 0.0)

	frame = first_right_frame + idx
