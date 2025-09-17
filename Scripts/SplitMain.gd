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

# SplitMain.gd
func _spawn_worlds(two_players: bool) -> void:
	var packed := load(main_world_scene) as PackedScene
	assert(packed != null)

	# Always normalize device mapping we want
	Engine.set_meta("p1_device", 0)
	Engine.set_meta("p2_device", 1)

	if not two_players:
		if _divider: _divider.visible = false
		_right_vc.visible = false

		var w1 := packed.instantiate()
		if w1.has_method("set_player_slot"):
			w1.call("set_player_slot", 1)   # <- P1 slot BEFORE add_child
		_left_sv.add_child(w1)
		return

	# 2P
	if _divider: _divider.visible = true
	_right_vc.visible = true

	var wL := packed.instantiate()
	var wR := packed.instantiate()

	# Tell each world its slot BEFORE they enter the tree
	if wL.has_method("set_player_slot"):
		wL.call("set_player_slot", 1)     # -> pad 0
	if wR.has_method("set_player_slot"):
		wR.call("set_player_slot", 2)     # -> pad 1

	_left_sv.add_child(wL)
	_right_sv.add_child(wR)

func _configure_world_player_slot(world_root: Node, slot: int, device_id: int) -> void:
	# Preferred: tell the World instance the slot (if it has it)
	if world_root.has_method("set_player_slot"):
		world_root.call_deferred("set_player_slot", slot)

	# Set the player's device per instance
	var player := world_root.find_child("Player", true, false)
	if player != null:
		if player.has_method("SetPlayerIndex"):
			player.call_deferred("SetPlayerIndex", slot)
		if player.has_method("SetInputDevice"):
			player.call_deferred("SetInputDevice", device_id)

	# Pass device to systems that need it (Map/SpriteHandler)
	var map := world_root.find_child("Map", true, false)
	if map != null and map.has_method("SetPlayerDevice"):
		map.call("SetPlayerDevice", device_id)
	var sh := world_root.find_child("SpriteHandler", true, false)
	if sh != null and sh.has_method("SetPlayerDevice"):
		sh.call("SetPlayerDevice", device_id)

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
