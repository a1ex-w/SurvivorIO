extends "res://scenes/object/placeable_object.gd"

const SCALE := Vector2(0.14, 0.14)

func _ready() -> void:
	score_per_interval = 1
	score_interval = 10.0
	super._ready()
	$Sprite2D.texture = load("res://assets/objects/windmill_world.png")
	$Sprite2D.scale = SCALE
