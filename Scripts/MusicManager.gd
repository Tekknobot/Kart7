extends Node
class_name MusicManager

@export var music_tracks: Array[AudioStream]   # assign in Inspector
@export var bus_name: String = "Music"         # audio bus
@export var start_immediately := true          # begin on first scene

@onready var player: AudioStreamPlayer = AudioStreamPlayer.new()

var _playlist: Array[AudioStream] = []
var _track_index: int = 0
var _initialized := false

# --- Make this instance persistent & unique without Autoload ---
func _enter_tree() -> void:
	# If another MusicManager already exists anywhere, kill this one.
	for n in get_tree().get_nodes_in_group("_music_manager_singleton"):
		if n != self:
			queue_free()
			return

	# We are the one true instance.
	add_to_group("_music_manager_singleton")

	# Move out of the current scene so scene changes won't free us.
	if get_parent() != get_tree().get_root():
		call_deferred("_make_persistent")

func _make_persistent() -> void:
	if is_inside_tree():
		reparent(get_tree().get_root())

func _ready() -> void:
	# If we were queued for deletion (duplicate), do nothing.
	if is_queued_for_deletion():
		return
	# Guard against double-init (reparent can re-enter).
	if _initialized:
		return
	_initialized = true

	if music_tracks.is_empty():
		push_warning("MusicManager: no tracks assigned.")
		return

	# Set up player once
	player.bus = bus_name
	player.autoplay = false
	player.stream_paused = false
	add_child(player)

	# Build shuffled playlist
	_playlist = music_tracks.duplicate()
	_playlist.shuffle()
	_track_index = 0

	player.finished.connect(_on_track_finished)

	if start_immediately:
		_play_current_track()

func _play_current_track() -> void:
	if _playlist.is_empty():
		return
	player.stream = _playlist[_track_index]
	player.play()
	# print("Now playing: ", player.stream.resource_path)

func _on_track_finished() -> void:
	_track_index += 1
	if _track_index >= _playlist.size():
		_playlist.shuffle()
		_track_index = 0
	_play_current_track()

# --- Public API ---
func skip_track() -> void:
	if not is_instance_valid(player):
		return
	player.stop()
	_on_track_finished()

func stop_music() -> void:
	if not is_instance_valid(player):
		return
	player.stop()
