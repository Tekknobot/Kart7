#SpriteHandler.gd
extends Node2D

@export var _showSpriteInRangeOf : int = 440
@export var _hazards : Array[Hazard]
var _worldElements : Array[WorldElement]
var _player : Racer

var _mapSize : int = 1024
var _worldMatrix : Basis

# --- ADD near top of SpriteHandler.gd ---
@export var pseudo3d_node: NodePath                    # your Pseudo3D Sprite2D
@export var auto_load_path := true
@export var path_overlay_node: NodePath   # assign your PathOverlay2D node

# --- MODIFY Setup(...) to auto-apply path after world init ---
func Setup(worldMatrix : Basis, mapSize : int, player : Racer):
	_worldMatrix = worldMatrix
	_mapSize = mapSize
	_player = player
	_worldElements.append(player)
	_worldElements.append_array(_hazards)
	WorldToScreenPosition(player)

	if auto_load_path:
		_apply_path_from_json()

func Update(worldMatrix : Basis):
	_worldMatrix = worldMatrix
	
	for hazard in _hazards:
		HandleSpriteDetail(hazard)
		WorldToScreenPosition(hazard)

	# feed matrix + screen size to the overlay so it can project points
	var ov := get_node_or_null(path_overlay_node)
	if ov and ov.has_method("set_world_and_screen"):
		ov.set_world_and_screen(_worldMatrix, Globals.screenSize)
			
	HandleYLayerSorting()

func HandleSpriteDetail(target : WorldElement) -> void:
	var playerPosition : Vector2 = Vector2(_player.ReturnMapPosition().x, _player.ReturnMapPosition().z)
	var targetPosition : Vector2 = Vector2(target.ReturnMapPosition().x, target.ReturnMapPosition().z)
	var distance : float = targetPosition.distance_to(playerPosition) * _mapSize

	target.ReturnSpriteGraphic().visible = (distance < _showSpriteInRangeOf)
	if not target.ReturnSpriteGraphic().visible:
		return
	
	var detailStates : int = target.ReturnTotalDetailStates()
	var normalizedDistance : float = distance / float(_showSpriteInRangeOf)
	var expFactor : float = pow(normalizedDistance, 0.75)
	var detailLevel : int = int(clamp(expFactor * float(detailStates), 0.0, float(detailStates - 1)))
	var newRegionPos : int = int(target.ReturnSpriteGraphic().region_rect.size.y) * detailLevel
	
	target.ReturnSpriteGraphic().region_rect.position.y = float(newRegionPos)

func HandleYLayerSorting():
	_worldElements.sort_custom(SortByScreenY)
	for i in range(_worldElements.size()):
		var element = _worldElements[i]
		element.ReturnSpriteGraphic().z_index = i

func SortByScreenY(a : WorldElement, b : WorldElement) -> int:
	var aPosY : float = a.ReturnScreenPosition().y
	var bPosY : float = b.ReturnScreenPosition().y
	if aPosY < bPosY:
		return -1
	elif aPosY > bPosY:
		return 1
	else:
		return 0

func WorldToScreenPosition(worldElement : WorldElement):
	var transformedPos : Vector3 = _worldMatrix.inverse() * Vector3(worldElement.ReturnMapPosition().x, worldElement.ReturnMapPosition().z, 1.0)
	if (transformedPos.z < 0.0):
		worldElement.SetScreenPosition(Vector2(-1000, -1000)) 
		return  
	
	var screenPos : Vector2 = Vector2(transformedPos.x / transformedPos.z, transformedPos.y / transformedPos.z) 
	screenPos = (screenPos + Vector2(0.5, 0.5)) * Globals.screenSize
	screenPos.y -= (worldElement.ReturnSpriteGraphic().region_rect.size.y * worldElement.ReturnSpriteGraphic().scale.x) / 2
	
	if(screenPos.floor().x > Globals.screenSize.x or screenPos.x < 0 or screenPos.floor().y > Globals.screenSize.y or screenPos.y < 0): 
		worldElement.visible = false
		worldElement.SetScreenPosition(Vector2(-1000, -1000)) 
		return  
	else:
		worldElement.SetScreenPosition(screenPos.floor())

# --- ADD to SpriteHandler.gd ---
func _apply_path_from_json() -> void:
	var p3d = get_node_or_null(pseudo3d_node)
	if p3d == null:
		push_warning("SpriteHandler: pseudo3d_node not set.")
		return

	if not p3d.has_method("SetPathPoints"):
		push_warning("SpriteHandler: Pseudo3D is missing SetPathPoints().")
		return
