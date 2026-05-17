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

# Shows the win banner with a live 5-second countdown, then hides it.
# Triggered by Multihelper.win_announced on all peers.
func _on_win_announced(winner_name: String, win_count: int) -> void:
	%WinBanner.visible = true
	for i in range(5, 0, -1):
		%WinBanner.text = "♛ %s wins! (%d total) — New round in %ds..." % [winner_name, win_count, i]
		await get_tree().create_timer(1.0).timeout
	%WinBanner.visible = false
