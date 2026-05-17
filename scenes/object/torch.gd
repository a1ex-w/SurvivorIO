extends StaticBody2D

const MAX_DURABILITY := 40.0

var durability := MAX_DURABILITY:
	set(value):
		durability = value
		if is_node_ready():
			$HealthBar.value = durability

func _ready():
	$Sprite2D.texture = load("res://assets/items/torch.png")
	$Sprite2D.scale = Vector2(1.8, 1.8)
	add_to_group("coal_repeller")
	$HealthBar.max_value = MAX_DURABILITY
	$HealthBar.value = durability

func _on_burn_timer_timeout():
	if !multiplayer.is_server():
		return
	durability -= 1.0
	if durability <= 0:
		queue_free()
