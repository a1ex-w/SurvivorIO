extends Control

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

var _opened_from_game := false

func _ready():
	if OS.has_feature("dedicated_server"):
		start_server()
	_setup_resolution_dropdown()

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

func _on_public_lobby_pressed():
	Multihelper.join_game()

func _on_host_test_server_pressed():
	Multihelper.create_game()

func _on_join_test_server_pressed():
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

func _on_resolution_selected(index: int) -> void:
	var res := RESOLUTIONS[index]
	DisplayServer.window_set_size(res)
	# Re-center window on screen
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(Vector2i((screen - res) / 2))
