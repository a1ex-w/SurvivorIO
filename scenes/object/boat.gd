extends StaticBody2D

var boarded_player_id := ""

func _ready():
	$Sprite2D.texture = load("res://assets/items/boat.png")
	$InteractArea.body_entered.connect(_on_area_entered)
	$InteractArea.body_exited.connect(_on_area_exited)

func _process(_delta):
	if boarded_player_id == "":
		return
	var players = get_parent().get_parent().get_node_or_null("Players")
	if !players:
		return
	var player_node = players.get_node_or_null(boarded_player_id)
	if player_node:
		position = player_node.position

func _on_area_entered(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_boat = self
		$InteractLabel.visible = true

func _on_area_exited(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_boat = null
		$InteractLabel.visible = false

@rpc("any_peer", "call_local", "reliable")
func set_boarded(player_id: String):
	boarded_player_id = player_id
	$InteractLabel.text = "Press E to disembark" if player_id != "" else "Press E to board"
