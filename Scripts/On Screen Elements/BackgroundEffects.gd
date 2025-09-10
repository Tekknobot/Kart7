# BackgroundEffects.gd
extends Node2D

@export var _skyLine : Sprite2D
@export var _treeLine : Sprite2D

# --- Time of day selection ---
const TIME_DAWN := 0
const TIME_DAY := 1
const TIME_SUNSET := 2
@export var time_of_day: int = TIME_DAY   # 0=Dawn, 1=Day, 2=Sunset

# --- Strength (blend with original texture color) ---
@export var sky_strength:  float = 1.0    # 0..1
@export var tree_strength: float = 1.0    # 0..1

# --- Palettes ---
@export var dawn_sky_color:    Color = Color(1.00, 0.80, 0.92, 1.0)
@export var dawn_tree_color:   Color = Color(1.00, 0.60, 0.50, 1.0)
@export var day_sky_color:     Color = Color(0.60, 0.80, 1.00, 1.0)
@export var day_tree_color:    Color = Color(0.48, 0.78, 0.46, 1.0)
@export var sunset_sky_color:  Color = Color(1.00, 0.64, 0.35, 1.0)
@export var sunset_tree_color: Color = Color(0.95, 0.45, 0.25, 1.0)

# --- Time-of-day randomization weights ---
@export var randomize_time_of_day_on_setup := true
@export var weight_dawn: float = 1.0
@export var weight_day: float = 1.0
@export var weight_sunset: float = 1.0

# --- Clear color behavior ---
@export var match_clear_color_to_sky := true
@export var night_clear_enabled := true                        # turn the feature on/off
@export var night_clear_chance: float = 0.25                   # chance (0..1) to use a night tint
@export var reroll_night_on_time_change := true                # re-roll when time-of-day changes
@export var night_clear_color: Color = Color(0.06, 0.08, 0.12, 1.0)  # deep navy
@export var night_tint_strength: float = 1.0                   # 0..1, 1 = full night color

var _rng := RandomNumberGenerator.new()
var _booted := false
var _use_night_clear := false

func _ready() -> void:
	if auto_setup_on_ready and not _booted:
		Setup()

@export var auto_setup_on_ready := true

@export var skyline_folder: String = "res://Textures/Tracks/Skylines/"   # where your .pngs live
@export var skyline_ext: String = ".png"                    # .png, .webp, etc
@export var skyline_map: Dictionary = {}                    # optional overrides: { "Tokyo": "res://custom/tokyo.webp" }
@export var default_skyline: Texture2D                      # fallback if not found

@export var treeline_folder: String = "res://Textures/Tracks/Treelines/"  # where your treeline .pngs live
@export var treeline_ext: String = ".png"                                  # .png, .webp, etc.
@export var treeline_map: Dictionary = {}                                   # optional overrides: { "Tokyo": "res://custom/trees_tokyo.webp" or Texture2D }
@export var default_treeline: Texture2D                                     # fallback if not found

var _sky_night_mat: ShaderMaterial = null

func Setup():
	_rng.randomize()
	if randomize_time_of_day_on_setup:
		_roll_time_of_day()
	_roll_night_clear()              # <<< roll night chance once at setup
	_apply_time_of_day_modulate()
	_apply_city_from_globals() 
	_booted = true

func Update(mapRotation : float) -> void:
	MoveBackgroundElements(_skyLine, mapRotation)
	MoveBackgroundElements(_treeLine, mapRotation)
	_apply_time_of_day_modulate()

func MoveBackgroundElements(element : Sprite2D, mapRotation : float) -> void:
	if element == null:
		return
	if element.texture == null:
		return
	var rotationDegree : float = rad_to_deg(mapRotation) / 360.0
	var scrollPosition : float = rotationDegree * element.texture.get_width()
	var rr := element.region_rect
	rr.position.x = -scrollPosition
	element.region_rect = rr

# --- Modulation --------------------------------------------------------------

func _apply_time_of_day_modulate() -> void:
	# Pick target palettes
	var sky_target := day_sky_color
	var tree_target := day_tree_color
	if time_of_day == TIME_DAWN:
		sky_target  = dawn_sky_color
		tree_target = dawn_tree_color
	elif time_of_day == TIME_DAY:
		sky_target  = day_sky_color
		tree_target = day_tree_color
	elif time_of_day == TIME_SUNSET:
		sky_target  = sunset_sky_color
		tree_target = sunset_tree_color

	# Mix toward targets by strength
	var sky_mix  := _blend_color(Color(1,1,1,1), sky_target,  clamp(sky_strength,  0.0, 1.0))
	var tree_mix := _blend_color(Color(1,1,1,1), tree_target, clamp(tree_strength, 0.0, 1.0))

	# --- Apply time-of-day modulation to sprites ---
	if _skyLine != null:
		_skyLine.modulate = sky_mix
	if _treeLine != null:
		_treeLine.modulate = tree_mix

	# Optionally keep engine clear color tied to time-of-day
	if match_clear_color_to_sky:
		var cc := Color(sky_mix.r, sky_mix.g, sky_mix.b, 1.0)
		if _use_night_clear:
			var t = clamp(night_tint_strength, 0.0, 1.0)
			cc = Color(
				lerp(cc.r, night_clear_color.r, t),
				lerp(cc.g, night_clear_color.g, t),
				lerp(cc.b, night_clear_color.b, t),
				1.0
			)
		RenderingServer.set_default_clear_color(cc)

func _blend_color(base: Color, tint: Color, t: float) -> Color:
	var tt := t
	if tt < 0.0:
		tt = 0.0
	if tt > 1.0:
		tt = 1.0
	return Color(
		lerp(base.r, tint.r, tt),
		lerp(base.g, tint.g, tt),
		lerp(base.b, tint.b, tt),
		lerp(base.a, tint.a, tt)
	)

# --- Time-of-day controls ---
func SetTimeOfDay(mode: int) -> void:
	time_of_day = mode
	if reroll_night_on_time_change:
		_roll_night_clear()
	_apply_time_of_day_modulate()

func NextTimeOfDay() -> void:
	if time_of_day >= TIME_SUNSET:
		time_of_day = TIME_DAWN
	else:
		time_of_day += 1
	if reroll_night_on_time_change:
		_roll_night_clear()
	_apply_time_of_day_modulate()

func RerollTimeOfDay() -> void:
	_roll_time_of_day()
	if reroll_night_on_time_change:
		_roll_night_clear()
	_apply_time_of_day_modulate()

# --- Random rolls ---
func _roll_time_of_day() -> void:
	var wd = max(0.0, weight_dawn)
	var wy = max(0.0, weight_day)
	var ws = max(0.0, weight_sunset)
	var total = wd + wy + ws
	if total <= 0.0:
		wd = 1.0; wy = 1.0; ws = 1.0; total = 3.0

	var r = _rng.randf() * total
	if r < wd:
		time_of_day = TIME_DAWN
	else:
		r -= wd
		if r < wy:
			time_of_day = TIME_DAY
		else:
			time_of_day = TIME_SUNSET

func _roll_night_clear() -> void:
	if not night_clear_enabled:
		_use_night_clear = false
		return
	var p = clamp(night_clear_chance, 0.0, 1.0)
	var r := _rng.randf()
	_use_night_clear = (r < p)

func _apply_city_from_globals() -> void:
	var glb := get_node_or_null("/root/Globals")
	if glb == null:
		return
	var name := ""
	if glb.has_method("get_selected_city"):
		name = String(glb.call("get_selected_city"))
	else:
		var val = glb.get("selected_city")
		if val != null:
			name = String(val)
	if name != "":
		SetCityAssetsByName(name)   # <<< set both skyline + treeline

func SetCityAssetsByName(name: String) -> void:
	SetCitySkylineByName(name)
	SetCityTreeLineByName(name)

func SetCityTreeLineByName(name: String) -> void:
	if _treeLine == null:
		return
	var tex := _resolve_treeline_texture(name)
	if tex != null:
		_treeLine.texture = tex

func _resolve_treeline_texture(name: String) -> Texture2D:
	# explicit override via dictionary (Texture2D or String path)
	if treeline_map.has(name):
		var v = treeline_map[name]
		if v is Texture2D:
			return v
		if v is String:
			if ResourceLoader.exists(v):
				var t := load(v)
				if t is Texture2D:
					return t

	# convention: <treeline_folder>/<slug><treeline_ext>
	var folder := treeline_folder
	if not folder.ends_with("/"):
		folder += "/"
	var slug := _slugify_city(name)
	var path := folder + slug + treeline_ext
	if ResourceLoader.exists(path):
		var t2 := load(path)
		if t2 is Texture2D:
			return t2

	return default_treeline

func SetCitySkylineByName(name: String) -> void:
	if _skyLine == null:
		return
	var tex := _resolve_skyline_texture(name)
	if tex != null:
		_skyLine.texture = tex

func _resolve_skyline_texture(name: String) -> Texture2D:
	# explicit override via dictionary (path or Texture2D)
	if skyline_map.has(name):
		var v = skyline_map[name]
		if v is Texture2D:
			return v
		if v is String:
			if ResourceLoader.exists(v):
				var t := load(v)
				if t is Texture2D:
					return t

	# convention: res://art/skylines/<slug><ext>
	var folder := skyline_folder
	if not folder.ends_with("/"):
		folder += "/"
	var slug := _slugify_city(name)
	var path := folder + slug + skyline_ext
	if ResourceLoader.exists(path):
		var t2 := load(path)
		if t2 is Texture2D:
			return t2

	return default_skyline

func _slugify_city(name: String) -> String:
	var s := name.to_lower()
	var out := ""
	var i := 0
	while i < s.length():
		var code := s.unicode_at(i)
		if (code >= 97 and code <= 122) or (code >= 48 and code <= 57):
			out += char(code)
		elif code == 32:
			out += "_"
		else:
			out += "_"
		i += 1
	return out
