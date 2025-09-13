extends Node2D
class_name WorldMap

@export var html_path: String = "res://amCharts.pixelMap.html"
@export var map_size: Vector2i = Vector2i(1920, 960)
@export var pixel_size: int = 5
@export var pixel_color: Color = Color(129.0/255.0, 129.0/255.0, 129.0/255.0, 1.0)
@export var background_color: Color = Color(80.0/255.0, 80.0/255.0, 80.0/255.0, 1.0)

@export var completed_label_color: Color = Color(1.0, 0.25, 0.25, 1.0)  # “red”

@export var camera_path: NodePath
@export var camera_smoothing_speed: float = 5.0
@export var enable_camera_limits: bool = true

@export var marker_color: Color = Color(1.0, 0.35, 0.35, 1.0)
@export var marker_radius: float = 8.0

# --- City label styling (map) ---
@export var show_city_dots: bool = true
@export var city_dot_radius: float = 3.0
@export var city_dot_color: Color = Color(1.0, 0.9, 0.3, 1.0)

@export var show_city_labels: bool = true
@export var label_font: Font
@export var label_font_size: int = 16
@export var label_color: Color = Color(1, 1, 1, 1)
@export var map_label_outline_px: int = 2
@export var map_label_outline_color: Color = Color(0, 0, 0, 0.85)
@export var city_label_offset: Vector2 = Vector2(8, -8)

# Selected city emphasis (map)
@export var selected_label_color: Color = Color(1.0, 0.95, 0.5, 1.0)
@export var selected_label_outline_px: int = 3
@export var selected_label_outline_color: Color = Color(0, 0, 0, 1.0)
@export var selected_ring_color: Color = Color(1.0, 0.85, 0.3, 1.0)
@export var selected_city_dot_radius: float = 5.0
@export var pulse_scale: float = 1.35
@export var pulse_time: float = 0.35

# --- Zoom controls ---
@export var zoom_min: float = 0.5
@export var zoom_max: float = 4.0
@export var zoom_step: float = 0.2
@export var zoom_lerp_speed: float = 8.0

# --- City cycle options ---
@export var cycle_jumps_camera: bool = false
@export var start_on_city_index: int = 0

# --- UI (Title / Info) ---
@export var title_label_path: NodePath
@export var info_label_path: NodePath
@export var ui_font: Font
@export var ui_font_size: int = 36
@export var ui_color: Color = Color(1, 1, 1, 1)
@export var ui_outline_px: int = 6
@export var ui_outline_color: Color = Color(0, 0, 0, 0.9)
@export var ui_shadow_offset: Vector2 = Vector2(2, 2)
@export var ui_shadow_color: Color = Color(0, 0, 0, 0.45)
@export var ui_pulse_scale: float = 1.1
@export var ui_pulse_time: float = 0.25
@export var ui_flash_color: Color = Color(1.0, 0.85, 0.2, 1.0)

var _marker_pos := Vector2.ZERO
var _map_sprite: Sprite2D = null
var _camera: Camera2D = null
var _title: Label = null
var _info: Label = null

var _target_zoom: float = 1.0
var _pulse_t: float = 0.0

var _rng := RandomNumberGenerator.new()

@export var default_size: Vector2i = Vector2i(240, 240)

const CITY_DATA := [
	{"name":"Los Angeles", "lon":-118.2437, "lat":34.0522},
	{"name":"Banff", "lon":-115.5708, "lat":51.1784},                 # Banff town, Alberta
	{"name":"Mexico City", "lon":-99.1332, "lat":19.4326},
	{"name":"Keystone", "lon":-96.2775, "lat":36.1287},               # Keystone State Park (OK) coords
	{"name":"Toronto", "lon":-79.3832, "lat":43.6532},
	{"name":"New York", "lon":-74.0060, "lat":40.7128},
	{"name":"Buenos Aires", "lon":-58.3816, "lat":-34.6037},
	{"name":"Sao Paulo", "lon":-46.6333, "lat":-23.5505},
	{"name":"Madrid", "lon":-3.7038, "lat":40.4168},
	{"name":"London", "lon":-0.1276, "lat":51.5074},
	{"name":"Paris", "lon":2.3522, "lat":48.8566},
	{"name":"Lagos", "lon":3.3792, "lat":6.5244},
	{"name":"Istanbul", "lon":28.9784, "lat":41.0082},
	{"name":"Cairo", "lon":31.2357, "lat":30.0444},
	{"name":"Moscow", "lon":37.6173, "lat":55.7558},
	{"name":"Dubai", "lon":55.2708, "lat":25.2048},
	{"name":"Mumbai", "lon":72.8777, "lat":19.0760},
	{"name":"Taj Mahal", "lon":78.0421, "lat":27.1751},               # Agra, India
	{"name":"Nuwara Eliya", "lon":80.7891, "lat":6.9497},             # Sri Lanka highlands
	{"name":"Singapore", "lon":103.8198, "lat":1.3521},
	{"name":"Beijing", "lon":116.4074, "lat":39.9042},
	{"name":"Seoul", "lon":126.9780, "lat":37.5665},
	{"name":"Tokyo", "lon":139.6917, "lat":35.6895},
	{"name":"Sydney", "lon":151.2093, "lat":-33.8688},
]

const CITY_FACTS := {
	"New York": [
		"Central Park is larger than Monaco.",
		"The Statue of Liberty was a gift from France in 1886.",
		"Times Square is nicknamed the Crossroads of the World."
	],
	"Los Angeles": [
		"The Hollywood sign originally read Hollywoodland in 1923.",
		"The Walk of Fame has more than 2,700 stars.",
		"Griffith Observatory watches over the city and the sign."
	],
	"Mexico City": [
		"The city stands on the ruins of the Aztec capital Tenochtitlan.",
		"Its elevation is about 2,240 meters above sea level.",
		"The Zócalo is among the world’s largest public squares."
	],
	"Sao Paulo": [
		"It is the largest city in the Southern Hemisphere.",
		"Avenida Paulista is a major cultural and financial corridor.",
		"The city is often nicknamed Sampa."
	],
	"Buenos Aires": [
		"The tango originated here in the late 19th century.",
		"The Obelisk on 9 de Julio Avenue is a city icon.",
		"It’s nicknamed the Paris of South America."
	],
	"London": [
		"The Underground opened in 1863, the world’s first subway.",
		"The Thames Barrier helps protect the city from flooding.",
		"The Shard is the tallest building in the UK."
	],
	"Paris": [
		"The Louvre is the world’s most-visited museum.",
		"The Eiffel Tower was built for the 1889 Exposition Universelle.",
		"Paris is nicknamed La Ville Lumière—the City of Light."
	],
	"Madrid": [
		"Puerta del Sol marks Kilometer Zero of Spain’s roads.",
		"El Retiro and the Prado area form a UNESCO Landscape of Light.",
		"Plaza Mayor dates to the early 1600s."
	],
	"Lagos": [
		"Nigeria’s largest city spreads around Lagos Lagoon.",
		"It’s a powerhouse for Nollywood and Afrobeats.",
		"Victoria Island is a major business district."
	],
	"Moscow": [
		"The Kremlin and Red Square are UNESCO World Heritage Sites.",
		"Moscow Metro stations are famed for palatial designs.",
		"The city stands on the Moskva River."
	],
	"Istanbul": [
		"It spans Europe and Asia across the Bosphorus.",
		"Hagia Sophia has been cathedral, mosque, museum, and mosque again.",
		"The Grand Bazaar is among the oldest covered markets."
	],
	"Dubai": [
		"Burj Khalifa rises 828 meters, the world’s tallest building.",
		"Palm Jumeirah is an artificial island shaped like a palm tree.",
		"Dubai Mall is among the largest shopping centers globally."
	],
	"Mumbai": [
		"It’s home to Bollywood, India’s film industry hub.",
		"The Gateway of India was completed in 1924.",
		"The city was officially renamed from Bombay in 1995."
	],
	"Singapore": [
		"It’s a city-state at the tip of the Malay Peninsula.",
		"Known as the Garden City for its greenery.",
		"Changi Airport frequently tops global rankings."
	],
	"Beijing": [
		"The Forbidden City anchors the historic center.",
		"It hosted the Summer 2008 and Winter 2022 Olympics.",
		"The Temple of Heaven is a UNESCO site."
	],
	"Seoul": [
		"The Hangang River runs through the city.",
		"Gyeongbokgung Palace dates to 1395.",
		"Its subway is among the world’s busiest."
	],
	"Tokyo": [
		"Shibuya Crossing is one of the busiest on earth.",
		"Tokyo Skytree stands 634 meters tall.",
		"Greater Tokyo is among the world’s largest metro areas."
	],
	"Sydney": [
		"The Opera House opened in 1973 and is UNESCO-listed.",
		"The Harbour Bridge is nicknamed the Coathanger.",
		"Bondi Beach is one of Australia’s most famous beaches."
	],
	"Toronto": [
		"The CN Tower was the tallest freestanding structure from 1976 to 2007.",
		"The PATH is a 30+ km underground walkway network.",
		"St. Lawrence Market is a celebrated 19th-century food hall."
	],
	"Taj Mahal": [
		"A white-marble mausoleum built by Shah Jahan for Mumtaz Mahal (construction ~1632–1653).",
		"It sits on the Yamuna River and appears to change color with the light.",
		"Listed as a UNESCO World Heritage Site in 1983."
	],
	"Nuwara Eliya": [
		"Tea-country hill town nicknamed ‘Little England’ for its cool climate and colonial-era villas.",
		"Elevation is roughly 1,868 meters, surrounded by rolling tea estates.",
		"Gateway to Horton Plains National Park and the World’s End escarpment."
	],
	"Keystone": [
		"Set on Keystone Lake west of Tulsa, with coves and wooded shoreline.",
		"Popular for boating and fishing—catfish, crappie, and striped bass are common targets.",
		"Trails and cabins sit among Cross Timbers woodlands and sandstone bluffs."
	],
	"Banff": [
		"Banff National Park (est. 1885) is Canada’s first national park.",
		"The town of Banff sits in the Bow Valley beneath the Rockies.",
		"Iconic glacial lakes—like Lake Louise and Moraine Lake—are nearby."
	],
}

var _cities: Array = []     # each = {"name": String, "lon": float, "lat": float, "pos": Vector2}
var _city_index: int = 0

func _ready() -> void:
	_force_minimap_front_debug()
	_camera = _resolve_camera()
	_title = _resolve_label(title_label_path)
	_info = _resolve_label(info_label_path)
	_style_ui_label(_title)
	_style_ui_label(_info)

	_setup_camera()
	_build_map_texture_from_html()
	_init_cities()

	# Prefer last city raced (from GP), otherwise use start_on_city_index
	var desired_idx := -1
	var gp := get_node_or_null("/root/MidnightGrandPrix")
	if gp != null:
		var last_name := ""
		if gp.has_method("get_last_city_name"):
			last_name = String(gp.call("get_last_city_name"))
		else:
			var v = gp.get("last_city_name")
			if v != null:
				last_name = String(v)
		if last_name != "":
			desired_idx = _find_city_index_by_name(last_name)

	if desired_idx == -1:
		desired_idx = clamp(start_on_city_index, 0, max(CITY_DATA.size() - 1, 0))

	_city_index = desired_idx
	if CITY_DATA.size() > 0:
		_goto_city(_city_index, true)

	_target_zoom = 1.0
	set_process(true)
	queue_redraw()
	
	_rng.randomize()
	
	process_mode = Node.PROCESS_MODE_ALWAYS  # still receive input if something paused the tree
	_ensure_ui_accept_binding()	

func _force_minimap_front_debug() -> void:
	var mm := get_node_or_null(^"CanvasLayer/Control/Minimap")
	if mm is Control:
		var c := mm as Control
		# Ignore parent layout/transforms (escapes clipping/containers)
		c.top_level = true
		# Big, visible, and in a safe corner
		if c.size.x < 2 or c.size.y < 2:
			c.custom_minimum_size = Vector2(280, 280)
			c.size = c.custom_minimum_size
		c.global_position = Vector2(32, 32)
		# Draw above anything in this canvas
		c.z_as_relative = false
		c.z_index = 100000
		c.visible = true
		# Disable clipping up the chain (just in case)
		var p := c.get_parent()
		while p is Control:
			(p as Control).clip_contents = false
			p = p.get_parent()
	# World map sprite should NOT be under a CanvasLayer
	if _map_sprite != null:
		_map_sprite.z_as_relative = false
		_map_sprite.z_index = -5000
		var up := _map_sprite.get_parent()
		while up != null:
			if up is CanvasLayer:
				push_warning("WorldMap Sprite2D is under a CanvasLayer; move it out (it can cover UI).")
				break
			up = up.get_parent()
	# Print the truth about layers & size
	_minimap_vis_dump()

func _minimap_vis_dump() -> void:
	var mm := get_node_or_null(^"CanvasLayer/Control/Minimap")
	var cl := get_node_or_null(^"CanvasLayer")
	if mm is Control:
		var c := mm as Control
		var rect := c.get_global_rect()
		prints("[MM] size=", c.size, " global=", rect,
			   " z=", c.z_index, " rel=", c.z_as_relative,
			   " visible=", c.is_visible_in_tree(),
			   " ui.layer=", (cl.layer if cl != null else -999))

func _ensure_ui_accept_binding() -> void:
	if not InputMap.has_action("ui_accept"):
		InputMap.add_action("ui_accept")

	var has_gamepad := false
	for ev in InputMap.action_get_events("ui_accept"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_A:  # 0 (South/A)
			has_gamepad = true
			break
	if not has_gamepad:
		var jb := InputEventJoypadButton.new()
		jb.button_index = JOY_BUTTON_A
		InputMap.action_add_event("ui_accept", jb)

func _pick_city_fact(name: String) -> String:
	if CITY_FACTS.has(name):
		var arr: Array = CITY_FACTS[name]
		if arr.size() > 0:
			var idx := _rng.randi_range(0, arr.size() - 1)
			return String(arr[idx])
	return ""

func _process(delta: float) -> void:
	if _camera != null:
		var target_global := to_global(_marker_pos)
		_camera.global_position = target_global

		var curr := _camera.zoom.x
		if abs(curr - _target_zoom) > 0.0001:
			var t := zoom_lerp_speed * delta
			if t > 1.0:
				t = 1.0
			var new_zoom = lerp(curr, _target_zoom, t)
			_camera.zoom = Vector2(new_zoom, new_zoom)

	# selected-city pulse timer
	if _pulse_t < pulse_time:
		_pulse_t += delta
		if _pulse_t > pulse_time:
			_pulse_t = pulse_time
		queue_redraw()

func _input(event: InputEvent) -> void:
	# Enter / A button → go to main scene
	if event.is_action_pressed("ui_accept"):
		_go_to_main_scene()
		return

	# D-pad / arrow keys → cycle cities
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_next_city()
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_prev_city()
		return

func _go_to_main_scene() -> void:
	get_tree().paused = false

	# Chosen city right now
	var chosen := ""
	if _cities.size() > 0:
		chosen = String(_cities[_city_index].get("name", ""))

	# Persist globally (race scene reads this)
	if chosen != "":
		if Globals.has_method("set_selected_city"):
			Globals.set_selected_city(chosen)
			print("[Globals] set_selected_city -> ", chosen)
			print_stack()
		else:
			Globals.selected_city = chosen
		Engine.set_meta("selected_city_override", chosen)  # <-- important
		print("[WorldMap] set_selected_city -> ", chosen)

	var gp := get_node_or_null("/root/MidnightGrandPrix")
	if gp != null:
		# Hint GP about the city using whatever API it has
		if gp.has_method("set_next_city_name"):
			gp.call("set_next_city_name", chosen)
		elif gp.has_method("set_current_city_name"):
			gp.call("set_current_city_name", chosen)
		elif gp.has_method("set_last_city_name"):
			gp.call("set_last_city_name", chosen)
		# (Optional) try common properties if they exist
		for k in ["next_city_name", "current_city_name", "last_city_name"]:
			if k in gp:
				gp.set(k, chosen)

		# Now launch the race
		gp.race_scene = "res://Scenes/Main.tscn"
		gp.race_count = 20
		gp.grid_size  = 8
		if not gp.active and gp.has_method("start_gp"):
			gp.call("start_gp", 0)
		else:
			gp.enter_current_race()
		return

	# Fallback (no GP autoload)
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _draw() -> void:
	# marker
	draw_circle(_marker_pos, marker_radius, marker_color)
	var cross := 6.0
	draw_line(_marker_pos - Vector2(cross, 0), _marker_pos + Vector2(cross, 0), marker_color, 2.0)
	draw_line(_marker_pos - Vector2(0, cross), _marker_pos + Vector2(0, cross), marker_color, 2.0)

	# cities (dots + labels) with outline and selection pulse
	var font: Font = label_font
	if font == null:
		font = ThemeDB.fallback_font

	if _cities.size() > 0:
		var i := 0
		while i < _cities.size():
			var c: Dictionary = _cities[i]
			var p: Vector2 = c["pos"]

			var is_selected := i == _city_index
			var size_px := label_font_size
			var lbl_color := label_color
			var outline_px := map_label_outline_px
			var outline_col := map_label_outline_color
			var dot_r := city_dot_radius
			var ring_r := dot_r * 2.4
			var ring_col := selected_ring_color

			if is_selected:
				var s := _current_pulse_scale()
				size_px = int(round(float(label_font_size) * s))
				lbl_color = selected_label_color
				outline_px = selected_label_outline_px
				outline_col = selected_label_outline_color
				dot_r = selected_city_dot_radius * s
				ring_r = (dot_r + 2.0) * 1.6

			# Completed city → color red (unless it's the selected one, which keeps the selected styling)
			if not is_selected and _is_city_completed(String(c["name"])):
				lbl_color = completed_label_color

			if show_city_dots:
				if is_selected:
					draw_arc(p, ring_r, 0.0, TAU, 24, ring_col, 2.0)
				draw_circle(p, dot_r, city_dot_color)

			if show_city_labels:
				var text = c["name"]
				var pos := p + city_label_offset
				_draw_text_with_outline(font, pos, text, size_px, lbl_color, outline_px, outline_col)
			i += 1

# --- Public API --------------------------------------------------------------

func set_marker_lonlat(lon: float, lat: float, jump_camera: bool = false) -> void:
	_marker_pos = _lonlat_to_xy(lon, lat)
	queue_redraw()
	if jump_camera:
		if _camera != null:
			_camera.reset_smoothing()
			_camera.global_position = to_global(_marker_pos)

func set_marker_xy(p: Vector2, jump_camera: bool = false) -> void:
	_marker_pos = p
	queue_redraw()
	if jump_camera:
		if _camera != null:
			_camera.reset_smoothing()
			_camera.global_position = to_global(_marker_pos)

# --- Internals ---------------------------------------------------------------

func _resolve_camera() -> Camera2D:
	if camera_path == NodePath():
		return null
	var n := get_node_or_null(camera_path)
	if n == null:
		return null
	if n is Camera2D:
		return n
	return null

func _resolve_label(path: NodePath) -> Label:
	if path == NodePath():
		return null
	var n := get_node_or_null(path)
	if n == null:
		return null
	if n is Label:
		return n
	return null

func _style_ui_label(lbl: Label) -> void:
	if lbl == null:
		return
	if lbl.label_settings == null:
		lbl.label_settings = LabelSettings.new()
	var s := lbl.label_settings
	if ui_font != null:
		s.font = ui_font
	s.font_size = ui_font_size
	s.font_color = ui_color
	s.outline_size = ui_outline_px
	s.outline_color = ui_outline_color
	s.shadow_color = ui_shadow_color
	s.shadow_offset = ui_shadow_offset
	# prep pivot so scale pulses from center
	lbl.pivot_offset = lbl.size * 0.5

func _apply_camera_limits() -> void:
	if _camera == null:
		return
	var top_left: Vector2 = to_global(Vector2.ZERO)
	var bottom_right: Vector2 = to_global(Vector2(map_size))
	var min_x = min(top_left.x, bottom_right.x)
	var max_x = max(top_left.x, bottom_right.x)
	var min_y = min(top_left.y, bottom_right.y)
	var max_y = max(top_left.y, bottom_right.y)
	_camera.limit_left = int(min_x)
	_camera.limit_right = int(max_x)
	_camera.limit_top = int(min_y)
	_camera.limit_bottom = int(max_y)

func _setup_camera() -> void:
	if _camera == null:
		return
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = camera_smoothing_speed
	if enable_camera_limits:
		_apply_camera_limits()

func _build_map_texture_from_html() -> void:
	var img := Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	img.fill(background_color)

	var file_exists := FileAccess.file_exists(html_path)
	if file_exists:
		var f := FileAccess.open(html_path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			var re := RegEx.new()
			re.compile("\\\"longitude\\\"\\s*:\\s*([-\\d\\.]+)\\s*,\\s*\\\"latitude\\\"\\s*:\\s*([-\\d\\.]+)")
			var matches := re.search_all(txt)
			var i := 0
			while i < matches.size():
				var m := matches[i]
				var lon := m.get_string(1).to_float()
				var lat := m.get_string(2).to_float()
				var p := _lonlat_to_xy(lon, lat)
				_blit_pixel(img, p, pixel_size, pixel_color)
				i += 1

	if _map_sprite == null:
		_map_sprite = Sprite2D.new()
		_map_sprite.centered = false
		add_child(_map_sprite)
		_map_sprite.z_index = -1

	var tex := ImageTexture.create_from_image(img)
	_map_sprite.texture = tex

	if _marker_pos == Vector2.ZERO:
		_marker_pos = _lonlat_to_xy(0.0, 0.0)
		queue_redraw()

func _blit_pixel(img: Image, center: Vector2, size_px: int, col: Color) -> void:
	var half := float(size_px) * 0.5
	var start_x := int(round(center.x - half))
	var start_y := int(round(center.y - half))
	var end_x := start_x + size_px
	var end_y := start_y + size_px
	var x := start_x
	while x < end_x:
		var y := start_y
		while y < end_y:
			if x >= 0 and y >= 0 and x < map_size.x and y < map_size.y:
				img.set_pixel(x, y, col)
			y += 1
		x += 1

func _lonlat_to_xy(lon: float, lat: float) -> Vector2:
	var x := (lon + 180.0) / 360.0 * float(map_size.x)
	var y := (90.0 - lat) / 180.0 * float(map_size.y)
	return Vector2(x, y)

# --- Cities / cycling --------------------------------------------------------

func _init_cities() -> void:
	_cities.clear()
	var i := 0
	while i < CITY_DATA.size():
		var c = CITY_DATA[i]
		var p := _lonlat_to_xy(c["lon"], c["lat"])
		_cities.append({
			"name": c["name"],
			"lon": c["lon"],
			"lat": c["lat"],
			"pos": p
		})
		i += 1
	queue_redraw()

func _goto_city(idx: int, jump: bool) -> void:
	if _cities.size() == 0:
		return
	_city_index = clamp(idx, 0, _cities.size() - 1)
	var c: Dictionary = _cities[_city_index]
	set_marker_xy(c["pos"], jump)

	Globals.set_selected_city(String(c["name"]))

	_update_ui_for_city(c)
	_pulse_ui_label(_title)
	_pulse_ui_label(_info)

	_pulse_t = 0.0
	queue_redraw()

	# NEW: live preview of the selected track in the Minimap
	_preview_minimap_for_city(String(c["name"]))

func _next_city() -> void:
	if _cities.size() == 0:
		return
	var idx := _city_index + 1
	if idx >= _cities.size():
		idx = 0
	_goto_city(idx, cycle_jumps_camera)

func _prev_city() -> void:
	if _cities.size() == 0:
		return
	var idx := _city_index - 1
	if idx < 0:
		idx = _cities.size() - 1
	_goto_city(idx, cycle_jumps_camera)

# --- Zoom helpers ------------------------------------------------------------

func _zoom_in() -> void:
	_set_target_zoom(false)

func _zoom_out() -> void:
	_set_target_zoom(true)

func _set_target_zoom(zoom_out: bool) -> void:
	if _camera == null:
		return
	var z := _target_zoom
	var step := 1.0 + zoom_step
	if zoom_out:
		z = z * step
	else:
		z = z / step
	z = clamp(z, zoom_min, zoom_max)
	_target_zoom = z

# --- Drawing helpers ---------------------------------------------------------

func _draw_text_with_outline(font: Font, pos: Vector2, text: String, font_size: int, color: Color, outline_px: int, outline_color: Color) -> void:
	# simple shadow for readability
	var has_shadow := ui_shadow_offset != Vector2.ZERO
	if has_shadow:
		draw_string(font, pos + ui_shadow_offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, ui_shadow_color)

	# outline (draw around center)
	if outline_px > 0:
		var dx := -outline_px
		while dx <= outline_px:
			var dy := -outline_px
			while dy <= outline_px:
				if dx != 0 or dy != 0:
					draw_string(font, pos + Vector2(dx, dy), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, outline_color)
				dy += 1
			dx += 1

	# fill
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _current_pulse_scale() -> float:
	if pulse_time <= 0.0:
		return 1.0
	var t := _pulse_t / pulse_time
	if t > 1.0:
		t = 1.0
	# easeOutQuad
	var ease := 1.0 - (1.0 - t) * (1.0 - t)
	var s := 1.0 + (pulse_scale - 1.0) * (1.0 - ease)
	return s

# --- UI helpers --------------------------------------------------------------

func _update_ui_for_city(c: Dictionary) -> void:
	# Build strings
	var name_str := String(c["name"])
	var lat := float(c["lat"])
	var lon := float(c["lon"])
	var fact := _pick_city_fact(name_str)

	var ll_plain := "Lat: " + str(round(lat * 100.0) / 100.0) + "   Lon: " + str(round(lon * 100.0) / 100.0)
	var ll_colored := "[color=#FFD166]" + ll_plain + "[/color]"  # gold coords
	var info_bbcode := ll_colored
	if fact != "":
		info_bbcode = fact + "\n" + ll_colored

	# --- Title (Label or RichTextLabel; with fallbacks) ---
	if _title != null:
		_title.text = name_str
	else:
		var tnode := get_node_or_null(title_label_path)
		if tnode == null:
			tnode = get_node_or_null("CanvasLayer/Control/Title")
		if tnode != null:
			tnode.set("text", name_str)

	# --- Info (Label or RichTextLabel; with fallbacks) ---
	var inode: Node = _info
	if inode == null:
		inode = get_node_or_null(info_label_path)
		if inode == null:
			inode = get_node_or_null("CanvasLayer/Control/Info")

	if inode == null:
		return

	# RichTextLabel path → outline + colored Lat/Lon via BBCode
	if inode is RichTextLabel:
		var r := inode as RichTextLabel
		r.bbcode_enabled = true
		# theme overrides for outline and base color
		r.add_theme_color_override("default_color", ui_color)
		r.add_theme_color_override("outline_color", ui_outline_color)
		r.add_theme_constant_override("outline_size", ui_outline_px)
		r.bbcode_text = info_bbcode
		r.fit_content = true
	# Label path → outline via LabelSettings (Labels can't color substrings)
	elif inode is Label:
		var lbl := inode as Label
		if lbl.label_settings == null:
			lbl.label_settings = LabelSettings.new()
		var s := lbl.label_settings
		if ui_font != null:
			s.font = ui_font
		s.font_size = ui_font_size
		s.font_color = ui_color
		s.outline_size = ui_outline_px
		s.outline_color = ui_outline_color
		s.shadow_color = ui_shadow_color
		s.shadow_offset = ui_shadow_offset

		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var info_plain := ll_plain
		if fact != "":
			info_plain = fact + "\n" + ll_plain
		lbl.text = info_plain

func _pulse_ui_label(lbl: Label) -> void:
	if lbl == null:
		return
	lbl.pivot_offset = lbl.size * 0.5
	var base_col := lbl.modulate
	lbl.modulate = ui_flash_color
	var tw1 := create_tween()
	tw1.tween_property(lbl, "scale", Vector2(ui_pulse_scale, ui_pulse_scale), ui_pulse_time * 0.5)
	tw1.tween_property(lbl, "scale", Vector2.ONE, ui_pulse_time * 0.5)
	var tw2 := create_tween()
	tw2.tween_property(lbl, "modulate", base_col, ui_pulse_time)

func _is_city_completed(name: String) -> bool:
	var gp := get_node_or_null("/root/MidnightGrandPrix")
	if gp == null:
		return false

	# Prefer the helper if present
	if gp.has_method("is_city_completed"):
		return bool(gp.call("is_city_completed", name))

	# Fallback: read the array directly
	var arr = gp.get("completed_cities")
	if arr is PackedStringArray:
		return (arr as PackedStringArray).has(name)
	if arr is Array:
		return (arr as Array).has(name)
	return false

func _find_city_index_by_name(name: String) -> int:
	var i := 0
	while i < _cities.size():
		var c: Dictionary = _cities[i]
		if String(c.get("name","")) == name:
			return i
		i += 1
	return -1

func _find_minimap() -> Node:
	var mm := get_node_or_null(^"CanvasLayer/Control/Minimap")
	if mm == null:
		mm = get_tree().get_root().find_child("Minimap", true, false)
	return mm

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

func _load_points_from_json(p: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not ResourceLoader.exists(p):
		return out
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return out
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return out

	var keys := ["points_uv", "points", "uv"]
	var arr: Array = []
	var i := 0
	while i < keys.size():
		var k := String(keys[i])
		if data.has(k):
			var v = data[k]
			if v is Array:
				arr = v
				break
		i += 1

	for q in arr:
		if q is Array and q.size() >= 2:
			out.append(Vector2(float(q[0]), float(q[1])))
	return out

func _preview_minimap_for_city(name: String) -> void:
	var mm := _find_minimap()
	if mm == null:
		prints("[WorldMap] preview", name, "no Minimap node found")
		return

	var pts := PackedVector2Array()
	var slug := _slugify_city(name)

	# 0) Make sure DB is loaded
	if Engine.has_singleton("TracksDataBase"):
		var db0 := get_node_or_null("/root/TracksDataBase")
		if db0 != null and db0.has_method("reload"):
			db0.call("reload")

	# 1) Try DB by name, then slug
	var cfg: Resource = null
	if Engine.has_singleton("TracksDataBase"):
		var db := get_node_or_null("/root/TracksDataBase")
		if db != null:
			if db.has_method("get_config"):
				cfg = db.call("get_config", name)
				if cfg == null:
					cfg = db.call("get_config", slug)

	if cfg is TrackConfig:
		var tc := cfg as TrackConfig
		if tc.path_points_uv.size() >= 2:
			pts = tc.path_points_uv
			prints("[WorldMap] preview", name, "from TrackConfig.tres (DB)", pts.size())

	# 1a) If DB gave us a TrackConfig but no points, look for a sidecar next to the .tres
	if pts.size() < 2 and cfg is TrackConfig:
		var rp := ""
		if "resource_path" in cfg:
			rp = String(cfg.resource_path)
		if rp != "" and rp.ends_with(".tres"):
			var dir := rp.get_base_dir()
			var tried := [dir + "/path.json", dir + "/" + slug + ".json"]
			var j := 0
			while j < tried.size() and pts.size() < 2:
				var pj := String(tried[j])
				var a := _load_points_from_json(pj)
				if a.size() >= 2:
					pts = a
					prints("[WorldMap] preview", name, "from TracksDB sidecar:", pj, pts.size())
				j += 1

	# 2) No DB hit? Load the .tres directly and try again
	if pts.size() < 2:
		var direct := "res://TracksDB/" + slug + "/" + slug + ".tres"
		if ResourceLoader.exists(direct):
			var cfg2 := load(direct)
			if cfg2 is TrackConfig:
				var tc2 := cfg2 as TrackConfig
				if tc2.path_points_uv.size() >= 2:
					pts = tc2.path_points_uv
					prints("[WorldMap] preview", name, "from TrackConfig.tres (direct)", pts.size())
				if pts.size() < 2:
					var dir2 := direct.get_base_dir()
					var tried2 := [dir2 + "/path.json", dir2 + "/" + slug + ".json"]
					var k := 0
					while k < tried2.size() and pts.size() < 2:
						var pj2 := String(tried2[k])
						var b := _load_points_from_json(pj2)
						if b.size() >= 2:
							pts = b
							prints("[WorldMap] preview", name, "from TracksDB sidecar (direct):", pj2, pts.size())
						k += 1

	# 3) Legacy folder fallback
	if pts.size() < 2:
		var legacy := "res://Tracks/" + slug + "/path.json"
		var c := _load_points_from_json(legacy)
		if c.size() >= 2:
			pts = c
			prints("[WorldMap] preview", name, "from Tracks/ path.json:", legacy, pts.size())

	# 4) Push to Minimap (or clear)
	if pts.size() >= 2 and mm.has_method("set_preview_points_uv"):
		mm.call("set_preview_points_uv", pts)
		prints("[WorldMap] preview", name, "pts:", pts.size())
	elif mm.has_method("clear_preview"):
		mm.call("clear_preview")
		prints("[WorldMap] preview", name, "pts:", 0)
