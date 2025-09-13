# res://Scripts/Tracks/TrackConfig.gd
extends Resource
class_name TrackConfig

@export var display_name: String = ""          # e.g. "Los Angeles"
@export var track_texture: Texture2D           # map.png
@export var grass_texture: Texture2D           # grass.png
@export var collision_map: Texture2D           # collision.png
@export var tint_color: Color = Color(1,1,1,1) # optional
@export var tint_strength: float = 0.0         # 0..1
@export var path_points_uv: PackedVector2Array # closed loop (0..1)
