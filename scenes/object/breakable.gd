# World breakable resource object (trees, rocks, bushes, etc.).
# objectId drives all stats and drops via Items.objects — set it after adding to the scene.
# spawner must be set to the main.gd Node2D so on_object_broken() can trigger replacement.
extends StaticBody2D

@export var objectId := "":
	set(value):
		if value:
			objectId = value
			data = Items.objects[value]
			hp = data["hp"]
			$Sprite.texture = load("res://assets/objects/"+data["id"]+".png")
			loaded = true

var data := {}
var hp = 40
var spawner : Node2D
var loaded = false

# Called by the damageable group contract when struck by a player or enemy.
# Deals double damage when the causer uses the matching tool type (e.g. axe on trees).
# Gotcha: guards against damage before objectId is set (loaded flag) and after death.
func getDamage(causer, amount, type):
	if !loaded:
		return
	if hp <= 0:
		return
	var totalDamage = amount * 2 if type == data["tool"] else amount
	$AnimationPlayer.play("shake")
	$hitParticle.emitting = true
	hp -= totalDamage
	if hp <= 0:
		if causer.is_in_group("player"):
			causer.object_destroyed.emit()
		startBreaking()

# Triggers the break animation; breakObject() is called by the animation at its end.
func startBreaking():
	$AnimationPlayer.play("break")

# Server-only. Notifies the spawner to immediately replace this object elsewhere on
# the map, then frees this node and drops loot. Called by the break animation.
func breakObject():
	if !multiplayer.is_server():
		return
	queue_free()
	spawner.on_object_broken(position, objectId)
	spawnDrops()

# Spawns pickups from the object's drop table at the current position.
func spawnDrops():
	for drop in data["drops"].keys():
		Items.spawnPickups(drop, position, randi_range(data["drops"][drop]["min"], data["drops"][drop]["max"]))
