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
@export var src_hue: float   = 0.333333
@export var hue_tol: float   = 0.08
@export var edge_soft: float = 0.20

# Priming sheet (avoid 1-frame flash)
@export var prime_hframes: bool = true
@export var sheet_hframes: int  = 12

var DEFAULT_POINTS: PackedVector2Array = PackedVector2Array([
	Vector2(922, 584),
	Vector2(952, 607),
	Vector2(922, 631),
	Vector2(952, 655),
	Vector2(922, 679),
	Vector2(952, 703),
	Vector2(922, 727),
	Vector2(952, 751)
])

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

	# Build ordered names: selected, then remaining (we’ll spawn opponents from remaining, player last)
	var all_names: Array = []
	for n in Globals.racer_names:
		all_names.append(String(n))

	var selected := String(Globals.selected_racer)
	if selected == "" or not all_names.has(selected):
		if all_names.size() > 0:
			selected = String(all_names[0])
		else:
			selected = "Voltage"

	var remaining: Array = []
	for n in all_names:
		if n != selected:
			remaining.append(n)

	if Globals.has_method("set_selected_racer"):
		Globals.set_selected_racer(selected)
		print("Picked:", Globals.selected_racer, " color:", Globals.selected_color)

	# === 1) Spawn ALL OPPONENTS FIRST (player comes last) ===
	for i in range(remaining.size()):
		var nm := String(remaining[i])
		var opp := opponent_scene.instantiate()
		opp.name = nm
		racers_root.add_child(opp)

		# Collision + opponent setup (player_ref set later, after player exists)
		_wire_racer(opp, false)

		# Colorize now
		var ocol := Globals.get_racer_color(nm)
		_set_racer_name_label(opp, nm, ocol)
		var ospr := _find_sprite(opp)
		if ospr != null:
			_apply_yoshi_shader(ospr, ocol)

	# === 2) Spawn PLAYER LAST ===
	var p := player_scene.instantiate()
	p.name = selected
	racers_root.add_child(p)
	_wire_racer(p, true)
	_player = p

	# Color (shader) + identity label immediately
	var pcol := Globals.get_racer_color(selected)
	var pspr := _find_sprite(_player)
	if pspr != null:
		_apply_yoshi_shader(pspr, pcol)

	if _player.has_method("RefreshPaletteFromGlobals"):
		_player.RefreshPaletteFromGlobals()

	# HUD: point to the new player
	var hud := get_node_or_null(^"RaceHUD")
	if hud:
		hud.set("player_path", hud.get_path_to(_player))
		hud.set("_player", _player)

	# Bind player_ref on opponents now that player exists
	_bind_player_ref_to_opponents(racers_root, _player)

	# Keep Globals in sync with the spawned player/color
	if Globals.has_method("set_selected_racer"):
		Globals.set_selected_racer(selected)

	_update_hud_name_color()

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

	var want := Globals.racer_names.size()
	var chosen_name := String(Globals.selected_racer)
	var candidate: Node = null

	tries = 0
	while tries < 360:
		var have := 0
		candidate = null
		for c in racers_root.get_children():
			if c is Node2D:
				have += 1
				if c.name == chosen_name:
					candidate = c
		if have >= want and candidate != null:
			break
		await get_tree().process_frame
		tries += 1

	if candidate == null:
		push_error("World: chosen racer node not found.")
		return

	_player = candidate
	_wire_player_dependencies()

	if _player.has_method("RefreshPaletteFromGlobals"):
		_player.RefreshPaletteFromGlobals()
	else:
		if _player.has_method("_ensure_yoshi_material"): _player._ensure_yoshi_material()
		if _player.has_method("_apply_player_palette_from_globals"): _player._apply_player_palette_from_globals()

	_retarget_player_paths(get_tree().current_scene, _player)

	var hud := get_node_or_null(^"RaceHUD")
	if hud:
		hud.set("player_path", hud.get_path_to(_player))
		hud.set("_player", _player)

	_roster_ready = true
	_setup_after_roster()

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

	# Bind PathOverlay2D to the Map (Pseudo3D)
	var overlay_node := get_node(^"SubViewport/PathOverlay2D")
	var overlay_vp   := get_node(^"SubViewport") as SubViewport
	var rel_from_map := _map.get_path_to(overlay_node)
	if _map != null and _map.has_method("SetPathOverlayNodePath"):
		_map.call("SetPathOverlayNodePath", rel_from_map, overlay_vp)

	# >>> BIND THE SKID PAINTER / OVERLAY PATHS HERE <<<
	var painter := overlay_node  # PathOverlay2D node (has player_path & pseudo3d_path exports)
	if painter:
		painter.set("player_path", painter.get_path_to(_player))
		painter.set("pseudo3d_path", painter.get_path_to(_map))

	# Tell Map which nodes are opponents, etc.
	if _map != null and _map.has_method("SetOpponentsFromGroup"):
		_map.call("SetOpponentsFromGroup", "racers", _player)

	if _collision != null and _collision.has_method("Setup"):
		_collision.call("Setup")

	_player.Setup((_map as Sprite2D).texture.get_size().x)
	_spriteHandler.Setup(_map.ReturnWorldMatrix(), (_map as Sprite2D).texture.get_size().x, _player)
	_animationHandler.Setup(_player)

	# RaceManager boot
	if is_instance_valid(_raceManager):
		_raceManager.Setup()
		_raceManager.connect("standings_changed", Callable(self, "_on_standings_changed"))

	# Push path/overlay to subsystems, then finalize AI grid when the path is hot
	call_deferred("_push_path_points_once")
	call_deferred("_spawn_player_at_path_index", 1)

	# Register opponents with the map now (they were spawned dynamically)
	_refresh_map_opponents()

	# Finalize opponent grid a couple frames later so the path is guaranteed ready
	if _map != null and _map.has_method("SetOpponentsFromGroup"):
		_map.call("SetOpponentsFromGroup", "racers", _player)

	call_deferred("_finalize_ai_grid_spawn")
	
	_update_hud_name_color()
	_map_ready = true

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

func _apply_yoshi_shader(spr: Node, col: Color) -> void:
	if ResourceLoader.exists(yoshi_shader_path):
		var sh := load(yoshi_shader_path) as Shader
		if sh != null:
			var sm := ShaderMaterial.new()
			sm.shader = sh
			sm.resource_local_to_scene = true
			sm.set_shader_parameter("target_color", col)
			sm.set_shader_parameter("src_hue",     src_hue)
			sm.set_shader_parameter("hue_tol",     hue_tol)
			sm.set_shader_parameter("edge_soft",   edge_soft)
			if spr is CanvasItem:
				(spr as CanvasItem).material = sm
	else:
		# fallback: multiply tint
		if spr is CanvasItem:
			(spr as CanvasItem).modulate = col

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
	# Find a child Label named "Name" on the HUD
	var lbl := hud.get_node_or_null(^"Name")
	if lbl == null:
		lbl = _find_label_named(hud, "Name")
	if lbl != null:
		lbl.text = String(Globals.selected_racer).to_upper()
		lbl.add_theme_color_override("font_color", Globals.selected_color)

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

	# Last grid index we will use for the player
	var last_idx := total - 1
	if last_idx >= DEFAULT_POINTS.size():
		last_idx = DEFAULT_POINTS.size() - 1
	if last_idx < 0:
		last_idx = 0

	# 1) Place opponents into 0 .. last_idx-1
	var opp_i := 0
	for n in racers_root.get_children():
		if n == _player:
			continue
		if opp_i >= last_idx:
			break

		var px: Vector2 = DEFAULT_POINTS[opp_i]

		var used_merge := false
		if n.has_method("ArmMergeFromGrid"):
			var uv := px / scale_px
			n.call("ArmMergeFromGrid", uv, 0, 0.0)
			used_merge = true
		if not used_merge and n.has_method("SetMapPosition"):
			n.call("SetMapPosition", Vector3(px.x, 0.0, px.y))

		# Ensure they know the player (now that _player exists)
		if _player != null and _has_prop(n, "player_ref"):
			n.set("player_ref", n.get_path_to(_player))

		opp_i += 1

	# 2) Place the player at the last slot
	var ppx: Vector2 = DEFAULT_POINTS[last_idx]
	if _player != null and _player.has_method("SetMapPosition"):
		_player.call("SetMapPosition", Vector3(ppx.x, 0.0, ppx.y))
