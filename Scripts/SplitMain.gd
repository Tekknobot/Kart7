# res://Scenes/SplitMain.gd
extends Control

@export_file("*.tscn")
var main_world_scene: String = "res://Scenes/Main.tscn"

@export var show_divider: bool = true
@export var divider_color: Color = Color(1, 1, 1, 0.15)

var _left_vc: SubViewportContainer
var _right_vc: SubViewportContainer
var _left_sv: SubViewport
var _right_sv: SubViewport
var _divider: ColorRect

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_split_ui()

	var two_p: bool = false
	if Engine.has_meta("two_player_mode"):
		two_p = bool(Engine.get_meta("two_player_mode"))
	elif Engine.has_meta("player_count"):
		var pc: int = int(Engine.get_meta("player_count"))
		two_p = pc >= 2

	_spawn_worlds(two_p)

	if not is_connected("resized", Callable(self, "_on_resized")):
		connect("resized", Callable(self, "_on_resized"))
	_on_resized()

func _build_split_ui() -> void:
	var split := HBoxContainer.new()
	split.name = "Split"
	split.anchor_right = 1.0
	split.anchor_bottom = 1.0
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 0)
	add_child(split)

	_left_vc = SubViewportContainer.new()
	_left_vc.name = "Left"
	_left_vc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_vc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_child(_left_vc)

	_left_sv = SubViewport.new()
	_left_sv.name = "SV_Left"
	# FIX: use render_target_update_mode and Viewport enum
	_left_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_left_sv.gui_disable_input = false
	_left_vc.add_child(_left_sv)   # no need to assign .subviewport

	if show_divider:
		_divider = ColorRect.new()
		_divider.name = "Divider"
		_divider.color = divider_color
		_divider.custom_minimum_size = Vector2(2, 0) # thin vertical line
		_divider.size_flags_vertical = Control.SIZE_EXPAND_FILL
		split.add_child(_divider)

	_right_vc = SubViewportContainer.new()
	_right_vc.name = "Right"
	_right_vc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_vc.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	split.add_child(_right_vc)

	_right_sv = SubViewport.new()
	_right_sv.name = "SV_Right"
	# FIX: same here
	_right_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_right_sv.gui_disable_input = false
	_right_vc.add_child(_right_sv)

func _spawn_worlds(two_players: bool) -> void:
	var packed := load(main_world_scene) as PackedScene
	assert(packed != null, "SplitMain: set main_world_scene to your Main scene (.tscn).")

	# Read device hints (if present)
	var p1_dev: int = -1
	if Engine.has_meta("p1_device"):
		p1_dev = int(Engine.get_meta("p1_device"))
	var p2_dev: int = 0
	if Engine.has_meta("p2_device"):
		p2_dev = int(Engine.get_meta("p2_device"))

	if not two_players:
		_right_vc.visible = false
		if _divider != null:
			_divider.visible = false

		var w1: Node = packed.instantiate()
		# >>> IMPORTANT: set slot/device BEFORE add_child, so _ready() sees them
		if w1.has_method("set_player_slot"):
			w1.set_player_slot(1)
		if w1.has_method("set_input_device"):
			w1.set_input_device(p1_dev)

		_left_sv.add_child(w1)
		return

	# 2P
	_right_vc.visible = true
	if _divider != null:
		_divider.visible = show_divider

	var w_left: Node  = packed.instantiate()
	var w_right: Node = packed.instantiate()

	# >>> set slot/device BEFORE add_child
	if w_left.has_method("set_player_slot"):
		w_left.set_player_slot(1)
	if w_left.has_method("set_input_device"):
		w_left.set_input_device(p1_dev)

	if w_right.has_method("set_player_slot"):
		w_right.set_player_slot(2)
	if w_right.has_method("set_input_device"):
		w_right.set_input_device(p2_dev)

	_left_sv.add_child(w_left)
	_right_sv.add_child(w_right)

func _configure_world_player_slot(world_root: Node, slot: int, device_id: int) -> void:
	if world_root.has_method("set_player_slot"):
		world_root.call_deferred("set_player_slot", slot)
	if world_root.has_method("set_input_device"):
		world_root.call_deferred("set_input_device", device_id)

	# Try to find a Player node and pass along too (safe if absent)
	var player: Node = world_root.find_child("Player", true, false)
	if player != null:
		if player.has_method("SetPlayerIndex"):
			player.call_deferred("SetPlayerIndex", slot)
		if player.has_method("SetInputDevice"):
			player.call_deferred("SetInputDevice", device_id)

func _on_resized() -> void:
	var sz: Vector2 = get_viewport_rect().size
	var two_players: bool = _right_vc.visible

	if not two_players:
		_left_sv.size = Vector2i(int(sz.x), int(sz.y))
		return

	var half_w: int = int(sz.x / 2.0)
	var h: int = int(sz.y)
	_left_sv.size  = Vector2i(half_w, h)
	_right_sv.size = Vector2i(half_w, h)
