extends Node2D

@export_group("Map")
@export var map_texture: Texture2D                # drop your world PNG here
@export var marker_radius_px: float = 6.0
@export var marker_color: Color = Color(1, 0.8, 0.25, 1.0)
@export var marker_color_player: Color = Color(0.35, 1.0, 0.55, 1.0) # highlight color
@export var show_city_labels: bool = true

@export_group("Camera")
@export var pan_speed_px_s: float = 900.0
@export var accel: float = 10.0
@export var friction: float = 7.0
@export var zoom_min: float = 0.40
@export var zoom_max: float = 1.25
@export var zoom_step: float = 0.10

@export_group("Integration")
@export var start_intro_on_select: bool = true   # A/Enter → TrackIntro, then race
@export var default_track_scene: String = "res://Scenes/main.tscn" # fallback per city

@export var _map: Sprite2D
@export var _cam: Camera2D
@export var _markers_root: Node2D
@export var _hint: Label

@export_group("City Label Style")
@export var city_font: Font
@export var city_font_size: int = 14
@export var city_outline_size: int = 2
@export var city_outline_color: Color = Color(0,0,0,0.85)
@export var city_text_color: Color = Color(1,1,1,0.95)

@export_group("Geo Mapping")
@export var auto_fit_lonlat_rect: bool = true
@export var lonlat_rect_px: Rect2i = Rect2i(0, 56, 854, 427)  # for PixelWorldMap_All_Countries_ClearBG_1x.png

var _cam_vel: Vector2 = Vector2.ZERO
var _cities := []   # filled with dictionaries {name, country, lat, lon, scene, node}

func _ready() -> void:
	# Basic input actions (safe if they already exist)
	_ensure_actions()

	# Setup map sprite
	if map_texture == null:
		push_error("WorldMap: map_texture not set.")
		return
	_map.texture = map_texture
	_map.centered = false
	_map.position = Vector2.ZERO

	_ensure_lonlat_rect()   # <<< add this

	# Camera initial zoom and limits
	_cam.zoom = Vector2.ONE
	_update_camera_limits()

	# Build city list + markers
	_build_cities()
	_place_markers_from_latlon()

	# UI hint
	if _hint:
		_hint.text = "Move: Left Stick / D-Pad   Zoom: LB/RB or Q/E   Select: A / Enter   Back: B / Esc"
		_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	set_process(true)
	set_process_input(true)

func _process(dt: float) -> void:
	# Panning (keyboard actions; stick handled in _input for smoothness)
	var axis := Input.get_vector("map_left","map_right","map_up","map_down")
	var wish := axis * pan_speed_px_s
	_cam_vel = _cam_vel.move_toward(wish, accel * dt)
	_cam.position += _cam_vel * dt

	# friction if no input
	if axis == Vector2.ZERO:
		_cam_vel = _cam_vel.move_toward(Vector2.ZERO, friction * dt)

	# Clamp inside map
	_clamp_camera_to_map()

	# Highlight nearest city to camera center
	_highlight_nearest_to_camera()

func _input(event: InputEvent) -> void:
	# Analog stick panning
	if event is InputEventJoypadMotion:
		var lx := Input.get_action_strength("map_right") - Input.get_action_strength("map_left")
		var ly := Input.get_action_strength("map_down") - Input.get_action_strength("map_up")
		var stick := Vector2(lx, ly)
		if stick.length_squared() > 0.0001:
			var wish := stick.normalized() * pan_speed_px_s
			_cam_vel = _cam_vel.move_toward(wish, accel * get_process_delta_time())

	# Zoom
	if event.is_action_pressed("map_zoom_in"):
		_cam.zoom = Vector2.ONE * clamp(_cam.zoom.x - zoom_step, zoom_min, zoom_max)
		_update_camera_limits(); _clamp_camera_to_map()
		var vp := get_viewport(); if vp != null: vp.set_input_as_handled()
	elif event.is_action_pressed("map_zoom_out"):
		_cam.zoom = Vector2.ONE * clamp(_cam.zoom.x + zoom_step, zoom_min, zoom_max)
		_update_camera_limits(); _clamp_camera_to_map()
		var vp2 := get_viewport(); if vp2 != null: vp2.set_input_as_handled()

	# Select nearest city (A / Enter)
	if event.is_action_pressed("ui_accept"):
		_select_nearest_city()
		var vp3 := get_viewport(); if vp3 != null: vp3.set_input_as_handled()

	# Back (B / Esc)
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://Scenes/Title.tscn")
		var vp4 := get_viewport(); if vp4 != null: vp4.set_input_as_handled()

# ---------- Camera helpers ----------

func _update_camera_limits() -> void:
	var tex_size := map_texture.get_size()
	# Camera2D limits refer to world coords; we clamp manually in _clamp_camera_to_map
	# so we just ensure limits are wide enough.
	_cam.limit_left = 0
	_cam.limit_top = 0
	_cam.limit_right = int(tex_size.x)
	_cam.limit_bottom = int(tex_size.y)

func _clamp_camera_to_map() -> void:
	var tex := map_texture.get_size()
	var vw := get_viewport_rect().size / _cam.zoom   # world size visible
	var half := vw * 0.5

	var minp := half
	var maxp := Vector2(tex.x, tex.y) - half
	# If map smaller than viewport on either axis, keep camera centered on that axis
	if minp.x > maxp.x:
		_cam.position.x = tex.x * 0.5
	else:
		_cam.position.x = clamp(_cam.position.x, minp.x, maxp.x)
	if minp.y > maxp.y:
		_cam.position.y = tex.y * 0.5
	else:
		_cam.position.y = clamp(_cam.position.y, minp.y, maxp.y)

# ---------- City markers ----------

func _build_cities() -> void:
	_cities = [
		{"name":"New York",     "country":"USA",          "lat":40.7128,   "lon":-74.0060,  "scene": default_track_scene},
		{"name":"Los Angeles",  "country":"USA",          "lat":34.0522,   "lon":-118.2437, "scene": default_track_scene},
		{"name":"Mexico City",  "country":"Mexico",       "lat":19.4326,   "lon":-99.1332,  "scene": default_track_scene},
		{"name":"Sao Paulo",    "country":"Brazil",       "lat":-23.5505,  "lon":-46.6333,  "scene": default_track_scene},
		{"name":"London",       "country":"UK",           "lat":51.5074,   "lon":-0.1278,   "scene": default_track_scene},
		{"name":"Paris",        "country":"France",       "lat":48.8566,   "lon":2.3522,    "scene": default_track_scene},
		{"name":"Berlin",       "country":"Germany",      "lat":52.52,     "lon":13.405,    "scene": default_track_scene},
		{"name":"Rome",         "country":"Italy",        "lat":41.9028,   "lon":12.4964,   "scene": default_track_scene},
		{"name":"Moscow",       "country":"Russia",       "lat":55.7558,   "lon":37.6173,   "scene": default_track_scene},
		{"name":"Cairo",        "country":"Egypt",        "lat":30.0444,   "lon":31.2357,   "scene": default_track_scene},
		{"name":"Istanbul",     "country":"Türkiye",      "lat":41.0082,   "lon":28.9784,   "scene": default_track_scene},
		{"name":"Dubai",        "country":"UAE",          "lat":25.2048,   "lon":55.2708,   "scene": default_track_scene},
		{"name":"Mumbai",       "country":"India",        "lat":19.0760,   "lon":72.8777,   "scene": default_track_scene},
		{"name":"Beijing",      "country":"China",        "lat":39.9042,   "lon":116.4074,  "scene": default_track_scene},
		{"name":"Seoul",        "country":"Korea",        "lat":37.5665,   "lon":126.9780,  "scene": default_track_scene},
		{"name":"Tokyo",        "country":"Japan",        "lat":35.6762,   "lon":139.6503,  "scene": default_track_scene},
		{"name":"Singapore",    "country":"Singapore",    "lat":1.3521,    "lon":103.8198,  "scene": default_track_scene},
		{"name":"Sydney",       "country":"Australia",    "lat":-33.8688,  "lon":151.2093,  "scene": default_track_scene},
		{"name":"Johannesburg", "country":"South Africa", "lat":-26.2041,  "lon":28.0473,   "scene": default_track_scene},
		{"name":"Toronto",      "country":"Canada",       "lat":43.6532,   "lon":-79.3832,  "scene": default_track_scene},
	]

func _place_markers_from_latlon() -> void:
	# Clear
	for c in _markers_root.get_children():
		c.queue_free()

	var r := lonlat_rect_px
	var rx := float(r.position.x)
	var ry := float(r.position.y)
	var rw := float(r.size.x)
	var rh := float(r.size.y)

	for i in range(_cities.size()):
		var d: Dictionary = _cities[i]
		var lon := float(d["lon"])   # [-180, +180]
		var lat := float(d["lat"])   # [-90, +90]

		var u := (lon + 180.0) / 360.0   # 0..1 across the rect width
		var v := (90.0 - lat) / 180.0    # 0..1 down the rect height

		var px := Vector2(rx + u * rw, ry + v * rh)

		var node := Node2D.new()
		node.position = px
		node.set_meta("idx", i)
		_markers_root.add_child(node)

		var dot := ColorRect.new()
		dot.color = marker_color
		dot.size = Vector2(marker_radius_px * 2.0, marker_radius_px * 2.0)
		dot.position = -dot.size * 0.5
		dot.name = "Dot"
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.add_child(dot)

		if show_city_labels:
			var lab := Label.new()
			lab.text = String(d["name"])
			# Apply your font settings
			var ls := LabelSettings.new()
			ls.font = city_font          # may be null; that’s fine
			ls.font_size = city_font_size
			ls.font_color = city_text_color
			ls.outline_size = city_outline_size
			ls.outline_color = city_outline_color
			lab.label_settings = ls
			lab.position = Vector2(8, -18)
			lab.name = "Label"
			node.add_child(lab)

		d["node"] = node
		_cities[i] = d

# ---------- Selection / Highlight ----------

func _nearest_city_to(pos_world: Vector2) -> int:
	var best_i := -1
	var best_d2 := 1e12
	for i in range(_cities.size()):
		var d: Dictionary = _cities[i]
		var n = d.get("node", null)
		if n == null: continue
		var node := n as Node2D
		var d2 := node.position.distance_squared_to(pos_world)
		if d2 < best_d2:
			best_d2 = d2
			best_i = i
	return best_i

func _highlight_nearest_to_camera() -> void:
	var center := _cam.get_screen_center_position()
	var idx := _nearest_city_to(center)
	for i in range(_cities.size()):
		var d: Dictionary = _cities[i]
		var node := d.get("node", null) as Node2D
		if node == null: continue
		var dot := node.get_node("Dot") as ColorRect
		if i == idx:
			dot.color = marker_color_player
			dot.size = Vector2(marker_radius_px * 2.3, marker_radius_px * 2.3)
		else:
			dot.color = marker_color
			dot.size = Vector2(marker_radius_px * 2.0, marker_radius_px * 2.0)
		dot.position = -dot.size * 0.5

func _select_nearest_city() -> void:
	var center := _cam.get_screen_center_position()
	var idx := _nearest_city_to(center)
	if idx < 0:
		return

	var d: Dictionary = _cities[idx]

	# Build image path (no ternary)
	var image_path := ""
	if map_texture != null:
		var rp := String(map_texture.resource_path)
		if rp != "":
			image_path = rp

	var info := {
		"name": String(d.get("name","")),
		"location": String(d.get("country","")),
		"length_km": 0.0,
		"laps": 5,
		"blurb": "City race in " + String(d.get("name","")),
		"record": "",
		"image": image_path
	}

	if Engine.has_singleton("MidnightGrandPrix"):
		var gp = MidnightGrandPrix
		var path := String(d.get("scene",""))
		if path == "" and default_track_scene != "":
			path = default_track_scene

		var list := PackedStringArray()
		for c in _cities:
			var sp := String(c.get("scene",""))
			if sp == "":
				sp = default_track_scene
			list.append(sp)
		gp.tracks = list

		if gp.has_method("set_track_meta_for_scene"):
			gp.set_track_meta_for_scene(path, info)

		if start_intro_on_select:
			gp.show_intro = true
		gp.start_gp(idx)
	else:
		var direct := String(d.get("scene",""))
		if direct != "":
			get_tree().change_scene_to_file(direct)
		elif default_track_scene != "":
			get_tree().change_scene_to_file(default_track_scene)

	# mark input handled (since we’re a Node2D, no accept_event())
	var vp := get_viewport()
	if vp != null:
		vp.set_input_as_handled()

# ---------- Utility ----------

func _ensure_actions() -> void:
	if not InputMap.has_action("map_left"):  InputMap.add_action("map_left")
	if not InputMap.has_action("map_right"): InputMap.add_action("map_right")
	if not InputMap.has_action("map_up"):    InputMap.add_action("map_up")
	if not InputMap.has_action("map_down"):  InputMap.add_action("map_down")
	if not InputMap.has_action("map_zoom_in"):  InputMap.add_action("map_zoom_in")
	if not InputMap.has_action("map_zoom_out"): InputMap.add_action("map_zoom_out")
	if not InputMap.has_action("ui_accept"): InputMap.add_action("ui_accept")
	if not InputMap.has_action("ui_cancel"): InputMap.add_action("ui_cancel")

	# Default bindings (won’t duplicate on hot-reload)
	var keys = {
		"map_left":[Key.KEY_A, Key.KEY_LEFT],
		"map_right":[Key.KEY_D, Key.KEY_RIGHT],
		"map_up":[Key.KEY_W, Key.KEY_UP],
		"map_down":[Key.KEY_S, Key.KEY_DOWN],
		"map_zoom_in":[Key.KEY_Q],
		"map_zoom_out":[Key.KEY_E]
	}
	for act in keys.keys():
		for k in keys[act]:
			var ev := InputEventKey.new()
			ev.keycode = k
			InputMap.action_add_event(act, ev)

	# Gamepad: Left stick + D-Pad
	for act_btn in [
		["map_left",  JOY_BUTTON_DPAD_LEFT],
		["map_right", JOY_BUTTON_DPAD_RIGHT],
		["map_up",    JOY_BUTTON_DPAD_UP],
		["map_down",  JOY_BUTTON_DPAD_DOWN],
	]:
		var jb := InputEventJoypadButton.new()
		jb.button_index = act_btn[1]
		InputMap.action_add_event(StringName(act_btn[0]), jb)

	# Zoom on shoulders
	var jb_in := InputEventJoypadButton.new();  jb_in.button_index = JOY_BUTTON_LEFT_SHOULDER
	var jb_out := InputEventJoypadButton.new(); jb_out.button_index = JOY_BUTTON_RIGHT_SHOULDER
	InputMap.action_add_event("map_zoom_in", jb_in)
	InputMap.action_add_event("map_zoom_out", jb_out)

	# Accept/Cancel on A/B
	var jA := InputEventJoypadButton.new(); jA.button_index = JOY_BUTTON_A
	var jB := InputEventJoypadButton.new(); jB.button_index = JOY_BUTTON_B
	InputMap.action_add_event("ui_accept", jA)
	InputMap.action_add_event("ui_cancel", jB)

func _compute_default_lonlat_rect() -> Rect2i:
	var w := int(map_texture.get_width())
	var h := int(map_texture.get_height())
	if w <= 0 or h <= 0:
		return Rect2i(0,0,0,0)

	# Find the largest 2:1 rectangle inside the PNG (equirectangular area)
	var aspect := float(w) / float(h)
	if aspect >= 2.0:
		var target_w := int(2.0 * float(h))
		var x := (w - target_w) / 2
		return Rect2i(x, 0, target_w, h)   # letterboxed left/right
	else:
		var target_h := int(float(w) / 2.0)
		var y := (h - target_h) / 2
		return Rect2i(0, y, w, target_h)   # letterboxed top/bottom

func _ensure_lonlat_rect() -> void:
	if not auto_fit_lonlat_rect:
		return
	if lonlat_rect_px.size.x <= 0 or lonlat_rect_px.size.y <= 0:
		lonlat_rect_px = _compute_default_lonlat_rect()
