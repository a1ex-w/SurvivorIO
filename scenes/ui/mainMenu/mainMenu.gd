extends Control

func _ready():
	if OS.has_feature("dedicated_server"):
		start_server()
	else:
		show_menu()

func start_server():
	$connectTimer.stop()
	Multihelper.create_game()

func show_menu():
	pass

func server_offline():
	$connectTimer.start()

func _on_hostDebugButton_pressed():
	Multihelper.create_game()

func _on_connect_timer_timeout():
	Multihelper.join_game()
