extends Node

var mobs := {
	# Mob data fields:
	#   maxhp          — starting health
	#   speed          — movement speed (pixels/sec)
	#   attack         — scene name in res://scenes/attacks/ used to fire projectiles
	#   attackDamage   — damage dealt per hit
	#   attackRange    — distance at which the enemy switches from CHASE to ATTACK
	#   detect_radius  — distance at which the enemy notices a player and begins chasing
	#   lose_radius    — distance at which enemy gives up and returns to IDLE (>= detect_radius)
	#   weight             — spawn frequency relative to other mobs (higher = more common).
	#                        Omitting defaults to 1. No code changes needed for new mob types.
	#   projectile_sprite  — Path to a custom sprite PNG (optional). Use a white image so color tints correctly.
	#   projectile_color   — Color tint applied to the projectile sprite (optional, defaults to white).
	#   sprite_scale       — Vector2 scale for the enemy sprite (optional, defaults to Vector2(1,1)).
	#   collision_radius   — float radius for the CircleShape2D hitbox (optional, keeps scene default).
	#   drops              — loot table: { "item_id": { "min": N, "max": N } }
	# Adding a new mob only requires a new entry here + a PNG at assets/characters/enemy/<id>.png
	"zombie":   {"maxhp": 40,  "speed": 50,  "attack": "slash_attack",      "attackDamage": 4,  "attackRange": 50,  "detect_radius": 300.0, "lose_radius": 500.0, "weight": 10, "drops": {"wood":  {"min": 1, "max": 2}}},
	"spider":   {"maxhp": 80,  "speed": 100, "attack": "projectile_attack",  "attackDamage": 6,  "attackRange": 300, "detect_radius": 450.0, "lose_radius": 650.0, "weight": 7,  "drops": {"stone": {"min": 1, "max": 2}}},
	"brute":    {"maxhp": 180, "speed": 40,  "attack": "slash_attack",       "attackDamage": 15, "attackRange": 70,  "detect_radius": 250.0, "lose_radius": 437.5, "weight": 3, "sprite_scale": Vector2(2.0, 2.0), "collision_radius": 20.0, "drops": {"wood":  {"min": 2, "max": 4}, "stone": {"min": 1, "max": 2}}},
	"wraith":   {"maxhp": 50,  "speed": 140, "attack": "projectile_attack",  "attackDamage": 8,  "attackRange": 500, "detect_radius": 900.0, "lose_radius": 1200.0, "weight": 2, "projectile_sprite": "res://assets/characters/attacks/wraith_orb_purple.png", "drops": {"stone": {"min": 1, "max": 3}}},
}

var objects := {
	"tree1": {"id": "tree1", "hp": 40, "tool": "axe", "drops": {"wood": {"min": 1, "max": 2}}},
	"rock1": {"id": "rock1", "hp": 70, "tool": "pickaxe", "drops": {"stone": {"min": 1, "max": 3}}},
	"tree2": {"id": "tree2", "hp": 50, "tool": "axe", "drops": {"wood": {"min": 2, "max": 4}}},
	"rock2": {"id": "rock2", "hp": 100, "tool": "pickaxe", "drops": {"stone": {"min": 2, "max": 5}}},
	"bush1": {"id": "bush1", "hp": 20, "tool": "sword", "drops": {"berries": {"min": 1, "max": 3}}},
	"ore1": {"id": "ore1", "hp": 120, "tool": "pickaxe", "drops": {"iron": {"min": 1, "max": 3}}},
	"tree3": {"id": "tree3", "hp": 60, "tool": "axe", "drops": {"wood": {"min": 3, "max": 5}, "sap": {"min": 1, "max": 1}}},
	"rock3": {"id": "rock3", "hp": 90, "tool": "pickaxe", "drops": {"stone": {"min": 2, "max": 4}, "coal": {"min": 1, "max": 2}}},
	"magicPlant1": {"id": "magicPlant1", "hp": 30, "tool": "sword", "drops": {"magicHerb": {"min": 1, "max": 2}}},
	"crystal1": {"id": "crystal1", "hp": 150, "tool": "pickaxe", "drops": {"crystalShard": {"min": 1, "max": 2}}},
	"magicTree1": {"id": "magicTree1", "hp": 70, "tool": "axe", "drops": {"magicWood": {"min": 1, "max": 3}}},
	"magicRock1": {"id": "magicRock1", "hp": 110, "tool": "pickaxe", "drops": {"magicStone": {"min": 1, "max": 2}}},
}

var equips := {
	"torch": {"attack": "swing", "damage": 20, "damageType": "normal", "durability": 40.0, "scene": "torch"},
	"sword1": {"attack": "swing", "damage": 30, "damageType": "normal", "durability": 5.0},
	"axe1": {"attack": "swing", "damage": 30, "damageType": "axe", "durability": 20.0},
	"pickaxe1": {"attack": "swing", "damage": 30, "damageType": "pickaxe", "durability": 20.0},
	"spear1": {"attack": "stab", "damage": 20, "damageType": "normal", "durability": 10.0, "projectile": "fireshuriken", "fire_rate": 0.65},
	"dagger1": {"attack": "stab", "damage": 15, "damageType": "normal", "durability": 10.0},
	"axe2": {"attack": "swing", "damage": 40, "damageType": "axe", "durability": 30.0},
	"pickaxe2": {"attack": "swing", "damage": 40, "damageType": "pickaxe", "durability": 30.0},
	"magicSword1": {"attack": "swing", "damage": 35, "damageType": "magic", "durability": 10.0, "projectile": "magicBolt"},
	"magicAxe1": {"attack": "swing", "damage": 45, "damageType": "magic", "durability": 25.0, "projectile": "fireball"},
	"magicDagger1": {"attack": "stab", "damage": 25, "damageType": "magic", "durability": 15.0, "projectile": "iceShard"},
	"magicSpear1": {"attack": "stab", "damage": 30, "damageType": "magic", "durability": 25.0, "projectile": "lightningBolt"},
}

var placeables := {
	"chest": "chest",
	"torch": "torch",
	"boat": "boat",
	"wall": "wall",
	"stone_wall": "stone_wall",
	"door": "door",
	"stone_door": "stone_door",
	"windmill": "windmill",
}

var recipes := {
	"chest": {"wood": 4},
	"windmill": {"wood": 6, "stone": 3},
	"torch": {"wood": 3, "coal": 1},
	"wall": {"wood": 1},
	"stone_wall": {"stone": 2},
	"door": {"wood": 2},
	"stone_door": {"stone": 2},
	"boat": {"wood": 1},
	"sword1": {"wood": 2, "stone": 2},
	"axe1": {"wood": 2, "stone": 3},
	"pickaxe1": {"wood": 2, "stone": 3},
	"spear1": {"wood": 3, "stone": 1},
	"dagger1": {"wood": 1, "stone": 2},
	"axe2": {"wood": 3, "iron": 2},
	"pickaxe2": {"wood": 3, "iron": 2},
	"magicSword1": {"magicWood": 2, "magicStone": 2, "crystalShard": 1},
	"magicAxe1": {"magicWood": 3, "magicStone": 3, "crystalShard": 1},
	"magicDagger1": {"magicWood": 1, "magicStone": 2, "magicHerb": 2},
	"magicSpear1": {"magicWood": 3, "magicStone": 1, "magicHerb": 1},
}

var projectiles := {
	"fireshuriken": {"maxHits": 1, "speed": 50, "time": 1, "curveSpeed": true},
	"icebolt": {"maxHits": 1, "speed": 30, "time": 1.5, "curveSpeed": false, "effect": "freeze"},
	"magicBolt": {"maxHits": 1, "speed": 45, "time": 1.2, "curveSpeed": true, "effect": "magicDamage"},
	"fireball": {"maxHits": 1, "speed": 35, "time": 1.3, "curveSpeed": false, "effect": "burn"},
	"iceShard": {"maxHits": 1, "speed": 40, "time": 1.5, "curveSpeed": false, "effect": "slow"},
	"lightningBolt": {"maxHits": 1, "speed": 50, "time": 1, "curveSpeed": true, "effect": "stun"},
}

func spawnPickups(id, at, amount):
	var pickups := get_node("/root/Game/Level/Main/Pickups")
	for i in range(amount):
		var pickupScene := preload("res://scenes/item/pickup.tscn")
		var pickup := pickupScene.instantiate()
		pickups.call_deferred("add_child", pickup, true)
		pickup.itemId = id
		pickup.position = at + Vector2(randf_range(-15,15), randf_range(-15,15))

# THE canonical way to display any item ID as a human-readable name.
# Converts snake_case to Title Case: "stone_wall" -> "Stone Wall", "windmill" -> "Windmill"
#
# Use this wherever an item ID is shown to the player:
#   - Inventory/recipe slot tooltips (already wired in their setters)
#   - World pickup labels (already wired in pickup.gd setter)
#   - Any future UI — just call Items.format_item_name(item_id)
# Adding a new item requires NO changes here; the ID is formatted automatically.
func format_item_name(item_id: String) -> String:
	var words := item_id.split("_")
	for i in words.size():
		words[i] = words[i].capitalize()
	return " ".join(words)

# Returns drop counts for a recipe at the given rate.
# Fractional amounts are resolved probabilistically — e.g. 1.5 → 1 (50%) or 2 (50%).
# Use server-side only (randomness must be authoritative).
func calc_drops(recipe: Dictionary, rate: float) -> Dictionary:
	var drops := {}
	for item in recipe:
		var amount: float = recipe[item] * rate
		var count: int = int(amount)
		if randf() < fmod(amount, 1.0):
			count += 1
		if count > 0:
			drops[item] = count
	return drops

# Instantiates a placeable scene from Items.placeables and adds it to the Objects node.
# owner_id is set only if the instance has an owner_id property (PlaceableObject subclasses).
# Older placeables (walls, chest, etc.) without owner_id are unaffected — backward compatible.
# Called on ALL peers via spawnPlaceableRpc — do not call directly for multiplayer placement.
func spawnPlaceable(item_id: String, at: Vector2, owner_id: int = 0):
	var objects := get_node("/root/Game/Level/Main/Objects")
	var scene: PackedScene = load("res://scenes/object/" + placeables[item_id] + ".tscn")
	var instance := scene.instantiate()
	objects.add_child(instance, true)
	instance.position = at
	if instance.get("owner_id") != null:
		instance.owner_id = owner_id

# RPC wrapper for spawnPlaceable — runs on server and all clients simultaneously.
# Pass the placing player's peer ID as owner_id so PlaceableObject can track ownership.
@rpc("authority", "call_local", "reliable")
func spawnPlaceableRpc(item_id: String, at: Vector2, owner_id: int = 0):
	spawnPlaceable(item_id, at, owner_id)

func spawnProjectile(spawner, pId, towardsPos, canTarget):
	var projectilesNode := get_node("/root/Game/Level/Main/Projectiles")
	var projectileScene := load("res://scenes/attacks/projectile_attack.tscn")
	var projectile = projectileScene.instantiate()
	projectilesNode.add_child(projectile,true)
	projectile.projectileId = pId
	projectile.targetGroup = canTarget
	projectile.position = spawner.position
	projectile.get_node("MovingParts").rotation = spawner.get_node("MovingParts").rotation
	projectile.hitPlayer.connect(spawner.projectileHit)
	projectile.targetPos = towardsPos
	projectile.spawner = spawner
