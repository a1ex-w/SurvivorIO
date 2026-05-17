extends Control

const CONFIG_PATH := "user://settings.cfg"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(2560, 1440),
	Vector2i(1920, 1080),
	Vector2i(1600, 900),
	Vector2i(1280, 720),
]
const RESOLUTION_LABELS: Array[String] = [
	"2560 × 1440",
	"1920 × 1080",
	"1600 × 900",
	"1280 × 720",
]

@onready var settings_overlay: Control = $SettingsOverlay
@onready var resolution_dropdown: OptionButton = $SettingsOverlay/SettingsPanel/VBox/ResolutionRow/ResolutionDropdown
@onready var volume_slider: HSlider = $SettingsOverlay/SettingsPanel/VBox/VolumeRow/VolumeSlider
@onready var volume_percent: Label = $SettingsOverlay/SettingsPanel/VBox/VolumeRow/VolumePercent
@onready var music_player: AudioStreamPlayer = $MusicPlayer

var _opened_from_game := false
var _music_stopped := false

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) == OK:
		AudioServer.set_bus_volume_db(0, linear_to_db(config.get_value("audio", "volume", 1.0)))

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", db_to_linear(AudioServer.get_bus_volume_db(0)))
	config.save(CONFIG_PATH)

func _ready():
	if OS.has_feature("dedicated_server"):
		start_server()
	_setup_resolution_dropdown()
	_load_settings()
	volume_slider.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	volume_percent.text = "%d%%" % roundi(volume_slider.value * 100)
	if not _music_stopped:
		var stream := load("res://assets/sfx/menu_music.mp3") as AudioStreamMP3
		stream.loop = true
		music_player.stream = stream
		music_player.play()

func _setup_resolution_dropdown() -> void:
	var current := DisplayServer.window_get_size()
	var current_index := 0
	for i in range(RESOLUTIONS.size()):
		resolution_dropdown.add_item(RESOLUTION_LABELS[i], i)
		if RESOLUTIONS[i] == current:
			current_index = i
	resolution_dropdown.select(current_index)

func start_server():
	Multihelper.create_game()

func _stop_music() -> void:
	_music_stopped = true
	if music_player.playing:
		music_player.stop()

func _on_public_lobby_pressed():
	_stop_music()
	Multihelper.join_game()

func _on_host_test_server_pressed():
	_stop_music()
	Multihelper.create_game()

func _on_join_test_server_pressed():
	_stop_music()
	Multihelper.join_game("localhost")

func _on_exit_pressed() -> void:
	get_tree().quit()

func open_settings() -> void:
	_opened_from_game = true
	$SubViewportContainer.hide()
	$TitleLabel.hide()
	$PanelContainer.hide()
	$SettingsButton.hide()
	settings_overlay.visible = true

func _on_settings_pressed() -> void:
	_opened_from_game = false
	settings_overlay.visible = true

func _on_settings_closed() -> void:
	settings_overlay.visible = false
	if _opened_from_game:
		$SubViewportContainer.show()
		$TitleLabel.show()
		$PanelContainer.show()
		$SettingsButton.show()
		hide()

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(value))
	volume_percent.text = "%d%%" % roundi(value * 100)
	_save_settings()

func _on_resolution_selected(index: int) -> void:
	var res := RESOLUTIONS[index]
	DisplayServer.window_set_size(res)
	# Re-center window on screen
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i((screen - res) / 2))
