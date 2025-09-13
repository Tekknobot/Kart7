# res://Scripts/Tracks/TracksDB.gd
extends Node
class_name TracksDB

const TRACKS_DB_ROOT := "res://TracksDB"   # .tres live here (any depth is fine)
const TRACKS_FS_ROOT := "res://Tracks"     # fallback folders: map.png/grass.png/collision.png

var _cfg_by_name: Dictionary = {}          # "Los Angeles" -> TrackConfig

func _ready() -> void:
	reload()

# --- public API ---------------------------------------------------------------

func reload() -> void:
	_cfg_by_name.clear()
	_auto_register_from_tracksdb()
	_auto_register_from_tracks_fs()
	# print_known_tracks()

func get_config(name: String) -> Resource:
	# exact match
	if _cfg_by_name.has(name):
		return _cfg_by_name[name]
	# slug/case tolerant match
	var wanted := _slugify(name)
	for k in _cfg_by_name.keys():
		if _slugify(String(k)) == wanted:
			return _cfg_by_name[k]
	return null

func get_all_names() -> Array:
	return _cfg_by_name.keys()

func first_config() -> Resource:
	for k in _cfg_by_name.keys():
		return _cfg_by_name[k]
	return null

# --- loaders -----------------------------------------------------------------

# 1) Load every TrackConfig .tres under res://TracksDB/**
func _auto_register_from_tracksdb() -> void:
	if not DirAccess.dir_exists_absolute(TRACKS_DB_ROOT):
		return
	_scan_db_dir(TRACKS_DB_ROOT)

func _scan_db_dir(path: String) -> void:
	# recursive
	for f in DirAccess.get_files_at(path):
		if not f.ends_with(".tres"): continue
		var full := path + "/" + f
		var res := load(full)
		if res == null: continue
		var name := ""
		if "display_name" in res and String(res.display_name) != "":
			name = String(res.display_name)
		else:
			name = _unslugify(f.substr(0, f.length() - 5))
		_cfg_by_name[name] = res
	for d in DirAccess.get_directories_at(path):
		_scan_db_dir(path + "/" + d)

# 2) Mirror any res://Tracks/<slug>/ folders into in-memory configs (optional)
func _auto_register_from_tracks_fs() -> void:
	if not DirAccess.dir_exists_absolute(TRACKS_FS_ROOT):
		return
	for slug in DirAccess.get_directories_at(TRACKS_FS_ROOT):
		var base := TRACKS_FS_ROOT + "/" + slug + "/"
		var p_map := base + "map.png"
		var p_grs := base + "grass.png"
		var p_col := base + "collision.png"
		if not (ResourceLoader.exists(p_map) and ResourceLoader.exists(p_grs) and ResourceLoader.exists(p_col)):
			continue

		var cfg := TrackConfig.new()
		cfg.display_name   = _unslugify(slug)
		cfg.track_texture  = load(p_map)
		cfg.grass_texture  = load(p_grs)
		cfg.collision_map  = load(p_col)

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
					cfg.path_points_uv = arr

		if not _cfg_by_name.has(cfg.display_name):
			_cfg_by_name[cfg.display_name] = cfg

# --- helpers ------------------------------------------------------------------

func _unslugify(slug: String) -> String:
	var spaced := slug.replace("_", " ")
	if spaced.length() == 0: return ""
	var out := ""
	var words := spaced.split(" ", false)
	for i in range(words.size()):
		var w: String = String(words[i])
		out += (w.substr(0,1).to_upper() + w.substr(1)) if w.length() > 0 else ""
		if i < words.size() - 1: out += " "
	return out

func _slugify(s: String) -> String:
	var t := s.strip_edges().to_lower()
	var out := ""
	for i in t.length():
		var ch := t.unicode_at(i)
		if (ch >= 97 and ch <= 122) or (ch >= 48 and ch <= 57): out += char(ch)
		elif ch == 32 or ch == 45 or ch == 95: out += "_"
		else: out += "_"
	return out

func print_known_tracks() -> void:
	for k in _cfg_by_name.keys():
		prints("Track:", k)

# Convenience for generating old-style _add(...) lines (optional)
func dump_add_lines_for_tres() -> void:
	for name in _cfg_by_name.keys():
		var res: Resource = _cfg_by_name[name]
		if "resource_path" in res and String(res.resource_path).ends_with(".tres"):
			print('_add("%s", "%s")' % [name, String(res.resource_path)])
