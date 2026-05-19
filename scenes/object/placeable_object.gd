# Base class for all player-placed objects (windmill, etc.).
# Handles owner tracking, HP/destruction, animations, and optional passive score generation.
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
# Add node to "damageable" group so player/enemy attacks call getDamage automatically.
# Override _do_break() to spawn drops on destruction.
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

# Called by the damage system (player/enemy attacks via "damageable" group).
# Runs on all peers — AnimationPlayer sync in the scene replicates visuals to clients.
func getDamage(_causer, amount: float, _type) -> void:
	if hp <= 0:
		return
	hp -= amount
	_on_hit()
	if hp <= 0:
		_on_break()

# Plays hit feedback. Override to customise particles/sound.
func _on_hit() -> void:
	var anim := get_node_or_null("AnimationPlayer")
	if anim:
		anim.play("shake")
	var particles := get_node_or_null("hitParticle")
	if particles:
		particles.emitting = true

# Plays break animation if present, otherwise destroys immediately.
func _on_break() -> void:
	var anim := get_node_or_null("AnimationPlayer")
	if anim:
		anim.play("break")
	else:
		_do_break()

# Called at the end of the break animation (or immediately if no animation).
# Override in subclass to spawn drops before freeing.
func _do_break() -> void:
	queue_free()

# Server-only programmatic damage (e.g. from game logic, not player attack).
func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	getDamage(null, amount, "normal")
