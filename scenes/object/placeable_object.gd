extends StaticBody2D

var owner_id: int = 0
var max_hp: float = 100.0
var hp: float = 100.0

# Set before calling super._ready() in subclass. 0 = no passive score.
var score_per_interval: int = 0
var score_interval: float = 10.0

func _ready() -> void:
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

func take_damage(amount: float) -> void:
	if not multiplayer.is_server():
		return
	hp -= amount
	if hp <= 0:
		queue_free()
