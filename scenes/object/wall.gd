extends StaticBody2D

var hp := 60

func _ready():
	$Sprite2D.texture = load("res://assets/objects/wall_world.png")

func getDamage(_causer, amount, _type):
	if hp <= 0:
		return
	hp -= amount
	$hitParticle.emitting = true
	if hp <= 0:
		$AnimationPlayer.play("break")
	else:
		$AnimationPlayer.play("shake")

func _do_break():
	if multiplayer.is_server():
		Items.spawnPickups("wood", position, 1)
	queue_free()
