extends Button
class_name RacerButton

@export var racer_name: StringName = ""
@export var idle_anim_name: StringName = "idle"
@export var rotate_anim_name: StringName = "Rotate"
@export var hover_fps: float = 24.0
@export var flip_on_reverse: bool = true
@export var idle_flip_h: bool = false
@export var show_label: bool = true

# tint + shader options
@export var tint_color: Color = Color(1,1,1,1)
@export_file("*.gdshader") var yoshi_shader_path: String = "res://Scripts/Shaders/YoshiSwap.gdshader"
@export var yoshi_source_hue: float = 0.333333
@export var yoshi_tolerance: float = 0.08
@export var yoshi_strength: float = 1.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var name_label: Label = $Name if has_node("Name") else null

var _focus_active := false
var _rotate_fwd := ""
var _rotate_rev := ""

@export var yoshi_edge_soft: float = 0.20

func _ready() -> void:
	if name_label == null:
		name_label = Label.new()
		name_label.name = "Name"
		add_child(name_label)

	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(_on_mouse_entered)
	resized.connect(_layout)

	if String(racer_name) == "":
		racer_name = StringName(name)
	name_label.visible = show_label
	name_label.text = String(racer_name)

	name_label.visible = show_label
	name_label.text = String(racer_name)
	# keep name text white (don’t inherit any previous override)
	name_label.remove_theme_color_override("font_color")
	name_label.add_theme_color_override("font_color", Color.WHITE)

	if sprite.sprite_frames == null:
		push_error("%s: SpriteFrames missing on $Sprite." % name)
		return

	_init_anim_names()
	_setup_rotate_reverse()

	sprite.flip_h = idle_flip_h
	_play_idle()

	# --- NEW: ensure shader and pull color from Globals ---
	_ensure_yoshi_shader()
	_apply_color_from_globals()  # <- pulls color by racer_name from Globals

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	sprite.animation_finished.connect(_on_anim_finished)

	_layout()

func _on_mouse_entered() -> void:
	grab_focus()

func _layout() -> void:
	if name_label:
		var lh := name_label.get_combined_minimum_size().y
		name_label.size = Vector2(size.x, lh)
		name_label.position = Vector2(0, size.y - lh)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var label_half := (name_label.get_combined_minimum_size().y if name_label and name_label.visible else 0.0) * 0.5
	if sprite:
		sprite.position = Vector2(size.x * 0.5, size.y * 0.5 - label_half)

# -------------------- NEW: Globals-driven color --------------------

func _apply_color_from_globals() -> void:
	# Prefer Globals.get_racer_color(name) if available; otherwise default white
	var col := Color.WHITE
	if "get_racer_color" in Globals:
		col = Globals.get_racer_color(String(racer_name))
	tint_color = col
	_apply_tint_to_shader()  # push to material/label (with fallback)

	print("RacerButton color: ", racer_name, " → ", tint_color)	

# Call this if you change racer_name after _ready()
func refresh_from_globals() -> void:
	_apply_color_from_globals()

# Optional helper if you want to update name + color together
func set_racer_name(v: StringName) -> void:
	racer_name = v
	if is_node_ready():
		if name_label:
			name_label.text = String(racer_name)
		_apply_color_from_globals()

# ------------------------------------------------------------------

func _init_anim_names() -> void:
	var sf := sprite.sprite_frames
	if idle_anim_name == "" or !sf.has_animation(idle_anim_name):
		if sf.has_animation("idle"): idle_anim_name = "idle"
		elif sf.has_animation("default"): idle_anim_name = "default"
		elif sf.has_animation("spin_fwd"): idle_anim_name = "spin_fwd"
		else:
			var names := sf.get_animation_names()
			idle_anim_name = names[0] if names.size() > 0 else ""

	if rotate_anim_name == "" or !sf.has_animation(rotate_anim_name):
		if sf.has_animation("Rotate"): _rotate_fwd = "Rotate"
		elif sf.has_animation("spin_fwd"): _rotate_fwd = "spin_fwd"
		else: _rotate_fwd = idle_anim_name
	else:
		_rotate_fwd = String(rotate_anim_name)

func _setup_rotate_reverse() -> void:
	var sf := sprite.sprite_frames
	if _rotate_fwd == "": return
	sf.set_animation_loop(_rotate_fwd, false)
	sf.set_animation_speed(_rotate_fwd, hover_fps)

	_rotate_rev = _rotate_fwd + "_rev"
	if !sf.has_animation(_rotate_rev):
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

func _on_anim_finished() -> void:
	var sf := sprite.sprite_frames
	if sprite.animation == _rotate_fwd and sf.has_animation(_rotate_rev):
		if flip_on_reverse:
			sprite.flip_h = !sprite.flip_h
		sprite.animation = _rotate_rev
		sprite.play()
		return

	if sprite.animation == _rotate_rev:
		if _focus_active:
			if flip_on_reverse:
				sprite.flip_h = !sprite.flip_h
			sprite.animation = _rotate_fwd
			sprite.play()
		else:
			sprite.flip_h = idle_flip_h
			_play_idle()

func _shader_has_param(sm: ShaderMaterial, pname: String) -> bool:
	if sm == null:
		return false
	var sh := sm.shader
	if sh == null:
		return false
	for u in sh.get_shader_uniform_list():
		if u.has("name"):
			if String(u["name"]) == pname:
				return true
	return false

func _ensure_yoshi_shader() -> void:
	if sprite == null:
		return

	# Get or create a unique ShaderMaterial
	var sm: ShaderMaterial = null
	var mat := sprite.material
	if mat != null and mat is ShaderMaterial:
		sm = mat as ShaderMaterial
		if not sm.resource_local_to_scene:
			var dupe := sm.duplicate(true) as ShaderMaterial
			dupe.resource_local_to_scene = true
			sprite.material = dupe
			sm = dupe
	else:
		sm = ShaderMaterial.new()
		sm.resource_local_to_scene = true
		sprite.material = sm

	# Ensure it is the Yoshi shader (has target_color/src_hue)
	var need_shader := true
	if sm.shader != null:
		var has_target := _shader_has_param(sm, "target_color")
		var has_src    := _shader_has_param(sm, "src_hue")
		if has_target and has_src:
			need_shader = false

	if need_shader and ResourceLoader.exists(yoshi_shader_path):
		var sh := load(yoshi_shader_path) as Shader
		if sh != null:
			sm.shader = sh

	# Avoid stacking multiply-tint on the texture
	sprite.modulate = Color(1, 1, 1, 1)

func _apply_tint_to_shader() -> void:
	if name_label:
		name_label.remove_theme_color_override("font_color")
		name_label.add_theme_color_override("font_color", Color.WHITE)

	var sm: ShaderMaterial = null
	if sprite != null and sprite.material != null and sprite.material is ShaderMaterial:
		sm = sprite.material as ShaderMaterial

	# If we have the right shader, set its params
	if sm != null and _shader_has_param(sm, "target_color"):
		sm.set_shader_parameter("target_color", tint_color)
		sm.set_shader_parameter("src_hue",     yoshi_source_hue)
		sm.set_shader_parameter("hue_tol",     yoshi_tolerance)
		sm.set_shader_parameter("edge_soft",   yoshi_edge_soft)
	else:
		# Fallback (shouldn't happen after _ensure_yoshi_shader), but keep it safe
		if sprite != null:
			sprite.modulate = tint_color

# Manual override (kept for flexibility)
func set_tint_color(c: Color) -> void:
	tint_color = c
	_apply_tint_to_shader()

func _on_pressed() -> void:
	pass
