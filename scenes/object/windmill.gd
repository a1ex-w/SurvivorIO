# Craftable placeable structure that generates passive score for its owner over time.
# Recipe: 6 wood + 3 stone (defined in Items.recipes).
# Drops 50% of crafting cost on destruction (probabilistic — see Items.calc_drops).
#
# Extends PlaceableObject — owner_id and damage/animation handling are automatic.
# To adjust score rate or HP, change score_per_interval, score_interval, or max_hp
# before calling super._ready(). See placeable_object.gd for the full extension pattern.
extends "res://scenes/object/placeable_object.gd"

const SCALE := Vector2(0.14, 0.14)

func _ready() -> void:
	score_per_interval = 10  # +10 score to owner every 10 seconds
	score_interval = 10.0
	max_hp = 150             # Durable — costs more than a stone wall to craft
	super._ready()
	$Sprite2D.texture = load("res://assets/objects/windmill_world.png")
	$Sprite2D.scale = SCALE

# Overrides PlaceableObject._do_break to drop 50% of recipe cost before freeing.
# Uses Items.calc_drops for probabilistic rounding of fractional amounts.
# Server-only drop logic — queue_free() runs on all peers.
func _do_break() -> void:
	if multiplayer.is_server():
		var drops := Items.calc_drops(Items.recipes["windmill"], 0.5)
		for item in drops:
			Items.spawnPickups(item, position, drops[item])
	queue_free()
