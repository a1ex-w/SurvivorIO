extends StaticBody2D

const MAX_DURABILITY := 40.0

var durability := MAX_DURABILITY
var _elapsed := 0.0

func _ready():
	$Sprite2D.texture = load("res://assets/items/torch.png")
	$Sprite2D.scale = Vector2(1.2, 1.2)
	add_to_group("coal_repeller")
	$HealthBar.max_value = MAX_DURABILITY
	$HealthBar.value = durability

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0:
		_elapsed -= 1.0
		durability -= 1.0
		$HealthBar.value = durability
		if durability <= 0 and multiplayer.is_server():
			_despawn.rpc()

@rpc("authority", "call_local", "reliable")
func _despawn():
	queue_free()
