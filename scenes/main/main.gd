extends Node2D

#objects
const initialSpawnObjects := 10
const maxObjects := Constants.MAX_OBJECTS
const objectWaveCount := 10
var spawnedObjects := 0

#enemies
const enemyWaveCount := 1
const maxEnemiesPerPlayer := Constants.MAX_ENEMIES_PER_PLAYER
const enemySpawnRadiusMin := 8
const enemySpawnRadiusMax := 9
var spawnedEnemies := {}

func _ready():
	if multiplayer.is_server():
		Multihelper.loadMap()
		spawnObjects(initialSpawnObjects)
		$HUD.queue_free()
	$dayNight.time_tick.connect(%DayNightCycleUI.set_daytime)
	createHUD()

func createHUD():
	var hudScene := preload("res://scenes/ui/playersList/generalHud.tscn")
	var hud := hudScene.instantiate()
	$HUD.add_child(hud)

#object spawn

func spawnObjects(amount):
	var breakableScene := preload("res://scenes/object/breakable.tscn")
	var spawnedThisWave := 0
	for i in range(amount):
		var spawnPos = $Map.tile_map.map_to_local($Map.walkable_tiles.pick_random())
		var breakable := breakableScene.instantiate()
		var objectId = Items.objects.keys().pick_random()
		$Objects.add_child(breakable,true)
		breakable.objectId = objectId
		breakable.position = spawnPos
		breakable.spawner = self
		spawnedObjects += 1
		spawnedThisWave += 1
	return spawnedThisWave

func trySpawnObjectWave():
	if spawnedObjects < maxObjects:
		var toMax := maxObjects - spawnedObjects
		spawnObjects(min(objectWaveCount, toMax))

func _on_object_spawn_timer_timeout():
	if multiplayer.is_server():
		trySpawnObjectWave()

#enemy spawn

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

# Seeds the world with the initial object wave after a round reset.
func spawn_initial_objects() -> void:
	spawnObjects(initialSpawnObjects)
