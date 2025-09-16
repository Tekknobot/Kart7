extends Node2D

var _roster_ready := false
var _map_ready := false

@export var _map : Node2D
@export var _collision : Node
var _player: Racer = null
@export var _spriteHandler : Node2D
@export var _animationHandler : Node
@export var _backgroundElements : Node2D

# NEW: RaceManager
@export var _raceManager : RaceManager

var _player_freeze_frames := 0
@onready var _smoother := preload("res://addons/FrameSmoother.gd").new()

@onready var _player_script   := preload("res://Scripts/World Elements/Racers/Player.gd")
@onready var _opponent_script := preload("res://Scripts/World Elements/Racers/Opponent.gd")

@export var racers_root_path: NodePath           # e.g. "Sprite Handler/Racers"
@export var spawn_points_path: NodePath          # Node2D whose children are your grid spots (P1..P8)
@export var player_scene: PackedScene            # Player prefab (tscn)
@export var opponent_scene: PackedScene          # Opponent prefab (tscn)

# Yoshi recolor shader for sprites
@export_file("*.gdshader") var yoshi_shader_path: String = "res://Scripts/Shaders/YoshiSwap.gdshader"
@export var src_hue: float   = 0.97
@export var hue_tol: float   = 0.045
@export var edge_soft: float = 0.20

# Priming sheet (avoid 1-frame flash)
@export var prime_hframes: bool = true
@export var sheet_hframes: int  = 12

var _locked_city := ""      # lock the city once
var _track_applied := false # prevent re-applying after first success

var DEFAULT_POINTS: PackedVector2Array = PackedVector2Array([
	Vector2(920, 584),
	Vector2(950, 607),
	Vector2(920, 631),
	Vector2(950, 655),
	Vector2(920, 679),
	Vector2(950, 703),
	Vector2(920, 727),
	Vector2(950, 751)
])

var _player_slot: int = 1            # 1 = P1, 2 = P2 (set by SplitMain)
var _selected_local: String = ""      # this instance’s chosen racer name

func set_player_slot(slot: int) -> void:
	_player_slot = slot
	if _player_slot < 1:
		_player_slot = 1

func _input(event):
	if event.is_action_pressed("ui_fullscreen"):
		if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			# Exact 4K fullscreen; change if you prefer 1920x1080.
			DisplayServer.window_set_size(Vector2i(3840, 2160))
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_character_selection() -> void:
	_ensure_roster_spawned()

func _ensure_roster_spawned() -> void:
	var racers_root := get_node_or_null(racers_root_path)
	if racers_root == null:
		racers_root = get_node_or_null(^"Sprite Handler/Racers")
	if racers_root == null:
		push_error("World: Racers root not found; set racers_root_path.")
		return

	# Already spawned? bail
	var existing := 0
	for c in racers_root.get_children():
		if c is Node2D:
			existing += 1
	if existing >= Globals.racer_names.size():
		return

	# Need prefabs
	if player_scene == null or opponent_scene == null:
		push_error("World: assign player_scene and opponent_scene in the Inspector.")
		return

	# Build ordered names
	var all_names: Array = []
	for n in Globals.racer_names:
		all_names.append(String(n))

	# Per-screen player pick
	var selected := _selected_from_meta_or_globals(all_names)
	_selected_local = selected

	# Opponents = everyone else
	var remaining: Array = []
	for n in all_names:
		if n != selected:
			remaining.append(n)

	# Mirror into Globals only in 1P (avoid P1/P2 fighting in 2P)
	if not _is_two_player():
		if Globals.has_method("set_selected_racer"):
			Globals.set_selected_racer(selected)
			print("Picked:", Globals.selected_racer, " color:", Globals.selected_color)

	# === 1) Spawn opponents first ===
	for i in range(remaining.size()):
		var nm := String(remaining[i])
		var opp := opponent_scene.instantiate()
		opp.name = nm
		racers_root.add_child(opp)

		_wire_racer(opp, false)

		var ocol := Globals.get_racer_color(nm)
		_set_racer_name_label(opp, nm, ocol)
		var ospr := _find_sprite(opp)
		if ospr != null:
			_apply_yoshi_shader(ospr, ocol)

	# === 2) Spawn the player last ===
	var p := player_scene.instantiate()
	p.name = selected
	racers_root.add_child(p)
	_wire_racer(p, true)
	_player = p

	# Optional: pass slot/device to the Player if supported
	var dev_key := "p1_device"
	if _player_slot != 1:
		dev_key = "p2_device"
	var device_id := -1
	if Engine.has_meta(dev_key):
		device_id = int(Engine.get_meta(dev_key))
	if _player.has_method("SetPlayerIndex"):
		_player.call_deferred("SetPlayerIndex", _player_slot)
	if _player.has_method("SetInputDevice"):
		_player.call_deferred("SetInputDevice", device_id)

	# Local tint immediately (don’t depend on shared Globals color)
	var pcol := Globals.get_racer_color(selected)
	var pspr := _find_sprite(_player)
	if pspr != null:
		_apply_yoshi_shader(pspr, pcol)

	# Avoid pulling shared palette in 2P
	if not _is_two_player() and _player.has_method("RefreshPaletteFromGlobals"):
		_player.RefreshPaletteFromGlobals()
	else:
		if _player.has_method("_ensure_yoshi_material"): _player._ensure_yoshi_material()
		if _player.has_method("_apply_player_palette_from_globals"): _player._apply_player_palette_from_globals()

	# HUD hook
	var hud := get_node_or_null(^"RaceHUD")
	if hud:
		hud.set("player_path", hud.get_path_to(_player))
		hud.set("_player", _player)

	# Opponents know the player
	_bind_player_ref_to_opponents(racers_root, _player)

	# Keep Globals in sync in 1P only
	if not _is_two_player() and Globals.has_method("set_selected_racer"):
		Globals.set_selected_racer(selected)

	_update_hud_name_color()
	call_deferred("_reapply_player_color_once")

func _bind_player_ref_to_opponents(racers_root: Node, player: Node) -> void:
	if racers_root == null or player == null:
		return
	for n in racers_root.get_children():
		if n == player:
			continue
		if _has_prop(n, "player_ref"):
			n.set("player_ref", n.get_path_to(player))

func _has_prop(obj: Object, prop: StringName) -> bool:
	for p in obj.get_property_list():
		if p.has("name") and p["name"] == prop:
			return true
	return false

func _retarget_player_paths(node: Node, player: Node) -> void:
	# Recursively set `player_path` export where present
	for child in node.get_children():
		var props := child.get_property_list()
		for p in props:
			if p.has("name") and p["name"] == "player_path":
				child.set("player_path", child.get_path_to(player))
				break
		_retarget_player_paths(child, player)

func _process(delta: float) -> void:
	if not _roster_ready or not _map_ready:
		return

	var dt := _smoother.smooth_delta(delta)

	_map.Update(_player)
	if _player_freeze_frames > 0:
		_player_freeze_frames -= 1
	else:
		_player.Update(_map.ReturnForward())

	_spriteHandler.Update(_map.ReturnWorldMatrix())
	_animationHandler.Update()
	_backgroundElements.Update(_map.ReturnMapRotation())

	if is_instance_valid(_raceManager):
		_raceManager.Update()

func _ready() -> void:
	var first := _read_selected_city_any_source()
	if first != "" and first.to_lower() != "main":
		_locked_city = first
		if Engine.has_meta("selected_city_override"):
			Engine.remove_meta("selected_city_override")
		print("[World] locked city -> ", _locked_city)

	_apply_character_selection()
	# (keep the rest of your existing _ready() as-is)
	await _await_roster_and_boot()
	
	if _map == null or _player == null:
		push_error("World: _map or _player is null.")
		return
	if not _map is Sprite2D:
		push_error("World: _map is not a Sprite2D (Pseudo3D.gd).")
		return
	if (_map as Sprite2D).texture == null:
		push_error("World: _map Sprite2D has no texture.")
		return
		
	call_deferred("_finalize_ai_grid_spawn")	

func _await_roster_and_boot() -> void:
	var racers_root := get_node_or_null(^"Sprite Handler/Racers")
	var tries := 0
	while racers_root == null and tries < 360:
		await get_tree().process_frame
		racers_root = get_node_or_null(^"Sprite Handler/Racers")
		tries += 1
	if racers_root == null:
		push_error("World: Racers root never appeared.")
		return

	# Find the local player's node by our local name (fallback to Globals)
	var chosen_name := _selected_local
	if chosen_name == "":
		chosen_name = String(Globals.selected_racer)

	var candidate: Node = null
	tries = 0
	while tries < 360:
		candidate = null
		for c in racers_root.get_children():
			if c is Node2D and c.name == chosen_name:
				candidate = c
				break
		if candidate != null:
			break
		await get_tree().process_frame
		tries += 1

	if candidate == null:
		push_error("World: chosen racer node not found: " + chosen_name)
		return

	_player = candidate
	_wire_player_dependencies()

	# Palette sync: avoid shared pull in 2P
	if not _is_two_player() and _player.has_method("RefreshPaletteFromGlobals"):
		_player.RefreshPaletteFromGlobals()
	else:
		if _player.has_method("_ensure_yoshi_material"): _player._ensure_yoshi_material()
		if _player.has_method("_apply_player_palette_from_globals"): _player._apply_player_palette_from_globals()

	# Retarget only within this world’s subtree
	_retarget_player_paths(self, _player)

	var hud := get_node_or_null(^"RaceHUD")
	if hud:
		hud.set("player_path", hud.get_path_to(_player))
		hud.set("_player", _player)

	_roster_ready = true
	_setup_after_roster()
	call_deferred("_reapply_player_color_once")

func _setup_after_roster() -> void:
	if _map == null or _player == null:
		push_error("World: _map or _player is null.")
		return
	if not (_map is Sprite2D):
		push_error("World: _map is not a Sprite2D (Pseudo3D.gd).")
		return
	if (_map as Sprite2D).texture == null:
		push_error("World: _map Sprite2D has no texture.")
		return

	# Boot map + systems
	_map.Setup(Globals.screenSize, _player)

	# Path overlay ↔ map binding
	var overlay_node := get_node(^"SubViewport/PathOverlay2D")
	var overlay_vp   := get_node(^"SubViewport") as SubViewport
	var rel_from_map := _map.get_path_to(overlay_node)
	if _map != null and _map.has_method("SetPathOverlayNodePath"):
		_map.call("SetPathOverlayNodePath", rel_from_map, overlay_vp)

	# Minimap (local subtree only)
	var rr := get_node_or_null(racers_root_path)
	if rr == null:
		rr = get_node_or_null(^"Sprite Handler/Racers")
	var minimap := find_child("Minimap", true, false)
	if minimap != null:
		if minimap.has_method("Bind"):
			minimap.call("Bind", _player, rr, overlay_node)
		if minimap.has_method("mark_path_dirty"):
			minimap.call("mark_path_dirty")

	# Skid overlay paths
	if overlay_node:
		overlay_node.set("player_path", overlay_node.get_path_to(_player))
		overlay_node.set("pseudo3d_path", overlay_node.get_path_to(_map))

	# Opponents registration
	if _map != null and _map.has_method("SetOpponentsFromGroup"):
		_map.call("SetOpponentsFromGroup", "racers", _player)

	# Track/visuals
	_apply_track_from_globals()

	# Collision boot
	if _collision != null and _collision.has_method("Setup"):
		_collision.call("Setup")

	# Shared time-of-day between screens
	_sync_time_of_day()

	# Subsystems
	_player.Setup((_map as Sprite2D).texture.get_size().x)
	_spriteHandler.Setup(_map.ReturnWorldMatrix(), (_map as Sprite2D).texture.get_size().x, _player)
	_animationHandler.Setup(_player)

	if is_instance_valid(_raceManager):
		_raceManager.Setup()
		_raceManager.connect("standings_changed", Callable(self, "_on_standings_changed"))

	call_deferred("_push_path_points_once")
	call_deferred("_spawn_player_at_path_index", 1)

	_refresh_map_opponents()

	if _map != null and _map.has_method("SetOpponentsFromGroup"):
		_map.call("SetOpponentsFromGroup", "racers", _player)

	call_deferred("_finalize_ai_grid_spawn")

	_update_hud_name_color()
	_map_ready = true

func _sync_time_of_day() -> void:
	if _backgroundElements == null:
		return

	# Use a shared meta so both screens match.
	var mode: int = -1
	if Engine.has_meta("tod_mode"):
		mode = int(Engine.get_meta("tod_mode"))
	else:
		# Read current setting from this world’s BackgroundEffects
		var cur := 1
		if _backgroundElements.has_method("get"):
			var v = _backgroundElements.get("time_of_day")
			if typeof(v) == TYPE_INT:
				cur = int(v)
		mode = cur
		Engine.set_meta("tod_mode", mode)

	# Apply to this world
	if _backgroundElements.has_method("SetTimeOfDay"):
		_backgroundElements.call("SetTimeOfDay", mode)
	else:
		# Fallback: set the exported property
		if _backgroundElements.has_method("set"):
			_backgroundElements.set("time_of_day", mode)

# Wait a couple frames so path points / overlay are pushed, then place AI.
func _finalize_ai_grid_spawn() -> void:
	if get_tree() == null or not is_inside_tree():
		call_deferred("_finalize_ai_grid_spawn")
		return
		
	_place_grid_player_last()

	if _map != null and _map.has_method("SetOpponentsFromGroup"):
		_map.call("SetOpponentsFromGroup", "racers", _player)
		
	_update_hud_name_color()	
	call_deferred("_attach_skids_to_opponents") 
	
# Place every Opponent child at Opponent.DEFAULT_POINTS[i] (pixels).
func _place_opponents_from_defaults_post() -> void:
	var racers_root := get_node_or_null(racers_root_path)
	if racers_root == null:
		racers_root = get_node_or_null(^"Sprite Handler/Racers")
	if racers_root == null:
		return

	if DEFAULT_POINTS.size() < 2:
		return

	# If you prefer a glide-into-path (like ArmMergeFromGrid), we need a UV scale.
	# Using the map texture width is a good default (your project uses 1024).
	var scale_px := 1024.0
	if _map is Sprite2D and (_map as Sprite2D).texture != null:
		scale_px = float((_map as Sprite2D).texture.get_size().x)

	var opp_index := 1  # start AFTER the player's slot (0)
	for n in racers_root.get_children():
		if n == _player:
			continue

		if opp_index >= DEFAULT_POINTS.size():
			break

		var px: Vector2 = DEFAULT_POINTS[opp_index]

		# Prefer a smooth, pre-GO hold -> path merge if the AI exposes it:
		var used_merge := false
		if n.has_method("ArmMergeFromGrid"):
			var uv := px / scale_px
			# path_idx = 0, lane_px = 0.0; adjust if you want per-row lanes
			n.call("ArmMergeFromGrid", uv, 0, 0.0)
			used_merge = true

		# Fallback: hard place in map pixels
		if not used_merge and n.has_method("SetMapPosition"):
			n.call("SetMapPosition", Vector3(px.x, 0.0, px.y))

		# Make sure each opponent knows who the player is (for catch-up/depth)
		if _player != null and _has_prop(n, "player_ref"):
			n.set("player_ref", n.get_path_to(_player))

		opp_index += 1

func _on_standings_changed(board: Array) -> void:
	# example: print leader name and lap
	if board.size() > 0:
		var lead = board[0]
		#print("P1:", lead["node"].name, "lap", lead["lap"])
		pass

func _sort_by_name(a: Node, b: Node) -> bool:
	return a.name < b.name

func _set_identity(racer: Node, name_str: String) -> void:
	racer.name = name_str
	if racer.has_meta("racer_name"):
		racer.set("racer_name", StringName(name_str))
	if racer.has_method("SetDisplayName"):
		racer.call("SetDisplayName", name_str)
	# Put everyone in groups most systems expect
	racer.add_to_group("racers")
	racer.add_to_group("kart")

func _place_at(racer: Node, parent: Node, spots: Array, index: int) -> void:
	parent.add_child(racer)
	if racer is Node2D:
		var r2d := racer as Node2D
		var pos := Vector2.ZERO
		var rot := 0.0
		if index >= 0 and index < spots.size():
			var mk := spots[index] as Node2D
			pos = mk.global_position
			rot = mk.global_rotation
		r2d.global_position = pos
		r2d.global_rotation = rot

func _apply_color_to_racer(racer: Node, col: Color, out_sprites: Array) -> void:
	var spr := _find_sprite(racer)
	if spr == null:
		return

	# Hide until primed (no sheet flash)
	if spr is CanvasItem:
		(spr as CanvasItem).visible = false

	_prime_sprite_grid(spr)
	_apply_yoshi_shader(spr, col)
	out_sprites.append(spr)

func _find_sprite(root: Node) -> CanvasItem:
	if root == null:
		return null

	# 1) If the racer knows its render sprite, use that.
	if root.has_method("ReturnSpriteGraphic"):
		var s = root.call("ReturnSpriteGraphic")
		if s is CanvasItem:
			return s

	# 2) Prefer explicit known paths in your prefab.
	var n := root.get_node_or_null(^"GFX2/AngleSprite")
	if n is CanvasItem:
		return n
	n = root.get_node_or_null(^"GFX/AngleSprite")
	if n is CanvasItem:
		return n

	# 3) Any child actually named "AngleSprite".
	n = root.find_child("AngleSprite", true, false)
	if n is CanvasItem:
		return n

	# 4) Fallback: first AnimatedSprite2D/Sprite2D that isn't a wheel/effect.
	var stack := [root]
	while stack.size() > 0:
		var cur = stack.pop_back()
		for c in cur.get_children():
			if not (c is Node):
				continue
			var nm := ""
			if "name" in c:
				nm = c.name
			var skip := false
			if nm.findn("Wheel") >= 0:
				skip = true
			if nm.findn("Effect") >= 0:
				skip = true
			if not skip and (c is AnimatedSprite2D or c is Sprite2D):
				return c as CanvasItem
			stack.push_back(c)

	return null


func _prime_sprite_grid(spr: Node) -> void:
	if not prime_hframes:
		return
	if spr is Sprite2D:
		var s := spr as Sprite2D
		if sheet_hframes > 0:
			s.hframes = sheet_hframes
			s.vframes = 1
			s.frame = 0
			s.flip_h = false
	if spr is AnimatedSprite2D:
		var a := spr as AnimatedSprite2D
		if a.sprite_frames != null and a.sprite_frames.get_animation_names().size() > 0:
			if a.animation == "":
				a.animation = a.sprite_frames.get_animation_names()[0]
			a.frame = 0
			a.stop()

func _apply_yoshi_shader(spr: Node, _unused: Color) -> void:
	# 1) Resolve the exact color chosen for THIS slot
	var col := Color.WHITE
	if Globals.has_method("get_selected_color_for_slot"):
		col = Globals.get_selected_color_for_slot(_player_slot)
	if col == Color.WHITE or col.a == 0.0:
		# Fallback to name->color map using our local selected name
		var nm := _selected_local
		if nm == "":
			nm = String(Globals.selected_racer)
		col = Globals.get_racer_color(nm)

	# 2) Make it crisp (no blur)
	if spr is CanvasItem:
		(spr as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# If your racer is a container node, push to children too:
	for c in spr.get_children():
		if c is CanvasItem:
			(c as CanvasItem).texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	# 3) Apply shader (fallback to modulate if missing)
	if not ResourceLoader.exists(yoshi_shader_path):
		if spr is CanvasItem:
			(spr as CanvasItem).modulate = col
		return

	var sh := load(yoshi_shader_path) as Shader
	if sh == null:
		if spr is CanvasItem:
			(spr as CanvasItem).modulate = col
		return

	var sm := ShaderMaterial.new()
	sm.shader = sh
	sm.resource_local_to_scene = true

	sm.set_shader_parameter("target_color", col)
	sm.set_shader_parameter("src_hue",     src_hue)
	sm.set_shader_parameter("hue_tol",     hue_tol)
	sm.set_shader_parameter("edge_soft",   edge_soft)

	if spr is CanvasItem:
		(spr as CanvasItem).material = sm

func _set_nearest_filter_recursive(n: Node) -> void:
	# Godot 4: per-node filter override
	if n is CanvasItem:
		var ci := n as CanvasItem
		ci.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Visit children to catch nested sprites/animated sprites
	for c in n.get_children():
		if c is Node:
			_set_nearest_filter_recursive(c)

func _current_player_color() -> Color:
	# Prefer per-slot color from Globals if available
	if Globals.has_method("get_selected_color_for_slot"):
		return Globals.get_selected_color_for_slot(_player_slot)
	# Derive from the local selected name
	var nm := _selected_local
	if nm == "":
		nm = String(Globals.selected_racer)
	return Globals.get_racer_color(nm)

func _reapply_player_color_once() -> void:
	if _player == null:
		return
	var spr := _find_sprite(_player)
	if spr != null:
		_apply_yoshi_shader(spr, Color.WHITE)

func _wire_player_dependencies() -> void:
	if _player == null:
		return
	if _collision != null:
		if _player.has_method("SetCollisionHandler"):
			_player.call("SetCollisionHandler", _collision)
		elif _has_prop(_player, "_collisionHandler"):   # <-- use _has_prop, not has_meta
			_player.set("_collisionHandler", _collision)
	if _player.has_method("OnBecamePlayer"):
		_player.call_deferred("OnBecamePlayer")

func _refresh_map_opponents() -> void:
	if _map != null and _map.has_method("SetOpponentsFromGroup"):
		# Put everyone in group "racers" except the player into Pseudo3D’s list
		_map.call("SetOpponentsFromGroup", "racers", _player)

func _wire_racer(racer: Node, is_player: bool) -> void:
	# Give the racer the collision handler so IsCollidingWithWall/ReturnCurrentRoadType exist
	if _collision != null:
		if racer.has_method("SetCollisionHandler"):
			racer.call("SetCollisionHandler", _collision)
		elif _has_prop(racer, "_collisionHandler"):
			# only set if the property actually exists
			racer.set("_collisionHandler", _collision)

	# For opponents, pass a player ref if they expose it (so catchup/depth sort work)
	if not is_player and _player != null and _has_prop(racer, "player_ref"):
		racer.set("player_ref", racer.get_path_to(_player))

	# Let prefabs run any re-init hook after they become Player/Opponent
	if is_player:
		if racer.has_method("OnBecamePlayer"):
			racer.call_deferred("OnBecamePlayer")
	else:
		if racer.has_method("OnBecameOpponent"):
			racer.call_deferred("OnBecameOpponent")


# Places every Opponent child at Opponent.DEFAULT_POINTS[i] in pixel space.
# Uses the API your Opponent.gd already exposes.
func _place_opponents_from_defaults(racers_root: Node) -> void:
	var idx := 0
	for n in racers_root.get_children():
		if n == _player:
			continue
		# Hide sprite briefly to avoid a 1-frame sheet peek
		var spr := _find_sprite(n)
		if spr != null and spr is CanvasItem:
			(spr as CanvasItem).visible = false

		# Prefer the prefab API if present
		if n.has_method("ApplySpawnFromDefaultIndex"):
			n.call("ApplySpawnFromDefaultIndex", idx, 0.0)  # lane_px = 0.. tweak if you want rows
			# Optional: if you want the nice pre-GO hold → path merge, use ArmMergeFromGrid instead:
			# if n.has_method("ArmMergeFromGrid") and n.has_method("DefaultCount"):
			#   var cnt := int(n.call("DefaultCount"))
			#   var di := clamp(idx, 0, max(0, cnt - 1))
			#   var px := n.DEFAULT_POINTS[di]   # if you export it, or expose a getter
			#   var scale_px := 1024.0           # or n.call("_pos_scale_px")
			#   var uv := Vector2(px.x, px.y) / scale_px
			#   n.call("A

func _place_player_from_defaults() -> void:
	if _player == null:
		return
	if DEFAULT_POINTS.size() == 0:
		return

	var px: Vector2 = DEFAULT_POINTS[0]
	# Map space is pixels on X/Z
	if _player.has_method("SetMapPosition"):
		_player.call("SetMapPosition", Vector3(px.x, 0.0, px.y))

func _find_label_named(root: Node, wanted: String) -> Label:
	if root == null:
		return null
	if root is Label and root.name == wanted:
		return root
	for child in root.get_children():
		var got := _find_label_named(child, wanted)
		if got != null:
			return got
	return null

func _set_racer_name_label(racer: Node, label_text: String, col: Color) -> void:
	if racer == null:
		return
	# Set the node's name (used by RaceManager / leaderboard)
	racer.name = label_text
	# Update a child Label named "Name" if present
	var lbl := _find_label_named(racer, "Name")
	if lbl != null:
		lbl.text = label_text
		lbl.add_theme_color_override("font_color", col)

func _update_hud_name_color() -> void:
	var hud := get_node_or_null(^"RaceHUD")
	if hud == null:
		return

	var name_str := _selected_local
	if name_str == "":
		name_str = String(Globals.selected_racer)

	var col := Color.WHITE
	if Globals.has_method("get_selected_color_for_slot"):
		col = Globals.get_selected_color_for_slot(_player_slot)
	if col == Color.WHITE or col.a == 0.0:
		col = Globals.get_racer_color(name_str)

	var lbl := hud.get_node_or_null(^"Name")
	if lbl == null:
		lbl = _find_label_named(hud, "Name")
	if lbl != null:
		lbl.text = name_str.to_upper()
		lbl.add_theme_color_override("font_color", col)

func _attach_skids_to_opponents() -> void:
	var svp := get_node_or_null(^"SubViewport")
	var map := get_node_or_null(^"Map")
	var racers_root := get_node_or_null(^"Sprite Handler/Racers")
	if svp == null or map == null or racers_root == null:
		return

	# Clear any old painters
	for n in svp.get_children():
		if n.name.begins_with("Skids_"):
			n.queue_free()

	await get_tree().process_frame # ensure opponents exist in the tree

	for r in racers_root.get_children():
		if r == _player:
			continue
		var painter := Node2D.new()
		painter.name = "Skids_%s" % r.name
		painter.set_script(load("res://Scripts/SkidMarkPainter2D.gd"))
		svp.add_child(painter)

		# Wire relative paths now that it's in-tree
		painter.pseudo3d_path = painter.get_path_to(map)
		painter.player_path   = painter.get_path_to(r)

		# Tweak look (matches your PathOverlay2D tuning)
		painter.width_px = 0.6
		painter.min_segment_px = 1.0
		painter.draw_while_drifting = true
		painter.draw_while_offroad  = true

func _place_grid_player_last() -> void:
	var racers_root := get_node_or_null(racers_root_path)
	if racers_root == null:
		racers_root = get_node_or_null(^"Sprite Handler/Racers")
	if racers_root == null:
		return
	if DEFAULT_POINTS.size() == 0:
		return

	# UV scale for ArmMergeFromGrid (uses map texture width)
	var scale_px := 1024.0
	if _map is Sprite2D and (_map as Sprite2D).texture != null:
		scale_px = float((_map as Sprite2D).texture.get_size().x)

	# How many racers are in this race?
	var total := 0
	for n in racers_root.get_children():
		if n is Node2D:
			total += 1
	if total <= 0:
		return

	# >>> This is where _grid_index_for_player is called <<<
	var p_idx := _grid_index_for_player(total)

	# 1) Place opponents into all slots except p_idx
	var grid_cap = min(total, DEFAULT_POINTS.size())
	var opp_slot := 0
	for n in racers_root.get_children():
		if n == _player:
			continue
		while opp_slot == p_idx and opp_slot < grid_cap:
			opp_slot += 1
		if opp_slot >= grid_cap:
			break

		var px: Vector2 = DEFAULT_POINTS[opp_slot]
		var used_merge := false
		if n.has_method("ArmMergeFromGrid"):
			var uv := px / scale_px
			n.call("ArmMergeFromGrid", uv, 0, 0.0)
			used_merge = true
		if not used_merge and n.has_method("SetMapPosition"):
			n.call("SetMapPosition", Vector3(px.x, 0.0, px.y))

		if _player != null and _has_prop(n, "player_ref"):
			n.set("player_ref", n.get_path_to(_player))

		opp_slot += 1

	# 2) Put the PLAYER at their computed slot
	var ppx: Vector2 = DEFAULT_POINTS[p_idx]
	if _player != null and _player.has_method("SetMapPosition"):
		_player.call("SetMapPosition", Vector3(ppx.x, 0.0, ppx.y))

# --- Track loading ------------------------------------------------------------
func _apply_track_from_globals() -> void:
	# Already applied? Ignore re-entries and show who called us.
	if _track_applied:
		print("[World] _apply_track_from_globals() called again; ignoring")
		print_stack()
		return

	var name := _locked_city
	if name == "":
		name = _read_selected_city_any_source()
		# Treat "Main" as a default; use only if we truly have nothing else
		if name.to_lower() == "main":
			name = ""

		if name != "":
			_locked_city = name
			if Engine.has_meta("selected_city_override"):
				Engine.remove_meta("selected_city_override")

	print("[World] City:", name, " slug:", _slugify_city(name))

	if name == "":
		# keep your existing first_config/legacy fallback here...
		# (unchanged)
		# ...
		return

	_apply_track_by_name(name)

func _apply_track_by_name(name: String) -> void:
	var slug := _slugify_city(name)
	var cfg_res: Resource = null

	# 1) Ask the autoload DB (try name, then slug)
	if Engine.has_singleton("TracksDataBase"):
		var db := get_node_or_null("/root/TracksDataBase")
		if db != null:
			if db.has_method("get_config"):
				cfg_res = db.call("get_config", name)
				if cfg_res == null:
					cfg_res = db.call("get_config", slug)
			if cfg_res == null and db.has_method("get_config_by_slug"):
				cfg_res = db.call("get_config_by_slug", slug)

	# 2) No DB hit? Load the .tres directly from TracksDB/<slug>/<slug>.tres
	if cfg_res == null:
		var p := "res://TracksDB/%s/%s.tres" % [slug, slug]
		if ResourceLoader.exists(p):
			cfg_res = load(p)

	# 3) Apply if it’s the right type; else fall back to old filesystem Tracks/
	if cfg_res is TrackConfig:
		_apply_track_config(cfg_res as TrackConfig, name)
		return
	elif cfg_res != null:
		push_warning("Track config for '%s' is not a TrackConfig resource." % name)

	# Legacy fallback (only works if you also have res://Tracks/<slug>/ assets)
	_apply_track_by_slug(slug)

func _apply_track_config(cfg: TrackConfig, display_name: String) -> void:
	# --- Debug: show which assets are being applied (no ternaries) ---
	var tp := ""
	if cfg.track_texture != null and cfg.track_texture is Resource:
		tp = (cfg.track_texture as Resource).resource_path
	var gp := ""
	if cfg.grass_texture != null and cfg.grass_texture is Resource:
		gp = (cfg.grass_texture as Resource).resource_path
	var cp := ""
	if cfg.collision_map != null and cfg.collision_map is Resource:
		cp = (cfg.collision_map as Resource).resource_path
	print("[TrackCfg] map:", tp, "  grass:", gp, "  coll:", cp)

	# Map textures + tint
	if _map != null:
		if _map.has_method("SetTrackTextures"):
			_map.call("SetTrackTextures", cfg.track_texture, cfg.grass_texture)
		elif _map is Sprite2D and cfg.track_texture != null:
			(_map as Sprite2D).texture = cfg.track_texture

		if _map.has_method("SetMapTint"):
			_map.call("SetMapTint", cfg.tint_color, cfg.tint_strength)
		elif _map is CanvasItem:
			(_map as CanvasItem).modulate = Color(1, 1, 1, 1)

	# Collision map
	if _collision != null:
		if _collision.has_method("SetCollisionTexture"):
			_collision.call("SetCollisionTexture", cfg.collision_map)
		elif _has_prop(_collision, StringName("_collisionMap")):
			_collision.set("_collisionMap", cfg.collision_map)
			if _collision.has_method("Setup"):
				_collision.call("Setup")

	# Path points (overlay + pseudo3D path)
	var pts: PackedVector2Array = cfg.path_points_uv
	if pts.size() >= 2:
		var overlay := get_node_or_null(^"SubViewport/PathOverlay2D")
		if overlay != null:
			# Replace any minimap/default points instead of appending
			if _has_prop(overlay, StringName("mm_append_uv")):
				overlay.set("mm_append_uv", false)
			if overlay.has_method("clear_minimap_points"):
				overlay.call("clear_minimap_points")
			if overlay.has_method("clear_points"):
				overlay.call("clear_points")
			if overlay.has_method("set_points_uv"):
				overlay.call("set_points_uv", pts)

		if _map != null and _map.has_method("SetPathPoints"):
			_map.call("SetPathPoints", pts)

	var minimap2 := find_child("Minimap", true, false)
	if minimap2 != null and minimap2.has_method("mark_path_dirty"):
		minimap2.call("mark_path_dirty")

	# Optional: themed backgrounds per city
	if _backgroundElements != null and _backgroundElements.has_method("SetCityAssetsByName"):
		_backgroundElements.call("SetCityAssetsByName", display_name)

	# Nudge redraws
	if _map is Node2D:
		(_map as Node2D).queue_redraw()
	var ov := get_node_or_null(^"SubViewport/PathOverlay2D")
	if ov is CanvasItem:
		(ov as CanvasItem).queue_redraw()

	_track_applied = true

# --- Helpers required by the code above --------------------------------------
func _slugify_city(name: String) -> String:
	var s := name.strip_edges().to_lower()
	var out := ""
	for i in s.length():
		var ch := s.unicode_at(i)
		if (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57):
			out += char(ch)
		elif ch == 32 or ch == 45 or ch == 95:
			out += "_"
		else:
			out += "_"
	return out

func _unslugify(slug: String) -> String:
	var s := slug.replace("_", " ")
	return s.substr(0,1).to_upper() + s.substr(1, s.length()-1)

func _apply_track_by_slug(slug: String) -> void:
	var base := "res://Tracks/%s/" % slug
	var track: Texture2D = null
	var grass: Texture2D = null
	var coll:  Texture2D = null

	var p_track := base + "map.png"
	if ResourceLoader.exists(p_track):
		var r := load(p_track)
		if r is Texture2D:
			track = r

	var p_grass := base + "grass.png"
	if ResourceLoader.exists(p_grass):
		var r := load(p_grass)
		if r is Texture2D:
			grass = r

	var p_coll := base + "collision.png"
	if ResourceLoader.exists(p_coll):
		var r := load(p_coll)
		if r is Texture2D:
			coll = r

	if _map != null and _map.has_method("SetTrackTextures"):
		_map.call("SetTrackTextures", track, grass)

	if _collision != null:
		if _collision.has_method("SetCollisionTexture"):
			_collision.call("SetCollisionTexture", coll)
		elif coll != null:
			_collision.set("_collisionMap", coll)
			if _collision.has_method("Setup"):
				_collision.call("Setup")

	# path.json: { "points_uv": [[x0,y0], [x1,y1], ...] }
	var p_path := base + "path.json"
	if ResourceLoader.exists(p_path):
		var f := FileAccess.open(p_path, FileAccess.READ)
		if f != null:
			var data = JSON.parse_string(f.get_as_text())
			if typeof(data) == TYPE_DICTIONARY and data.has("points_uv"):
				var arr := PackedVector2Array()
				for p in data["points_uv"]:
					if p is Array and p.size() >= 2:
						arr.append(Vector2(float(p[0]), float(p[1])))
				var overlay := get_node_or_null(^"SubViewport/PathOverlay2D")
				if overlay != null and overlay.has_method("set_points_uv"):
					overlay.call("set_points_uv", arr)
				if _map != null and _map.has_method("SetPathPoints"):
					_map.call("SetPathPoints", arr)

	# Optional: backgrounds keyed by city
	if _backgroundElements != null and _backgroundElements.has_method("SetCityAssetsByName"):
		_backgroundElements.call("SetCityAssetsByName", _unslugify(slug))

func _read_selected_city_any_source() -> String:
	# 1) one-shot handoff from WorldMap
	if Engine.has_meta("selected_city_override"):
		var over := String(Engine.get_meta("selected_city_override"))
		if over != "":
			return over

	# 2) MidnightGrandPrix autoload (if it carries a city)
	var gp := get_node_or_null("/root/MidnightGrandPrix")
	if gp != null:
		for m in ["get_current_city_name", "get_next_city_name", "get_last_city_name"]:
			if gp.has_method(m):
				var v := String(gp.call(m))
				if v != "":
					return v
		for k in ["current_city_name", "next_city_name", "last_city_name"]:
			if _has_prop(gp, StringName(k)):
				var pv = gp.get(k)
				if pv != null and String(pv) != "":
					return String(pv)

	# 3) Globals fallback
	var glb := get_node_or_null("/root/Globals")
	if glb != null:
		if glb.has_method("get_selected_city"):
			var n := String(glb.call("get_selected_city"))
			if n != "":
				return n
		if glb.has_method("get"):
			var v = glb.get("selected_city")
			if v != null and String(v) != "":
				return String(v)

	return ""

# --- Grid helpers (series-aware) ---
func _get_player_uid() -> String:
	if _player == null: return ""
	if _player.has_meta("racer_uid"): return String(_player.get_meta("racer_uid"))
	return _player.name

func _grid_index_for_player(total: int) -> int:
	# In 2P: P1 takes DEFAULT_POINTS[0], P2 takes DEFAULT_POINTS[1]
	if _is_two_player():
		if _player_slot <= 1:
			return 0
		return min(1, max(0, DEFAULT_POINTS.size() - 1))

	# 1P: keep your existing standings logic; fallback = last slot
	var last_fallback = clamp(total - 1, 0, max(0, DEFAULT_POINTS.size() - 1))
	var gp := get_node_or_null("/root/MidnightGrandPrix")
	if gp != null and gp.has_method("standings_rows"):
		var rows = gp.call("standings_rows")
		var uid_order: Array = []
		if rows is Array and rows.size() > 0:
			for r in rows:
				uid_order.append(String(r.get("uid","")))
			for n in Globals.racer_names:
				var u := String(n)
				if not uid_order.has(u):
					uid_order.append(u)
			var i := uid_order.find(_get_player_uid())
			if i >= 0:
				return clamp(i, 0, max(0, DEFAULT_POINTS.size() - 1))
		else:
			return last_fallback
	return last_fallback

func _selected_from_meta_or_globals(all_names: Array) -> String:
	# 1) Prefer Globals per-slot (if you store it there)
	if Globals.has_method("get_selected_racer_for_slot"):
		var nm_globals := String(Globals.get_selected_racer_for_slot(_player_slot))
		if nm_globals != "" and all_names.has(nm_globals):
			return nm_globals

	# 2) Engine meta per-slot
	var key := "p1_racer"
	if _player_slot != 1:
		key = "p2_racer"

	if Engine.has_meta(key):
		var nm_meta := String(Engine.get_meta(key))
		if nm_meta != "" and all_names.has(nm_meta):
			return nm_meta

	# 3) Global single-player selection
	var nm_global_single := String(Globals.selected_racer)
	if nm_global_single != "" and all_names.has(nm_global_single):
		return nm_global_single

	# 4) Fallbacks
	if all_names.size() > 0:
		return String(all_names[0])
	return "Voltage"

func _is_two_player() -> bool:
	var pc := 1
	if Engine.has_meta("player_count"):
		pc = int(Engine.get_meta("player_count"))
	return pc >= 2
