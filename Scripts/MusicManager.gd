extends Node

@export var music_tracks: Array[AudioStream]   # drop your music tracks here in the inspector
@export var bus_name: String = "Music"         # which audio bus to play through

@onready var player: AudioStreamPlayer = AudioStreamPlayer.new()

var _playlist: Array[AudioStream] = []
var _track_index: int = 0

func _ready() -> void:
	if music_tracks.is_empty():
		push_warning("MusicManager: no tracks assigned.")
		return
	
	# Set up player
	player.bus = bus_name
	player.autoplay = false
	player.stream_paused = false
	add_child(player)

	# Make a shuffled playlist
	_playlist = music_tracks.duplicate()
	_playlist.shuffle()
	_track_index = 0

	# Connect end signal
	player.finished.connect(_on_track_finished)

	# Start the first track
	_play_current_track()

func _play_current_track() -> void:
	if _playlist.is_empty():
		return
	player.stream = _playlist[_track_index]
	player.play()
	print("Now playing: ", player.stream.resource_path)

func _on_track_finished() -> void:
	# Advance to next track
	_track_index += 1
	if _track_index >= _playlist.size():
		# reshuffle once we run out
		_playlist.shuffle()
		_track_index = 0
	_play_current_track()

# Optional public API
func skip_track() -> void:
	player.stop()
	_on_track_finished()

func stop_music() -> void:
	player.stop()
