extends Node

var playerScenePath = preload("res://scenes/character/player.tscn")
var mapSeed = randi()
var map: Node2D
var main: Node2D

signal player_connected(peer_id)
signal player_disconnected(peer_id)
signal server_disconnected
signal player_spawned(peer_id, player_info)
signal player_despawned
signal player_registered
signal player_score_updated
signal win_announced(winner_name: String, win_count: int)

var _win_pending := false
signal data_loaded

const PORT = Constants.PORT

var spawnedPlayers = {}
var connectedPlayers = []

var player_info = {"name": ""}

@onready var game = get_node_or_null("/root/Game")
func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func join_game(address = ""):
	if address.is_empty():
		address = Constants.SERVER_IP
	multiplayer.multiplayer_peer = null
	var peer = WebSocketMultiplayerPeer.new()
	var error
	if Constants.USE_SSL:
		var cert := load(Constants.TRUSTED_CHAIN_PATH)
		var tlsOptions = TLSOptions.client(cert)
		error = peer.create_client("wss://" + address + ":" + str(PORT), tlsOptions)
	else:
		error = peer.create_client("ws://" + address + ":" + str(PORT))
	if error:
		return error
	multiplayer.multiplayer_peer = peer

func create_game():
	var peer = WebSocketMultiplayerPeer.new()
	var error
	if Constants.USE_SSL:
		var priv := load(Constants.PRIVATE_KEY_PATH)
		var cert := load(Constants.TRUSTED_CHAIN_PATH)
		var tlsOptions = TLSOptions.server(priv, cert)
		error = peer.create_server(PORT, "*", tlsOptions)
	else:
		error = peer.create_server(PORT, "*")
	if error:
		return error
	multiplayer.multiplayer_peer = peer
	player_connected.emit(1, player_info)
	game.start_game()

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = null

func _on_player_connected(id):
	print("player connected with id "+str(id)+" to "+str(multiplayer.get_unique_id()))
	if multiplayer.is_server():
		Victories.sync_to_peer(id)

@rpc("call_local" ,"any_peer", "reliable")
func _register_character(new_player_info):
	var new_player_id = multiplayer.get_remote_sender_id()
	spawnedPlayers[new_player_id] = new_player_info
	player_spawned.emit(new_player_id, new_player_info)
	player_registered.emit()
	
@rpc("call_local" ,"any_peer", "reliable")
func _deregister_character(id):
	spawnedPlayers.erase(id)
	player_despawned.emit()

func _on_player_disconnected(id):
	connectedPlayers.erase(id)
	spawnedPlayers.erase(id)
	player_disconnected.emit(id)

func _on_connected_ok():
	game.start_game()
	var peer_id = multiplayer.get_unique_id()
	connectedPlayers.append(peer_id)
	player_connected.emit(peer_id)
	load_main_game()
	
func load_main_game():
	player_loaded.rpc_id(1)

@rpc("any_peer", "call_local", "reliable")
func player_loaded():
	var sender_id = multiplayer.get_remote_sender_id()
	main = game.get_node("Level/Main")
	var mapData := {"seed": mapSeed}
	sendGameData.rpc_id(sender_id, spawnedPlayers, mapData)
	set_process(false)

@rpc("authority", "call_remote", "reliable")
func sendGameData(playerData, mapData):
	spawnedPlayers = playerData
	mapSeed = mapData["seed"]
	main = game.get_node("Level/Main")
	loadMap()
	data_loaded.emit()
	set_process(true)

func _on_connected_fail():
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()

# Called server-side when a player's score hits WIN_SCORE.
# Records the win, syncs crown UI, broadcasts the announcement, waits
# 5 seconds, then triggers a full round reset. _win_pending prevents
# a second winner being recorded during the 5s cooldown.
func trigger_win(winner_pid: int) -> void:
	if not multiplayer.is_server() or _win_pending:
		return
	_win_pending = true
	var winner_name: String = spawnedPlayers[winner_pid]["name"]
	var win_count := Victories.add_win(winner_name)
	spawnedPlayers[winner_pid]["wins"] = win_count
	_sync_wins.rpc(winner_pid, win_count)
	_broadcast_win.rpc(winner_name, win_count)
	await get_tree().create_timer(5.0).timeout
	_reset_round.rpc()
	_win_pending = false

# Syncs a player's updated win count to all peers and refreshes their crown.
@rpc("authority", "call_local", "reliable")
func _sync_wins(pid: int, win_count: int) -> void:
	if pid in spawnedPlayers:
		spawnedPlayers[pid]["wins"] = win_count
	player_score_updated.emit()
	var player_node := get_node_or_null("/root/Game/Level/Main/Players/" + str(pid))
	if player_node:
		player_node.update_crown(win_count)

# Emits win_announced so the HUD can display the win banner on all peers.
@rpc("authority", "call_local", "reliable")
func _broadcast_win(winner_name: String, win_count: int) -> void:
	win_announced.emit(winner_name, win_count)

# Resets all player scores, clears world objects, and regenerates the map.
# Only runs logic on the server; score resets are broadcast to clients via
# _sync_score so leaderboard stays in sync.
@rpc("authority", "call_local", "reliable")
func _reset_round() -> void:
	if not multiplayer.is_server():
		return
	for pid in spawnedPlayers:
		spawnedPlayers[pid]["score"] = 0
		var player_node := get_node_or_null("/root/Game/Level/Main/Players/" + str(pid))
		if player_node:
			player_node._sync_score.rpc(0)
	player_score_updated.emit()
	# MultiplayerSpawner automatically despawns cleared objects on clients.
	var m := get_node_or_null("/root/Game/Level/Main")
	if m:
		m.clear_world()
	var new_seed := randi()
	mapSeed = new_seed
	_regen_map.rpc(new_seed)

# Runs on all peers: regenerates the map with the new seed so terrain is
# identical everywhere. Server also spawns initial objects and respawns players.
@rpc("authority", "call_local", "reliable")
func _regen_map(new_seed: int) -> void:
	mapSeed = new_seed
	var m := get_node_or_null("/root/Game/Level/Main")
	if m:
		m.get_node("Map").generateMap()
	if multiplayer.is_server() and m:
		m.spawn_initial_objects()
		for player in m.get_node("Players").get_children():
			var pid_str: String = player.name
			Inventory.inventories[pid_str] = {}
			Inventory.durabilities.erase(pid_str)
			Inventory.inventoryUpdated.emit(pid_str)
			player.unequipItem.rpc()
			player.respawn.rpc()

func loadMap():
	main = get_node("/root/Game/Level/Main")
	map = main.get_node("Map")
	map.generateMap()

func requestSpawn(playerName, id, characterFile):
	player_info["name"] = playerName
	player_info["body"] = characterFile
	player_info["score"] = 0
	player_info["wins"] = Victories.get_wins(playerName)
	spawnedPlayers[id] = player_info
	_register_character.rpc(player_info)
	spawnPlayer.rpc_id(1, playerName, id, characterFile)

@rpc("any_peer", "call_local", "reliable")
func spawnPlayer(playerName, id, characterFile):
	var newPlayer := playerScenePath.instantiate()
	newPlayer.playerName = playerName
	newPlayer.characterFile = characterFile
	newPlayer.name = str(id)
	main.get_node("Players").add_child(newPlayer)
	newPlayer.sendPos.rpc(map.tile_map.map_to_local(map.walkable_tiles.pick_random()))

@rpc("any_peer", "call_remote", "reliable")
func showSpawnUI():
	var spawnPlayerScene := preload("res://scenes/ui/spawn/spawnPlayer.tscn")
	var retry = spawnPlayerScene.instantiate()
	retry.retry = true
	get_node("/root/Game/Level/Main/HUD").add_child(retry)
