extends StaticBody2D

func _ready():
	$Sprite2D.texture = load("res://assets/items/coal.png")
	$Sprite2D.scale = Vector2(1.8, 1.8)
