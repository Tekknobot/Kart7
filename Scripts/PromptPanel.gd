extends Node2D
class_name PromptPanel

signal continue_pressed
signal retry_pressed
signal quit_pressed

# Actions: set true to make this panel perform the actions directly
@export var handle_actions_locally := true

# Text
@export var title_text := "Race Complete"
@export var subtitle_text := "Nice driving! What’s next?"

# Styling (outlines + optional shadow)
@export var outline_color: Color = Color(0, 0, 0, 1.0)
@export var outline_size: int = 2
@export var use_shadow: bool = true
@export var shadow_color: Color = Color(0, 0, 0, 0.6)
@export var shadow_offset: Vector2i = Vector2i(2, 2)

# Optional fonts
@export var title_font: Font
@export var title_font_size: int = 28
@export var subtitle_font: Font
@export var subtitle_font_size: int = 18
@export var button_font: Font
@export var button_font_size: int = 18
@export var subtitle_color: Color = Color(1, 1, 1, 0.85)

# Node paths (use these names or change paths to match your prefab)
@export var title_node_path: NodePath = ^"Title"
@export var subtitle_node_path: NodePath = ^"Subtitle"
@export var continue_btn_path: NodePath = ^"ContinueBtn"
@export var retry_btn_path: NodePath = ^"RetryBtn"
@export var quit_btn_path: NodePath = ^"QuitBtn"

@export var show_on_ready := false

# Internals
var _title_lbl: Label
var _subtitle_lbl: Label
var _btn_continue: Button
var _btn_retry: Button
var _btn_quit: Button

# Rooted UI we might build
var _layer: CanvasLayer
var _ui_root: Control

@export var button_height: int = 56
@export var enforce_exact_button_height := true

@export var reload_scene_path: String = ""     # optional: set to your scene file path
@export var reload_scene_packed: PackedScene   # optional: drag the scene here

@export var ignore_input_until_ms := 400
var _opened_at_ms := 0

func _ready() -> void:
	set_process_unhandled_input(true)  # for JOY A
	call_deferred("_deferred_init")
		
func _deferred_init() -> void:
	# Locate existing nodes
	_title_lbl = get_node_or_null(title_node_path) as Label
	_subtitle_lbl = get_node_or_null(subtitle_node_path) as Label
	_btn_continue = get_node_or_null(continue_btn_path) as Button
	_btn_retry = get_node_or_null(retry_btn_path) as Button
	_btn_quit = get_node_or_null(quit_btn_path) as Button

	var need_build := false
	if _title_lbl == null:
		need_build = true
	if _subtitle_lbl == null:
		need_build = true
	if _btn_continue == null:
		need_build = true
	if _btn_retry == null:
		need_build = true
	if _btn_quit == null:
		need_build = true

	if need_build:
		_build_ui_runtime()
		# rebind after building
		_title_lbl = get_node_or_null(title_node_path) as Label
		_subtitle_lbl = get_node_or_null(subtitle_node_path) as Label
		_btn_continue = get_node_or_null(continue_btn_path) as Button
		_btn_retry = get_node_or_null(retry_btn_path) as Button
		_btn_quit = get_node_or_null(quit_btn_path) as Button

	# wire signals
	if _btn_continue != null:
		_btn_continue.pressed.connect(_on_continue)
	if _btn_retry != null:
		_btn_retry.pressed.connect(_on_retry)
	if _btn_quit != null:
		_btn_quit.pressed.connect(_on_quit)

	# apply initial texts
	if _title_lbl != null:
		_title_lbl.text = title_text
	if _subtitle_lbl != null:
		_subtitle_lbl.text = subtitle_text

	# wait one frame so theme/UI are fully ready (export-safe)
	await get_tree().process_frame

	# guard again then style
	if is_instance_valid(_title_lbl) and is_instance_valid(_subtitle_lbl):
		_apply_fonts()
		_apply_text_effects(self)

	_set_controls_alpha(0.0)
	visible = true
	if show_on_ready:
		show_prompt()

func show_prompt() -> void:
	_opened_at_ms = Time.get_ticks_msec()
	visible = true
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_control(_title_lbl, 1.0, 0.2, tw)
	_fade_control(_subtitle_lbl, 1.0, 0.2, tw)
	_fade_control(_btn_continue, 1.0, 0.2, tw)
	_fade_control(_btn_retry, 1.0, 0.2, tw)
	_fade_control(_btn_quit, 1.0, 0.2, tw)
	if _btn_continue != null:
		_btn_continue.grab_focus()

func hide_prompt() -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_fade_control(_title_lbl, 0.0, 0.15, tw)
	_fade_control(_subtitle_lbl, 0.0, 0.15, tw)
	_fade_control(_btn_continue, 0.0, 0.15, tw)
	_fade_control(_btn_retry, 0.0, 0.15, tw)
	_fade_control(_btn_quit, 0.0, 0.15, tw)
	tw.finished.connect(func():
		visible = false
	)

# ---------- RUNTIME UI BUILD ----------
func _build_ui_runtime() -> void:
	print("[PromptPanel] Building runtime UI (CanvasLayer + Panel + Buttons).")

	_layer = CanvasLayer.new()
	add_child(_layer)

	_ui_root = Control.new()
	_ui_root.name = "PromptUIRoot"
	_ui_root.anchors_preset = Control.PRESET_FULL_RECT
	_ui_root.anchor_right = 1.0
	_ui_root.anchor_bottom = 1.0
	_ui_root.mouse_filter = Control.MOUSE_FILTER_STOP   # capture UI clicks
	_layer.add_child(_ui_root)

	# Backdrop dimmer
	var dim := ColorRect.new()
	dim.name = "Dimmer"
	dim.color = Color(0, 0, 0, 0.5)
	dim.anchors_preset = Control.PRESET_FULL_RECT
	_ui_root.add_child(dim)

	# Centered panel
	var center := CenterContainer.new()
	center.name = "Centerer"
	center.anchor_left = 0.25
	center.anchor_right = 0.75
	center.anchor_top = 0.2
	center.anchor_bottom = 0.8
	_ui_root.add_child(center)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	var hbox := HBoxContainer.new()
	hbox.name = "Buttons"
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.custom_minimum_size.y = button_height
	vbox.add_child(hbox)

	var b_continue := Button.new()
	b_continue.name = "ContinueBtn"
	b_continue.text = "Continue"
	b_continue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_continue.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(b_continue, Color(0.0, 0.7, 0.0))  # green
	hbox.add_child(b_continue)

	var b_retry := Button.new()
	b_retry.name = "RetryBtn"
	b_retry.text = "Retry"
	b_retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_retry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(b_retry, Color(0.85, 0.55, 0.0))  # amber/orange
	hbox.add_child(b_retry)

	var b_quit := Button.new()
	b_quit.name = "QuitBtn"
	b_quit.text = "Quit"
	b_quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(b_quit, Color(0.85, 0.0, 0.0))    # red
	hbox.add_child(b_quit)

	# Update exported paths so the rest of the script can find them
	title_node_path = NodePath(title.get_path())
	subtitle_node_path = NodePath(subtitle.get_path())
	continue_btn_path = NodePath(b_continue.get_path())
	retry_btn_path = NodePath(b_retry.get_path())
	quit_btn_path = NodePath(b_quit.get_path())

	# Extra guard: viewport might attach next frame on some exports
	if _layer.get_viewport() == null:
		push_warning("[PromptPanel] CanvasLayer has no viewport yet; UI will attach when available.")

func _style_button(btn: Button, base_color: Color) -> void:
	var hover_color := base_color.lightened(0.20)
	var pressed_color := base_color.darkened(0.20)
	var focus_color := base_color.lightened(0.35)

	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.custom_minimum_size = Vector2(0, button_height)

	var border_w := 2
	var pad_x := 16
	var pad_y := 6

	var target_font_size := button_font_size
	if enforce_exact_button_height:
		var usable_h = max(0, button_height - border_w * 2)
		target_font_size = min(button_font_size, max(6, usable_h - 2 * pad_y))
		var need := target_font_size + 2 * pad_y
		if need > usable_h:
			pad_y = max(0, (usable_h - target_font_size) / 2)

	var normal := StyleBoxFlat.new()
	normal.bg_color = base_color
	normal.corner_radius_top_left = 8
	normal.corner_radius_top_right = 8
	normal.corner_radius_bottom_left = 8
	normal.corner_radius_bottom_right = 8
	normal.content_margin_left = pad_x
	normal.content_margin_right = pad_x
	normal.content_margin_top = pad_y
	normal.content_margin_bottom = pad_y

	var hover := normal.duplicate()
	hover.bg_color = hover_color
	hover.corner_radius_top_left = 8
	hover.corner_radius_top_right = 8
	hover.corner_radius_bottom_left = 8
	hover.corner_radius_bottom_right = 8

	var pressed := normal.duplicate()
	pressed.bg_color = pressed_color
	pressed.corner_radius_top_left = 8
	pressed.corner_radius_top_right = 8
	pressed.corner_radius_bottom_left = 8
	pressed.corner_radius_bottom_right = 8

	var focus := normal.duplicate()
	focus.bg_color = focus_color
	focus.corner_radius_top_left = 8
	focus.corner_radius_top_right = 8
	focus.corner_radius_bottom_left = 8
	focus.corner_radius_bottom_right = 8
	focus.border_color = Color.WHITE
	focus.border_width_left = border_w
	focus.border_width_right = border_w
	focus.border_width_top = border_w
	focus.border_width_bottom = border_w
	focus.content_margin_left = pad_x
	focus.content_margin_right = pad_x
	focus.content_margin_top = pad_y
	focus.content_margin_bottom = pad_y

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus)

	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	if button_font != null:
		btn.add_theme_font_override("font", button_font)
	btn.add_theme_font_size_override("font_size", target_font_size)

# ---------- helpers ----------
func _fade_control(ctrl: Control, target_a: float, dur: float, tw: Tween) -> void:
	if ctrl == null:
		return
	var m := ctrl.modulate
	if m.a < 0.0:
		m.a = 0.0
	if m.a > 1.0:
		m.a = 1.0
	ctrl.modulate = m
	tw.tween_property(ctrl, "modulate:a", target_a, dur)

func _set_controls_alpha(a: float) -> void:
	if _title_lbl != null:
		_title_lbl.modulate.a = a
	if _subtitle_lbl != null:
		_subtitle_lbl.modulate.a = a
	if _btn_continue != null:
		_btn_continue.modulate.a = a
	if _btn_retry != null:
		_btn_retry.modulate.a = a
	if _btn_quit != null:
		_btn_quit.modulate.a = a

func _apply_fonts() -> void:
	if _title_lbl != null:
		if title_font != null:
			_title_lbl.add_theme_font_override("font", title_font)
		_title_lbl.add_theme_font_size_override("font_size", title_font_size)

	if _subtitle_lbl != null:
		if subtitle_font != null:
			_subtitle_lbl.add_theme_font_override("font", subtitle_font)
		_subtitle_lbl.add_theme_font_size_override("font_size", subtitle_font_size)
		_subtitle_lbl.add_theme_color_override("font_color", subtitle_color)

	if _btn_continue != null:
		if button_font != null:
			_btn_continue.add_theme_font_override("font", button_font)
		_btn_continue.add_theme_font_size_override("font_size", button_font_size)
	if _btn_retry != null:
		if button_font != null:
			_btn_retry.add_theme_font_override("font", button_font)
		_btn_retry.add_theme_font_size_override("font_size", button_font_size)
	if _btn_quit != null:
		if button_font != null:
			_btn_quit.add_theme_font_override("font", button_font)
		_btn_quit.add_theme_font_size_override("font_size", button_font_size)

func _apply_text_effects(root: Node) -> void:
	if root is Label or root is Button or root is RichTextLabel:
		var c := root as Control
		c.add_theme_color_override("font_outline_color", outline_color)
		c.add_theme_constant_override("outline_size", outline_size)
		if use_shadow:
			c.add_theme_color_override("font_shadow_color", shadow_color)
			c.add_theme_constant_override("shadow_offset_x", shadow_offset.x)
			c.add_theme_constant_override("shadow_offset_y", shadow_offset.y)
	for child in root.get_children():
		_apply_text_effects(child)

# --- Button callbacks (emit + optional local handling) ---
func _on_continue() -> void:
	emit_signal("continue_pressed")
	if handle_actions_locally:
		_restart_scene_safe()

func _on_retry() -> void:
	emit_signal("retry_pressed")
	if handle_actions_locally:
		_restart_scene_safe()

func _on_quit() -> void:
	emit_signal("quit_pressed")
	if handle_actions_locally:
		get_tree().quit()

# --- Exact JOYPAD A (south) support ---
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# ignore accidental pulses briefly after opening
	var now_ms := Time.get_ticks_msec()
	if now_ms - _opened_at_ms < ignore_input_until_ms:
		return

	# explicit Joypad A (south) → activate focused button
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner != null and focus_owner is Button:
			focus_owner.emit_signal("pressed")
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


# --- Safe scene reload that works even if current scene has no file path ---
@export var allow_pack_fallback := false  # set true only if you really need it

func _restart_scene_safe() -> void:
	var st := get_tree()
	if st == null:
		push_warning("[PromptPanel] No SceneTree; cannot reload.")
		return

	# 1) Explicit path (recommended)
	if reload_scene_path != "":
		if not FileAccess.file_exists(reload_scene_path):
			push_warning("[PromptPanel] reload_scene_path not found in PCK: " + reload_scene_path)
		var e0 := st.change_scene_to_file(reload_scene_path)
		if e0 != OK:
			push_warning("[PromptPanel] change_scene_to_file(reload_scene_path) failed: " + str(e0))
		return

	# 2) Packed scene provided in Inspector
	if reload_scene_packed != null:
		st.change_scene_to_packed(reload_scene_packed)
		return

	# 3) Current scene’s own file path (if it has one)
	var cs := st.current_scene
	if cs != null:
		var p := cs.scene_file_path
		if p != "":
			var e1 := st.change_scene_to_file(p)
			if e1 != OK:
				push_warning("[PromptPanel] change_scene_to_file(current) failed: " + str(e1))
			return

	# 4) Optional last resort (disabled by default)
	if allow_pack_fallback and cs != null:
		var ps := PackedScene.new()
		if ps.pack(cs):
			st.change_scene_to_packed(ps)
			return

	push_warning("[PromptPanel] Reload failed: set reload_scene_path or reload_scene_packed.")
