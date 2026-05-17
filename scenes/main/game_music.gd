extends Node

const TRACKS: Array[String] = [
	"res://assets/sfx/game_music_1.mp3",
	"res://assets/sfx/game_music_2.mp3",
	"res://assets/sfx/game_music_3.mp3",
	"res://assets/sfx/game_music_4.mp3",
	"res://assets/sfx/game_music_5.mp3",
	"res://assets/sfx/game_music_6.mp3",
]

var playlist: Array[String] = []
var current_index := 0

@onready var player: AudioStreamPlayer = $AudioStreamPlayer

func _ready() -> void:
	_build_shuffled_playlist()
	current_index = randi() % playlist.size()
	player.finished.connect(_on_finished)
	Multihelper.player_registered.connect(_on_player_registered, CONNECT_ONE_SHOT)

func _on_player_registered() -> void:
	_play(current_index)

func _build_shuffled_playlist() -> void:
	playlist = TRACKS.duplicate()
	playlist.shuffle()

func _play(index: int) -> void:
	var stream := load(playlist[index]) as AudioStreamMP3
	stream.loop = false
	player.stream = stream
	player.play()

func _on_finished() -> void:
	current_index += 1
	if current_index >= playlist.size():
		# Reshuffle for next loop, avoid repeating same opening track
		var last_track := playlist[playlist.size() - 1]
		_build_shuffled_playlist()
		if playlist[0] == last_track and playlist.size() > 1:
			playlist.push_back(playlist.pop_front())
		current_index = 0
	_play(current_index)
