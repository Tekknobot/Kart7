# CollisionSampler.gd
# Optimized color sampling for a collision texture Image.
# Replace direct get_pixel() calls with this; keep Image locked.
# Usage:
#   sampler.setup(texture)
#   var col := sampler.get_pixelv(Vector2i(x,y))
extends RefCounted

var _img: Image
var _w: int = 0
var _h: int = 0

func setup(tex: Texture2D) -> void:
	if tex == null:
		push_warning("CollisionSampler: null texture")
		return
	_img = tex.get_image()
	if _img == null:
		push_warning("CollisionSampler: texture had no image")
		return
	_w = _img.get_width()
	_h = _img.get_height()
	# Locking is faster for many reads even if we don't write.
	# (Godot 4: lock is optional for reads, but reduces overhead.)
	if not _img.is_locked():
		_img.lock()

func size() -> Vector2i:
	return Vector2i(_w, _h)

func get_pixelv(p: Vector2i) -> Color:
	if _img == null:
		return Color(0,0,0,1)
	var x := clampi(p.x, 0, _w - 1)
	var y := clampi(p.y, 0, _h - 1)
	return _img.get_pixel(x, y)

func is_equal_color(a: Color, b: Color, tol: float = 0.01) -> bool:
	return abs(a.r - b.r) <= tol and abs(a.g - b.g) <= tol and abs(a.b - b.b) <= tol and abs(a.a - b.a) <= tol
