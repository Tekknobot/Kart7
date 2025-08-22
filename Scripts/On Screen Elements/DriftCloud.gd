extends GPUParticles2D

@export var player: Racer
@export var auto_configure: bool = true
@export var use_one_shot_bursts: bool = false
@export var min_speed_to_emit: float = 8.0

# Tuning
@export var particle_lifetime: float = 0.1   # node lifetime (renamed from 'lifetime')
@export var base_rate: float = 100.0
@export var speed_min: float = 100.0
@export var speed_max: float = 100.0
@export var spread_deg: float = 55.0
@export var gravity_y: float = 180.0
@export var scale_min: float = 0.5
@export var scale_max: float = 0.9

# Optional: set a round puff texture (white circle)
@export var cloud_texture: Texture2D

func _ready() -> void:
	z_as_relative = false
	z_index = 1000

	# Set node lifetime first (don’t collide with export name)
	lifetime = particle_lifetime

	if auto_configure and process_material == null:
		var pm := ParticleProcessMaterial.new()
		# Godot 4 expects Vector3 for 2D particles' direction/gravity
		pm.direction = Vector3(0, -1, 0)
		pm.spread = deg_to_rad(spread_deg)
		pm.gravity = Vector3(0, gravity_y, 0)
		pm.initial_velocity_min = speed_min
		pm.initial_velocity_max = speed_max
		pm.scale_min = scale_min
		pm.scale_max = scale_max
		pm.angular_velocity_min = -2.0
		pm.angular_velocity_max =  2.0
		pm.color = Color(1, 1, 1, 0.85)

		# color_ramp must be a GradientTexture1D
		var gt := GradientTexture1D.new()
		gt.gradient = _make_smoke_ramp()
		pm.color_ramp = gt

		process_material = pm

	if cloud_texture:
		texture = cloud_texture

	if use_one_shot_bursts:
		one_shot = true
		emitting = false
	else:
		one_shot = false
		emitting = false
		amount = int(base_rate * lifetime)  # lifetime is node property

func set_active(on: bool) -> void:
	# Call when drift starts/ends
	if use_one_shot_bursts:
		if on and _speed_ok():
			emitting = false
			restart()
			emitting = true
	else:
		emitting = on and _speed_ok()

func burst() -> void:
	# Call for hop puffs
	var prev_one_shot := one_shot
	var prev_emit := emitting
	one_shot = true
	emitting = false
	restart()
	emitting = true
	await get_tree().process_frame
	emitting = prev_emit
	one_shot = prev_one_shot

func _speed_ok() -> bool:
	return player == null or (player.ReturnMovementSpeed() >= min_speed_to_emit)

func _make_smoke_ramp() -> Gradient:
	var g := Gradient.new()
	g.colors = PackedColorArray([
		Color(1, 1, 1, 0.9),
		Color(0.85, 0.85, 0.85, 0.45),
		Color(0.7, 0.7, 0.7, 0.0)
	])
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	return g
