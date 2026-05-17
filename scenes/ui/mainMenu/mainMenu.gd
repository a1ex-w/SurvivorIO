extends Control

func _ready():
	if OS.has_feature("dedicated_server"):
		start_server()

func start_server():
	Multihelper.create_game()

func _on_public_lobby_pressed():
	Multihelper.join_game()

func _on_host_test_server_pressed():
	Multihelper.create_game()

func _on_join_test_server_pressed():
	Multihelper.join_game("localhost")
