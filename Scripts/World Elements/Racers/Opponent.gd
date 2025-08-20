extends CharacterBody2D

# Drag your PathOverlay2D node here in the inspector
@export_node_path("Node2D") var path_overlay_node: NodePath

@export var speed: float = 120.0
@export var lookahead: int = 5

var path_points: PackedVector2Array = []
var current_index := 0

func _ready():
	# Load points directly from the overlay node
	var overlay = get_node_or_null(path_overlay_node)
	if overlay and overlay.has_method("get_path_points"):
		path_points = overlay.get_path_points()
		print("[AI] Loaded", path_points.size(), "path points from overlay")
	else:
		push_warning("[AI] No path overlay node found!")

func _physics_process(delta):
	if path_points.is_empty():
		return

	# get target point with lookahead
	var target_index = (current_index + lookahead) % path_points.size()
	var target = path_points[target_index]

	# move towards it
	var dir = (target - global_position).normalized()
	velocity = dir * speed
	move_and_slide()

	# advance index when close enough
	if global_position.distance_to(path_points[current_index]) < 16.0:
		current_index = (current_index + 1) % path_points.size()
