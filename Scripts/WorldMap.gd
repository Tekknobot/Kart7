extends Node2D
class_name WorldMap

@export var html_path: String = "res://amCharts.pixelMap.html"
@export var map_size: Vector2i = Vector2i(1920, 960)
@export var pixel_size: int = 5
@export var pixel_color: Color = Color(129.0/255.0, 129.0/255.0, 129.0/255.0, 1.0)
@export var background_color: Color = Color(80.0/255.0, 80.0/255.0, 80.0/255.0, 1.0)

@export var camera_path: NodePath
@export var camera_smoothing_speed: float = 5.0
@export var enable_camera_limits: bool = true

@export var marker_color: Color = Color(1.0, 0.35, 0.35, 1.0)
@export var marker_radius: float = 8.0

# --- City label styling ---
@export var show_city_dots: bool = true
@export var city_dot_radius: float = 3.0
@export var city_dot_color: Color = Color(1.0, 0.9, 0.3, 1.0)

@export var show_city_labels: bool = true
@export var label_font: Font
@export var label_font_size: int = 16
@export var label_color: Color = Color(1, 1, 1, 1)
@export var city_label_offset: Vector2 = Vector2(8, -8)

# --- Zoom controls ---
@export var zoom_min: float = 0.5
@export var zoom_max: float = 4.0
@export var zoom_step: float = 0.2     # multiplicative (1.0 +/- zoom_step)
@export var zoom_lerp_speed: float = 8.0

# --- City cycle options ---
@export var cycle_jumps_camera: bool = false
@export var start_on_city_index: int = 0

var _marker_pos := Vector2.ZERO
var _map_sprite: Sprite2D = null
var _camera: Camera2D = null

var _target_zoom: float = 1.0

# City data → computed at runtime into _cities with .pos
const CITY_DATA := [
	{"name":"New York", "lon":-74.0060, "lat":40.7128},
	{"name":"Los Angeles", "lon":-118.2437, "lat":34.0522},
	{"name":"Mexico City", "lon":-99.1332, "lat":19.4326},
	{"name":"Sao Paulo", "lon":-46.6333, "lat":-23.5505},
	{"name":"Buenos Aires", "lon":-58.3816, "lat":-34.6037},
	{"name":"London", "lon":-0.1276, "lat":51.5074},
	{"name":"Paris", "lon":2.3522, "lat":48.8566},
	{"name":"Madrid", "lon":-3.7038, "lat":40.4168},
	{"name":"Cairo", "lon":31.2357, "lat":30.0444},
	{"name":"Lagos", "lon":3.3792, "lat":6.5244},
	{"name":"Moscow", "lon":37.6173, "lat":55.7558},
	{"name":"Istanbul", "lon":28.9784, "lat":41.0082},
	{"name":"Dubai", "lon":55.2708, "lat":25.2048},
	{"name":"Mumbai", "lon":72.8777, "lat":19.0760},
	{"name":"Singapore", "lon":103.8198, "lat":1.3521},
	{"name":"Beijing", "lon":116.4074, "lat":39.9042},
	{"name":"Seoul", "lon":126.9780, "lat":37.5665},
	{"name":"Tokyo", "lon":139.6917, "lat":35.6895},
	{"name":"Sydney", "lon":151.2093, "lat":-33.8688},
	{"name":"Toronto", "lon":-79.3832, "lat":43.6532},
]

var _cities: Array = []           # each = {"name": String, "lon": float, "lat": float, "pos": Vector2}
var _city_index: int = 0

func _ready() -> void:
	_camera = _resolve_camera()
	_setup_camera()
	_build_map_texture_from_html()
	_init_cities()
	_city_index = clamp(start_on_city_index, 0, max(CITY_DATA.size() - 1, 0))
	if CITY_DATA.size() > 0:
		_goto_city(_city_index, true)
	_target_zoom = 1.0
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if _camera != null:
		# follow marker (Camera2D smoothing handles the ease)
		var target_global := to_global(_marker_pos)
		_camera.global_position = target_global

		# smooth zoom to target
		var curr := _camera.zoom.x
		if abs(curr - _target_zoom) > 0.0001:
			var t := zoom_lerp_speed * delta
			if t > 1.0:
				t = 1.0
			var new_zoom = lerp(curr, _target_zoom, t)
			_camera.zoom = Vector2(new_zoom, new_zoom)

func _unhandled_input(event: InputEvent) -> void:
	# D-pad / arrow keys → cycle cities
	if event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
		_next_city()
	if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
		_prev_city()

	# Zoom keys
	if event is InputEventKey and event.pressed and event.echo == false:
		var k := (event as InputEventKey).keycode
		if k == Key.KEY_EQUAL:
			_zoom_in()
		if k == Key.KEY_MINUS:
			_zoom_out()

	# Mouse wheel zoom
	if event is InputEventMouseButton and event.pressed and event.is_echo() == false:
		var b := (event as InputEventMouseButton).button_index
		if b == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		if b == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()

func _draw() -> void:
	# marker
	draw_circle(_marker_pos, marker_radius, marker_color)
	var cross := 6.0
	draw_line(_marker_pos - Vector2(cross, 0), _marker_pos + Vector2(cross, 0), marker_color, 2.0)
	draw_line(_marker_pos - Vector2(0, cross), _marker_pos + Vector2(0, cross), marker_color, 2.0)

	# cities (dots + labels)
	var font: Font = label_font
	if font == null:
		font = ThemeDB.fallback_font

	if _cities.size() > 0:
		var i := 0
		while i < _cities.size():
			var c: Dictionary = _cities[i]
			var p: Vector2 = c["pos"]
			if show_city_dots:
				draw_circle(p, city_dot_radius, city_dot_color)

			if show_city_labels:
				var text = c["name"]
				var pos := p + city_label_offset
				draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label_font_size, label_color)
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

func _setup_camera() -> void:
	if _camera == null:
		return
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = camera_smoothing_speed
	if enable_camera_limits:
		_apply_camera_limits()

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

func _build_map_texture_from_html() -> void:
	var img := Image.create(map_size.x, map_size.y, false, Image.FORMAT_RGBA8)
	img.fill(background_color)

	var count := 0
	var file_exists := FileAccess.file_exists(html_path)
	if file_exists:
		var f := FileAccess.open(html_path, FileAccess.READ)
		if f != null:
			var txt := f.get_as_text()
			var re := RegEx.new()
			re.compile("\\\"longitude\\\"\\s*:\\s*([-\\d\\.]+)\\s*,\\s*\\\"latitude\\\"\\s*:\\s*([-\\d\\.]+)")
			var matches := re.search_all(txt)
			for m in matches:
				var lon := m.get_string(1).to_float()
				var lat := m.get_string(2).to_float()
				var p := _lonlat_to_xy(lon, lat)
				_blit_pixel(img, p, pixel_size, pixel_color)
				count += 1

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
