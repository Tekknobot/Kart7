# CheapTrig.gd
# Fast approximations for atan2/normalize/lerp to cut trig cost in tight loops.
# Use only where tiny visual error is acceptable.
extends RefCounted

static func fast_normalize(v: Vector2) -> Vector2:
	var ls := v.x*v.x + v.y*v.y
	if ls <= 0.0: return Vector2.ZERO
	# 1/sqrt approximation (Newton-Raphson, one iteration)
	var x = 1.0/sqrt(ls)
	return Vector2(v.x * x, v.y * x)

static func fast_atan2(y: float, x: float) -> float:
	# 7th-order poly approx; valid for gameplay heading and sprite selection
	var abs_y = abs(y) + 1e-10
	var r: float
	var angle: float
	if x < 0.0:
		r = (x + abs_y) / (abs_y - x)
		angle = 0.75 * PI
	else:
		r = (x - abs_y) / (x + abs_y)
		angle = 0.25 * PI
	angle += (0.1963 * r * r - 0.9817) * r
	if y < 0.0:
		angle = -angle
	return angle
