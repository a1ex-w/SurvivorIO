extends Control

# Maps player ID -> player_slot node for in-place score updates.
var _slot_cache: Dictionary = {}

func _ready():
	makePlayerList()
	Multihelper.player_registered.connect(makePlayerList)
	Multihelper.player_despawned.connect(makePlayerList)
	Multihelper.player_score_updated.connect(refreshPlayerList)
	Multihelper.win_announced.connect(_on_win_announced)

func _exit_tree():
	if Multihelper.player_registered.is_connected(makePlayerList):
		Multihelper.player_registered.disconnect(makePlayerList)
	if Multihelper.player_despawned.is_connected(makePlayerList):
		Multihelper.player_despawned.disconnect(makePlayerList)
	if Multihelper.player_score_updated.is_connected(refreshPlayerList):
		Multihelper.player_score_updated.disconnect(refreshPlayerList)
	if Multihelper.win_announced.is_connected(_on_win_announced):
		Multihelper.win_announced.disconnect(_on_win_announced)

# Full rebuild — called only when players join or leave.
func makePlayerList():
	for c in %playerList.get_children():
		c.queue_free()
	_slot_cache.clear()
	for player in Multihelper.spawnedPlayers.keys():
		var playerSlotScene := preload("res://scenes/ui/playersList/player_slot.tscn")
		var playerSlot := playerSlotScene.instantiate()
		%playerList.add_child(playerSlot)
		playerSlot.playerId = player
		_slot_cache[player] = playerSlot

# Lightweight refresh — updates labels in existing slots without rebuilding.
func refreshPlayerList():
	for player_id in _slot_cache:
		var slot = _slot_cache[player_id]
		if is_instance_valid(slot):
			slot.playerId = player_id

# Shows the win banner with a live 5-second countdown, then hides it.
# Triggered by Multihelper.win_announced on all peers.
func _on_win_announced(winner_name: String, win_count: int) -> void:
	%WinBanner.visible = true
	for i in range(5, 0, -1):
		if not is_inside_tree():
			return
		%WinBanner.text = "♛ %s wins! (%d total) — New round in %ds..." % [winner_name, win_count, i]
		await get_tree().create_timer(1.0).timeout
	if is_inside_tree():
		%WinBanner.visible = false