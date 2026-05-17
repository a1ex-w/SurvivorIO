extends StaticBody2D

@export var door_type := "door_wood"

var is_open := false:
	set(value):
		is_open = value
		if is_node_ready():
			_apply_state()

func _ready():
	$Sprite2D.texture = load("res://assets/objects/" + door_type + "_world.png")
	$InteractArea.body_entered.connect(_on_body_entered)
	$InteractArea.body_exited.connect(_on_body_exited)
	_apply_state()

func _apply_state():
	$CollisionShape2D.disabled = is_open
	$Sprite2D.modulate.a = 0.35 if is_open else 1.0
	$InteractLabel.text = "Press E to close" if is_open else "Press E to open"

func interact(player_id: String):
	if multiplayer.is_server():
		is_open = !is_open
	else:
		request_toggle.rpc_id(1, player_id)

@rpc("any_peer", "call_local", "reliable")
func request_toggle(_player_id: String):
	if !multiplayer.is_server():
		return
	is_open = !is_open

func _on_body_entered(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_door = self
		$InteractLabel.visible = true

func _on_body_exited(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_door = null
		$InteractLabel.visible = false
