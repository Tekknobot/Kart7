#WorldElement.gd
class_name WorldElement
extends Node2D

@export var _spriteGFX : Sprite2D
@export var _mapPosition : Vector3 = Vector3(50, 0, 537)
var _mapSize : int = 1024
var _screenPosition : Vector2i

func SetMapSize(size : int): _mapSize = size
func ReturnMapPosition() -> Vector3: return _mapPosition / _mapSize
func SetMapPosition(mapPosition : Vector3): _mapPosition = mapPosition

func ReturnScreenPosition() -> Vector2i: return _screenPosition
func SetScreenPosition(screenPosition : Vector2i): 
	_screenPosition = screenPosition
	position = _screenPosition

@export var sprite_graphic_path: NodePath = ^"GFX/AngleSprite"

func ReturnSpriteGraphic() -> CanvasItem:
	var n := get_node_or_null(sprite_graphic_path)
	if n != null and n is CanvasItem:
		return n
	return null

func SpriteOrNull() -> CanvasItem:
	var n := get_node_or_null(sprite_graphic_path)
	return n if n != null and n is CanvasItem else null

func SetSpriteOffsetY(y: float) -> void:
	var spr := SpriteOrNull()
	if spr == null: return
	var off: Vector2 = spr.offset
	off.y = y
	spr.offset = off

func SetSpriteZIndex(z: int) -> void:
	var spr := SpriteOrNull()
	if spr == null: return
	spr.z_index = z

func SetSpriteGlobalPos(p: Vector2) -> void:
	var spr := SpriteOrNull()
	if spr == null: return
	spr.global_position = p
