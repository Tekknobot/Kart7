extends Control
class_name LeaderboardRow

@export var flash_color_gain: Color = Color(0.30, 1.00, 0.45, 0.90)
@export var flash_color_loss: Color = Color(1.00, 0.40, 0.40, 0.90)
@export var player_highlight: Color = Color(0.95, 0.90, 0.20, 0.20)
@export var neutral_bg: Color       = Color(0, 0, 0, 0)

var racer: Node = null
var id: int = 0
var current_place: int = 0
var prev_place: int = 0
var is_player: bool = false

@export var L_place: Label     
@export var L_arrow: Label     
@export var L_name: Label      
@export var L_lap: Label       
@export var L_speed: Label     
@export var L_gap: Label       
@export var BG: ColorRect 

var _tween: Tween = null

func _ready() -> void:
	# --- Set consistent column widths ---
	L_place.custom_minimum_size.x = 40
	L_arrow.custom_minimum_size.x = 20
	L_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	L_lap.custom_minimum_size.x = 60
	L_speed.custom_minimum_size.x = 80
	L_gap.custom_minimum_size.x = 80

	# --- Align text ---
	L_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	L_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	L_name.horizontal_alignment  = HORIZONTAL_ALIGNMENT_LEFT
	L_lap.horizontal_alignment   = HORIZONTAL_ALIGNMENT_CENTER
	L_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	L_gap.horizontal_alignment   = HORIZONTAL_ALIGNMENT_RIGHT

func setup(r: Node, initial_place: int, lap: int, is_player_row: bool) -> void:
	racer = r
	id = r.get_instance_id()
	is_player = is_player_row
	prev_place = initial_place
	current_place = initial_place
	_refresh_static()
	set_stats(initial_place, lap, 0.0, 0.0)

func _refresh_static() -> void:
	var nm: String = ""
	if racer != null:
		nm = racer.name
	L_name.text = nm
	L_place.text = str(current_place)
	L_arrow.text = "•"
	if is_player:
		_set_bg(player_highlight)
	else:
		_set_bg(neutral_bg)

func set_stats(place: int, lap: int, speed: float, gap_s: float) -> void:
	prev_place = current_place
	current_place = place
	L_place.text = str(place)

	if prev_place != place:
		var up: bool = place < prev_place
		if up:
			L_arrow.text = "↑"
		else:
			L_arrow.text = "↓"
		_flash(up)
	else:
		L_arrow.text = "•"

	L_lap.text = "Lap " + str(lap + 1)
	L_speed.text = String.num(speed, 0) + " u/s"

	if gap_s <= 0.01:
		L_gap.text = "—"
	else:
		L_gap.text = "+" + String.num(gap_s, 2) + "s"

func _flash(gained: bool) -> void:
	if _tween:
		_tween.kill()
	if gained:
		BG.color = flash_color_gain
	else:
		BG.color = flash_color_loss

	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(BG, "color:a", 0.0, 0.45).from(0.90)
	_tween.tween_callback(func():
		if is_player:
			BG.color = player_highlight
		else:
			BG.color = neutral_bg
	)

func _set_bg(c: Color) -> void:
	BG.color = c
