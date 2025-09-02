extends Button
class_name RacerButton

@export var racer_name: StringName = ""      # If blank, we'll infer from node name
@export var idle_anim_name: StringName = "idle"   # Fallbacks handled if missing
@export var rotate_anim_name: StringName = "Rotate"  # Fallbacks handled if missing
@export var hover_fps: float = 24.0
@export var flip_on_reverse: bool = true
@export var idle_flip_h: bool = false
@export var show_label: bool = true

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var name_label: Label = $Name if has_node("Name") else null

var _focus_active := false
var _rotate_fwd := ""
var _rotate_rev := ""

func _ready() -> void:
	# Ensure label exists (create if missing)
	if name_label == null:
		name_label = Label.new()
		name_label.name = "Name"
		add_child(name_label)

	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func(): grab_focus())  # hovering also focuses → same behavior
	resized.connect(_layout)

	# Name & label
	if String(racer_name) == "":
		racer_name = StringName(name)   # fallback if you didn't set it in the Inspector
	name_label.visible = show_label
	name_label.text = String(racer_name)

	if sprite.sprite_frames == null:
		push_error("%s: SpriteFrames missing on $Sprite." % name)
		return

	# Resolve animation names + configure
	_init_anim_names()
	_setup_rotate_reverse()

	# Start in idle loop
	sprite.flip_h = idle_flip_h
	_play_idle()

	# Focus-only animation switching
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	sprite.animation_finished.connect(_on_anim_finished)

	_layout()

func _layout() -> void:
	# Bottom label across the button, sprite centered above it
	if name_label:
		var lh := name_label.get_combined_minimum_size().y
		name_label.size = Vector2(size.x, lh)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var label_half := (name_label.get_combined_minimum_size().y if name_label and name_label.visible else 0.0) * 0.5
	if sprite:
		sprite.position = Vector2(size.x * 0.5, size.y * 0.5 - label_half)

func _init_anim_names() -> void:
	var sf := sprite.sprite_frames

	# Idle
	if idle_anim_name != "" and sf.has_animation(idle_anim_name):
		pass
	elif sf.has_animation("idle"):
		idle_anim_name = "idle"
	elif sf.has_animation("default"):
		idle_anim_name = "default"
	elif sf.has_animation("spin_fwd"):
		idle_anim_name = "spin_fwd"
	else:
		var names := sf.get_animation_names()
		idle_anim_name = names[0] if names.size() > 0 else ""

	# Rotate forward base
	if rotate_anim_name != "" and sf.has_animation(rotate_anim_name):
		_rotate_fwd = String(rotate_anim_name)
	elif sf.has_animation("Rotate"):
		_rotate_fwd = "Rotate"
	elif sf.has_animation("spin_fwd"):
		_rotate_fwd = "spin_fwd"
	else:
		_rotate_fwd = idle_anim_name  # fallback (won't look great, but won't crash)

func _setup_rotate_reverse() -> void:
	var sf := sprite.sprite_frames
	if _rotate_fwd == "": return

	sf.set_animation_loop(_rotate_fwd, false)
	sf.set_animation_speed(_rotate_fwd, hover_fps)

	_rotate_rev = _rotate_fwd + "_rev"
	if not sf.has_animation(_rotate_rev):
		sf.add_animation(_rotate_rev)
		var c := sf.get_frame_count(_rotate_fwd)
		for i in range(c - 1, -1, -1):
			sf.add_frame(_rotate_rev, sf.get_frame_texture(_rotate_fwd, i))
	sf.set_animation_loop(_rotate_rev, false)
	sf.set_animation_speed(_rotate_rev, hover_fps)

func _play_idle() -> void:
	if idle_anim_name != "" and sprite.sprite_frames.has_animation(idle_anim_name):
		sprite.animation = idle_anim_name
		sprite.play()
	else:
		sprite.playing = false

func _on_focus_entered() -> void:
	_focus_active = true
	if _rotate_fwd != "":
		sprite.animation = _rotate_fwd
		sprite.play()

func _on_focus_exited() -> void:
	_focus_active = false
	# Let the current cycle finish; _on_anim_finished will return to idle.

func _on_anim_finished() -> void:
	var sf := sprite.sprite_frames
	if sprite.animation == _rotate_fwd and sf.has_animation(_rotate_rev):
		if flip_on_reverse:
			sprite.flip_h = not sprite.flip_h
		sprite.animation = _rotate_rev
		sprite.play()
		return

	if sprite.animation == _rotate_rev:
		if _focus_active:
			if flip_on_reverse:
				sprite.flip_h = not sprite.flip_h
			sprite.animation = _rotate_fwd
			sprite.play()
		else:
			sprite.flip_h = idle_flip_h
			_play_idle()

func _on_pressed() -> void:
	# Parent scene connects pressed to read racer_name
	pass
