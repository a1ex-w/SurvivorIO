extends Control

func _ready():
	makePlayerList()
	Multihelper.player_registered.connect(makePlayerList)
	Multihelper.player_despawned.connect(makePlayerList)
	Multihelper.player_score_updated.connect(makePlayerList)
	Multihelper.win_announced.connect(_on_win_announced)

func makePlayerList():
	for c in %playerList.get_children():
		c.queue_free()
	for player in Multihelper.spawnedPlayers.keys():
		var playerSlotScene := preload("res://scenes/ui/playersList/player_slot.tscn")
		var playerSlot := playerSlotScene.instantiate()
		%playerList.add_child(playerSlot)
		playerSlot.playerId = player

func _on_win_announced(winner_name: String, win_count: int) -> void:
	%WinBanner.text = "♛ %s wins! (%d total) — New round in 5s..." % [winner_name, win_count]
	%WinBanner.visible = true
	await get_tree().create_timer(6.0).timeout
	%WinBanner.visible = false
