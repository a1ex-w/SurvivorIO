extends Node

const SAVE_PATH := "user://victories.cfg"
const WIN_SCORE := 500

# Populated on server from file; populated on clients via sync RPC
var wins: Dictionary = {}

func _ready() -> void:
	if multiplayer.is_server():
		_load()

# ── Server only ──────────────────────────────────────────────────────────────

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		for key in config.get_section_keys("wins"):
			wins[key] = config.get_value("wins", key, 0)

func _save() -> void:
	var config := ConfigFile.new()
	for player_name in wins:
		config.set_value("wins", player_name, wins[player_name])
	config.save(SAVE_PATH)

func add_win(player_name: String) -> int:
	if not multiplayer.is_server():
		return 0
	wins[player_name] = wins.get(player_name, 0) + 1
	_save()
	_sync_to_clients.rpc(wins)
	return wins[player_name]

func get_wins(player_name: String) -> int:
	return wins.get(player_name, 0)

func crown_name(player_name: String) -> String:
	var w := get_wins(player_name)
	return ("♛%d " % w) + player_name if w > 0 else player_name

# ── Sync to clients ───────────────────────────────────────────────────────────

# Called by server to push full wins dict to all clients
@rpc("authority", "call_local", "reliable")
func _sync_to_clients(wins_data: Dictionary) -> void:
	if not multiplayer.is_server():
		wins = wins_data

# Server calls this when a client first connects so they get current wins
func sync_to_peer(peer_id: int) -> void:
	if multiplayer.is_server():
		_sync_to_clients.rpc_id(peer_id, wins)
