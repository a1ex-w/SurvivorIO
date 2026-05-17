extends StaticBody2D

const SCALE := Vector2(0.14, 0.14)

func _ready():
	$Sprite2D.texture = load("res://assets/objects/windmill_world.png")
	$Sprite2D.scale = SCALE
