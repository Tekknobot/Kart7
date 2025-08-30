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

# --- Dawn palette (soft pink/amber sky, warmer trees)
@export var dawn_sky_color:  Color = Color(1.00, 0.80, 0.92, 1.0)
@export var dawn_tree_color: Color = Color(1.00, 0.60, 0.50, 1.0)

# --- Day palette (blue sky, green trees)
@export var day_sky_color:   Color = Color(0.60, 0.80, 1.00, 1.0)
@export var day_tree_color:  Color = Color(0.48, 0.78, 0.46, 1.0)

# --- Sunset palette (warm orange sky, deeper orange/red trees)
@export var sunset_sky_color:  Color = Color(1.00, 0.64, 0.35, 1.0)
@export var sunset_tree_color: Color = Color(0.95, 0.45, 0.25, 1.0)

@export var randomize_time_of_day_on_setup := true
@export var weight_dawn: float = 1.0
@export var weight_day: float = 1.0
@export var weight_sunset: float = 1.0
var _rng := RandomNumberGenerator.new()

@export var auto_setup_on_ready := true
var _booted := false

func _ready() -> void:
	if auto_setup_on_ready and not _booted:
		Setup()

func Setup():
	_rng.randomize()
	if randomize_time_of_day_on_setup:
		_roll_time_of_day()
	_apply_time_of_day_modulate()
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

	if _skyLine != null:
		_skyLine.modulate = _blend_color(Color(1,1,1,1), sky_target, clamp(sky_strength, 0.0, 1.0))
	if _treeLine != null:
		_treeLine.modulate = _blend_color(Color(1,1,1,1), tree_target, clamp(tree_strength, 0.0, 1.0))

func _blend_color(base: Color, tint: Color, t: float) -> Color:
	# linear blend without ternaries
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

# --- Optional helpers to switch modes from code/UI ---
func SetTimeOfDay(mode: int) -> void:
	time_of_day = mode
	_apply_time_of_day_modulate()

func NextTimeOfDay() -> void:
	if time_of_day >= TIME_SUNSET:
		time_of_day = TIME_DAWN
	else:
		time_of_day += 1
	_apply_time_of_day_modulate()

func _roll_time_of_day() -> void:
	var wd = max(0.0, weight_dawn)
	var wy = max(0.0, weight_day)
	var ws = max(0.0, weight_sunset)
	var total = wd + wy + ws
	if total <= 0.0:
		wd = 1.0
		wy = 1.0
		ws = 1.0
		total = 3.0

	var r = _rng.randf() * total
	if r < wd:
		time_of_day = TIME_DAWN
	else:
		r -= wd
		if r < wy:
			time_of_day = TIME_DAY
		else:
			time_of_day = TIME_SUNSET

# optional: call this any time you want to re-roll during play
func RerollTimeOfDay() -> void:
	_roll_time_of_day()
	_apply_time_of_day_modulate()
