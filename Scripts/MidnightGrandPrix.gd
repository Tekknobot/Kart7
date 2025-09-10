extends Node

@export var tracks: PackedStringArray = []
@export var standings_scene: String = "res://Scenes/standings.tscn"
@export var grid_size: int = 8
@export var points_table: PackedInt32Array = PackedInt32Array([15,12,10,8,6,4,2,1])
@export var auto_start := false   # keep OFF; we’ll start from a button while testing

@export var world_map_scene: String = "res://Scenes/WorldMap.tscn"
@export var race_scene: String = "res://Scenes/Main.tscn"  # single scene used every race
@export var race_count: int = 20                           # how many races in the GP

var completed_cities: PackedStringArray = PackedStringArray()
var _current_race_city: String = ""   # captured when a race is entered

var active := false
var current_index := 0
var total_points := {}
var stats := {}
var uid_display := {}
var last_gain := {}
var last_race_index := -1
var player_uid := ""

signal gp_started(index:int)
signal gp_standings_ready(index:int)
signal gp_finished(winner_uid:String)

var last_city_name: String = ""
var last_race_was_replay: bool = false

func _ready() -> void:
	# Never force-start on boot unless you explicitly flip auto_start.
	if auto_start and tracks.size() > 0:
		call_deferred("start_gp", 0)

func start_gp(start_at := 0) -> void:
	active = true

	var last_index := -1
	if tracks.size() > 0:
		last_index = tracks.size() - 1
	else:
		last_index = race_count - 1
	if last_index < 0:
		last_index = 0

	current_index = clamp(start_at, 0, last_index)
	total_points.clear()
	stats.clear()
	uid_display.clear()
	last_gain.clear()
	last_race_index = -1
	player_uid = ""

	emit_signal("gp_started", current_index)
	_load_current_race()

func on_race_finished(board: Array, navigate: bool = true) -> void:
	if not active:
		return

	# Decide if this was a replay (city already completed)
	last_race_was_replay = false
	if _current_race_city != "":
		if completed_cities.has(_current_race_city):
			last_race_was_replay = true
		else:
			completed_cities.append(_current_race_city)  # first time only
			last_city_name = _current_race_city
			_save(false)

	# Points handling
	last_gain.clear()
	if last_race_was_replay:
		# replay: no points, no stats update
		for i in range(min(board.size(), grid_size)):
			var entry = board[i]
			var node: Node = entry["node"]
			var uid := _uid_for(node)
			var name := _display_name_for(node)
			uid_display[uid] = uid_display.get(uid, name)
			last_gain[uid] = 0
		# keep totals, wins/podiums/best_ms unchanged
	else:
		# real race: award as normal
		_award_points(board)

	last_race_index = current_index

	var p = board[0]["node"].get_tree().get_first_node_in_group("player")
	if p:
		player_uid = _uid_for(p)

	emit_signal("gp_standings_ready", current_index)

	if navigate:
		_show_standings()

func continue_from_standings() -> void:
	var last_index := -1
	if tracks.size() > 0:
		last_index = tracks.size() - 1
	else:
		last_index = race_count - 1

	# If that race was a replay, do NOT increment or finish—just go back to map
	if last_race_was_replay:
		last_race_was_replay = false
		_save(false)
		_go_to_world_map()
		return

	# Normal flow (counting race)
	if current_index >= last_index:
		emit_signal("gp_finished", _leader_uid())
		active = false
		_save(true)
		_go_to_world_map()
		return

	current_index += 1
	_save(false)
	_go_to_world_map()

func standings_rows() -> Array:
	var rows: Array = []
	for uid in total_points.keys():
		var st = stats.get(uid, {"wins":0,"podiums":0,"best_ms":-1})
		rows.append({
			"uid": uid,
			"name": String(uid_display.get(uid, uid)),
			"pts": int(total_points.get(uid, 0)),
			"gain": int(last_gain.get(uid, 0)),
			"wins": int(st.wins),
			"podiums": int(st.podiums),
			"best_ms": int(st.best_ms)
		})
	rows.sort_custom(Callable(self, "_cmp_rows"))
	for i in range(rows.size()):
		rows[i]["place"] = i + 1
	return rows

func _cmp_rows(a: Dictionary, b: Dictionary) -> bool:
	if a["pts"] != b["pts"]: return a["pts"] > b["pts"]
	if a["wins"] != b["wins"]: return a["wins"] > b["wins"]
	if a["podiums"] != b["podiums"]: return a["podiums"] > b["podiums"]
	var am = (a["best_ms"] if a["best_ms"] >= 0 else 999999999)
	var bm = (b["best_ms"] if b["best_ms"] >= 0 else 999999999)
	if am != bm: return am < bm
	return String(a["name"]) < String(b["name"])

func _award_points(board: Array) -> void:
	last_gain.clear()
	for i in range(min(board.size(), grid_size)):
		var entry = board[i]
		var node: Node = entry["node"]
		var uid := _uid_for(node)
		var name := _display_name_for(node)
		uid_display[uid] = uid_display.get(uid, name)

		var place := int(entry.get("place", i + 1))
		var idx := place - 1
		var pts := 0
		if idx >= 0 and idx < points_table.size(): pts = points_table[idx]
		total_points[uid] = int(total_points.get(uid, 0)) + pts
		last_gain[uid] = pts

		var st = stats.get(uid, {"wins":0,"podiums":0,"best_ms":-1})
		if place == 1: st.wins += 1
		if place <= 3: st.podiums += 1
		var best_ms := int(entry.get("best_ms", -1))
		if best_ms >= 0 and (st.best_ms < 0 or best_ms < st.best_ms): st.best_ms = best_ms
		stats[uid] = st
	_save(false)

func _uid_for(n: Node) -> String:
	if n == null: return ""
	if n.has_meta("racer_uid"): return String(n.get_meta("racer_uid"))
	if n.has_method("ReturnRacerUID"): return String(n.call("ReturnRacerUID"))
	if n.has_method("ReturnRacerName"): return String(n.call("ReturnRacerName"))
	return n.name

func _display_name_for(n: Node) -> String:
	if n == null: return "?"
	if n.has_method("ReturnRacerName"): return String(n.call("ReturnRacerName"))
	return n.name

func _leader_uid() -> String:
	var best := ""; var best_pts := -1
	for uid in total_points.keys():
		var pts := int(total_points[uid])
		if pts > best_pts: best_pts = pts; best = uid
		elif pts == best_pts and best != "":
			var a = stats.get(uid, {"wins":0,"podiums":0,"best_ms":999999999})
			var b = stats.get(best, {"wins":0,"podiums":0,"best_ms":999999999})
			if a.wins > b.wins or (a.wins == b.wins and a.podiums > b.podiums) or (a.wins == b.wins and a.podiums == b.podiums and a.best_ms < b.best_ms):
				best = uid
	return best

func _load_current_race() -> void:
	# record the selected city at race-entry time
	_current_race_city = ""
	var glb := get_node_or_null("/root/Globals")
	if glb != null:
		if glb.has_method("get_selected_city"):
			_current_race_city = String(glb.call("get_selected_city"))
		else:
			var v = glb.get("selected_city")
			if v != null:
				_current_race_city = String(v)

	# record the selected city at race-entry time
	_current_race_city = ""
	if glb != null:
		if glb.has_method("get_selected_city"):
			_current_race_city = String(glb.call("get_selected_city"))
		else:
			var v = glb.get("selected_city")
			if v != null:
				_current_race_city = String(v)
	
	if tracks.size() > 0:
		if current_index < 0 or current_index >= tracks.size():
			return
		call_deferred("_do_change_scene", tracks[current_index])
	else:
		if current_index < 0 or current_index >= race_count:
			return
		call_deferred("_do_change_scene", race_scene)

func _show_standings() -> void:
	call_deferred("_do_change_scene", standings_scene)

func _do_change_scene(path: String) -> void:
	if get_tree() == null:
		return
	get_tree().paused = false
	get_tree().change_scene_to_file(path)

# Save/Load
const SAVE_PATH := "user://gp_save.cfg"
func _save(finished: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("gp","index", current_index)
	cfg.set_value("gp","finished", finished)
	cfg.set_value("gp","points", total_points)
	cfg.set_value("gp","stats", stats)
	cfg.set_value("gp","names", uid_display)
	cfg.set_value("gp","last_gain", last_gain)
	cfg.set_value("gp","tracks", tracks)
	cfg.set_value("gp","grid", grid_size)
	cfg.set_value("gp","player_uid", player_uid)
	cfg.set_value("gp","completed_cities", completed_cities)
	cfg.set_value("gp","last_city_name", last_city_name)
	cfg.set_value("gp","completed_cities", completed_cities)
	cfg.set_value("gp","last_city_name", last_city_name)
	cfg.set_value("gp","last_race_was_replay", last_race_was_replay)
	
	cfg.save(SAVE_PATH)

func load_save() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK: return false
	current_index = int(cfg.get_value("gp","index",0))
	total_points = cfg.get_value("gp","points",{})
	stats = cfg.get_value("gp","stats",{})
	uid_display = cfg.get_value("gp","names",{})
	last_gain = cfg.get_value("gp","last_gain",{})
	tracks = cfg.get_value("gp","tracks", tracks)
	grid_size = int(cfg.get_value("gp","grid", grid_size))
	player_uid = String(cfg.get_value("gp","player_uid",""))
	last_city_name = String(cfg.get_value("gp","last_city_name", ""))

	var cc = cfg.get_value("gp","completed_cities", PackedStringArray())
	if cc is PackedStringArray:
		completed_cities = cc
	elif cc is Array:
		completed_cities = PackedStringArray(cc)
	else:
		completed_cities = PackedStringArray()

	last_city_name = String(cfg.get_value("gp","last_city_name", ""))
	last_race_was_replay = bool(cfg.get_value("gp","last_race_was_replay", false))

	if cc is PackedStringArray:
		completed_cities = cc
	elif cc is Array:
		completed_cities = PackedStringArray(cc)
	else:
		completed_cities = PackedStringArray()
	
	return true

func enter_current_race() -> void:
	# If a GP is already running, (re)enter the current race without resetting points
	if active:
		_load_current_race()
		return
	# If not active yet, start from race 0 (uses your configured race_scene/tracks)
	start_gp(0)

func _go_to_world_map() -> void:
	if world_map_scene != "":
		call_deferred("_do_change_scene", world_map_scene)
	else:
		push_error("world_map_scene not set; cannot go to map")
