extends Node2D

# Resource count is maintained continuously — one replacement spawns immediately
# whenever an object is destroyed. _top_up_objects() fills to cap on player join/leave.
# The ObjectSpawnTimer (60s) is a slow integrity check only; it is not the primary driver.
var spawnedObjects := 0
# Tracks how many of each object type are currently on the map.
# Used to enforce min_count guarantees from Items.objects.
var spawnedByType: Dictionary = {}

#enemies
const enemyWaveCount := 1
const maxEnemiesPerPlayer := Constants.MAX_ENEMIES_PER_PLAYER
const enemySpawnRadiusMin := 8
const enemySpawnRadiusMax := 9
var spawnedEnemies := {}

func _ready():
	if multiplayer.is_server():
		Multihelper.loadMap()
		spawnObjects(_max_objects())
		Multihelper.player_registered.connect(_top_up_objects)
		Multihelper.player_despawned.connect(_top_up_objects)
		$HUD.queue_free()
	$dayNight.time_tick.connect(%DayNightCycleUI.set_daytime)
	createHUD()

func createHUD():
	var hudScene := preload("res://scenes/ui/playersList/generalHud.tscn")
	var hud := hudScene.instantiate()
	$HUD.add_child(hud)

#object spawn

func spawnObjects(amount: int) -> int:
	var breakableScene := preload("res://scenes/object/breakable.tscn")
	for i in range(amount):
		var spawnPos := $Map.tile_map.map_to_local($Map.walkable_tiles.pick_random())
		var breakable := breakableScene.instantiate()
		var objectId := _pick_next_object_type()
		$Objects.add_child(breakable, true)
		breakable.objectId = objectId
		breakable.position = spawnPos
		breakable.spawner = self
		spawnedObjects += 1
		spawnedByType[objectId] = spawnedByType.get(objectId, 0) + 1
	return amount

# Selects the next object type to spawn, enforcing min_count guarantees first.
# Effective minimum scales with player count: min_count × max(1, players).
# e.g. crystal1 min_count=1 → 1 solo, 2 with 2 players, 4 with 4 players.
# If any type is below its scaled minimum, picks randomly from those deficient types.
# Otherwise falls through to weighted random selection.
func _pick_next_object_type() -> String:
	var player_count := max(1, Multihelper.spawnedPlayers.size())
	var deficient: Array = []
	for key in Items.objects:
		var base_min: int = Items.objects[key].get("min_count", 0)
		var scaled_min := base_min * player_count
		if scaled_min > 0 and spawnedByType.get(key, 0) < scaled_min:
			deficient.append(key)
	if not deficient.is_empty():
		return deficient.pick_random()
	return _pick_weighted_object()

# Selects a random object type using weighted probability from Items.objects.
# Higher weight = more frequent spawn. Objects without a weight field default to 1.
# To adjust rarity: change the weight value in Items.objects — no code changes needed.
# Gotcha: returns the last key as fallback if rng overshoots (shouldn't happen).
func _pick_weighted_object() -> String:
	var total_weight := 0
	for key in Items.objects:
		total_weight += Items.objects[key].get("weight", 1)
	var roll := randi() % total_weight
	var cumulative := 0
	for key in Items.objects:
		cumulative += Items.objects[key].get("weight", 1)
		if roll < cumulative:
			return key
	return Items.objects.keys().back()

# Returns the target object count based on current player count.
# Ensures the map is always resource-rich enough for all connected players.
# Gotcha: spawnedPlayers may be empty at startup — MAX_OBJECTS_BASE is the floor.
func _max_objects() -> int:
	return max(Constants.MAX_OBJECTS_BASE,
		Multihelper.spawnedPlayers.size() * Constants.OBJECTS_PER_PLAYER)

# Called by breakable.gd when an object is destroyed.
# Immediately spawns one replacement at least OBJECT_RESPAWN_MIN_DIST away from
# the broken object's position so the player doesn't see it appear beside them.
# Falls back to unrestricted spawn if no distant tiles are available.
func on_object_broken(broken_pos: Vector2, object_id: String) -> void:
	spawnedObjects -= 1
	spawnedByType[object_id] = max(0, spawnedByType.get(object_id, 0) - 1)
	if Multihelper.map and not Multihelper.map.walkable_tiles.is_empty():
		_spawn_away_from(broken_pos)

# Spawns one object on a walkable tile at least OBJECT_RESPAWN_MIN_DIST away from
# excluded_pos. Falls back to a fully random tile if no qualifying tiles exist.
func _spawn_away_from(excluded_pos: Vector2) -> void:
	var tile_map := Multihelper.map.tile_map
	var candidates := Multihelper.map.walkable_tiles.filter(func(tile: Vector2i) -> bool:
		return tile_map.map_to_local(tile).distance_to(excluded_pos) > Constants.OBJECT_RESPAWN_MIN_DIST
	)
	var spawn_pos: Vector2
	if candidates.is_empty():
		spawn_pos = tile_map.map_to_local(Multihelper.map.walkable_tiles.pick_random())
	else:
		spawn_pos = tile_map.map_to_local(candidates.pick_random())
	var breakableScene := preload("res://scenes/object/breakable.tscn")
	var breakable := breakableScene.instantiate()
	var objectId := _pick_next_object_type()
	$Objects.add_child(breakable, true)
	breakable.objectId = objectId
	breakable.position = spawn_pos
	breakable.spawner = self
	spawnedObjects += 1
	spawnedByType[objectId] = spawnedByType.get(objectId, 0) + 1

# Fills the map up to the current player-scaled cap.
# Called when players join or leave so the resource pool adjusts immediately.
func _top_up_objects() -> void:
	var shortage := _max_objects() - spawnedObjects
	if shortage > 0:
		spawnObjects(shortage)

# Slow integrity check — tops up any discrepancy not caught by event-driven spawning.
# Not the primary spawn driver; ObjectSpawnTimer should be set to 60s.
func _on_object_spawn_timer_timeout():
	if multiplayer.is_server():
		_top_up_objects()

#enemy spawn

# Spawns a specific mob type near the given player. Used by the /spawn server command.
# Ignores the enemy cap so it works for testing regardless of current mob count.
func spawn_mob_for_player(mob_id: String, pid: int) -> void:
	var positions: Array = $NavHelper.getNRandomNavigableTileInPlayerRadius(pid, 1, enemySpawnRadiusMin, enemySpawnRadiusMax)
	if positions.is_empty():
		return
	var enemyScene := preload("res://scenes/enemy/enemy.tscn")
	var enemy := enemyScene.instantiate()
	$Enemies.add_child(enemy, true)
	enemy.position = positions[0]
	enemy.spawner = self
	enemy.targetPlayerId = pid
	enemy.enemyId = mob_id
	increasePlayerEnemyCount(pid)

# Returns the total number of enemies currently alive on the map.
func _total_enemies() -> int:
	var total := 0
	for pid in spawnedEnemies:
		total += spawnedEnemies[pid]
	return total

# Returns the effective enemy cap: per-player × players, capped by MAX_ENEMIES_TOTAL.
func _max_enemies() -> int:
	var per_player_total := Multihelper.spawnedPlayers.size() * maxEnemiesPerPlayer
	return min(per_player_total, Constants.MAX_ENEMIES_TOTAL)

# Selects a mob type using weighted probability from Items.mobs.
# Higher weight = more frequent spawn. Omitting weight defaults to 1.
# To adjust rarity: change the weight value in Items.mobs — no code changes needed.
func _pick_weighted_mob() -> String:
	var total_weight := 0
	for key in Items.mobs:
		total_weight += Items.mobs[key].get("weight", 1)
	var roll := randi() % total_weight
	var cumulative := 0
	for key in Items.mobs:
		cumulative += Items.mobs[key].get("weight", 1)
		if roll < cumulative:
			return key
	return Items.mobs.keys().back()

func trySpawnEnemies():
	if _total_enemies() >= _max_enemies():
		return
	var enemyScene := preload("res://scenes/enemy/enemy.tscn")
	var players = Multihelper.spawnedPlayers.keys()
	for player in players:
		if _total_enemies() >= _max_enemies():
			break
		var playerEnemies := getPlayerEnemyCount(player)
		if playerEnemies < maxEnemiesPerPlayer:
			var toSpawn = min(maxEnemiesPerPlayer - playerEnemies, enemyWaveCount)
			var spawnPositions = $NavHelper.getNRandomNavigableTileInPlayerRadius(player, toSpawn, enemySpawnRadiusMin, enemySpawnRadiusMax)
			for pos in spawnPositions:
				if _total_enemies() >= _max_enemies():
					break
				var enemy = enemyScene.instantiate()
				$Enemies.add_child(enemy,true)
				enemy.position = pos
				enemy.spawner = self
				enemy.targetPlayerId = player
				enemy.enemyId = _pick_weighted_mob()
				increasePlayerEnemyCount(player)

func getPlayerEnemyCount(pId) -> int:
	if pId in spawnedEnemies:
		return spawnedEnemies[pId]
	return 0

func increasePlayerEnemyCount(pId) -> void:
	if pId in spawnedEnemies:
		spawnedEnemies[pId] += 1
	else:
		spawnedEnemies[pId] = 1

func decreasePlayerEnemyCount(pId) -> void:
	if pId in spawnedEnemies:
		spawnedEnemies[pId] -= 1
	else:
		spawnedEnemies[pId] = 0

func _on_enemy_spawn_timer_timeout():
	if multiplayer.is_server():
		trySpawnEnemies()

# Removes all world objects, enemies, and pickups server-side.
# MultiplayerSpawner propagates despawns to clients automatically.
func clear_world() -> void:
	for c in $Objects.get_children(): c.queue_free()
	for c in $Enemies.get_children(): c.queue_free()
	for c in $Pickups.get_children(): c.queue_free()
	spawnedEnemies.clear()
	spawnedObjects = 0
	spawnedByType.clear()

# Seeds the world after a round reset. Spawns to the full player-scaled cap.
func spawn_initial_objects() -> void:
	spawnObjects(_max_objects())
