# Base class for all player-placed objects (windmill, etc.).
# Handles owner tracking, HP/destruction, and optional passive score generation.
#
# Usage — extend this script and override values before super._ready():
#   extends "res://scenes/object/placeable_object.gd"
#   func _ready() -> void:
#       score_per_interval = 1   # score rewarded each tick (0 = disabled)
#       score_interval     = 10.0
#       max_hp             = 50.0
#       super._ready()
#
# owner_id is set automatically by Items.spawnPlaceable — no manual wiring needed.
# take_damage() is server-only; call it from enemy/projectile hit logic.
extends StaticBody2D

# Peer ID of the player who placed this object. Set by Items.spawnPlaceable.
var owner_id: int = 0
var max_hp: float = 100.0
var hp: float = 100.0

# Score given to owner every score_interval seconds. Leave at 0 to disable.
# Must be set before super._ready() so the timer is configured correctly.
var score_per_interval: int = 0
var score_interval: float = 10.0

func _ready() -> void:
	hp = max_hp
	if multiplayer.is_server() and score_per_interval > 0:
		var timer := Timer.new()
		timer.wait_time = score_interval
		timer.autostart = true
		timer.timeout.connect(_on_score_tick)
		add_child(timer)

func _on_score_tick() -> void:
	if owner_id == 0:
		return
	var player := get_node_or_null("/root/Game/Level/Main/Players/" + str(owner_id))
	if player:
		player.rewardPlayer(score_per_interval)

# Server-only. Reduces HP and frees the object when it reaches 0.
# MultiplayerSpawner propagates the removal to all clients automatically.
func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	hp -= amount
	if hp <= 0:
		queue_free()
