extends StaticBody2D

var boarded_player_id := ""

func _ready():
	var img = Image.create(50, 30, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.27, 0.07))
	$Sprite2D.texture = ImageTexture.create_from_image(img)
	$Sprite2D.scale = Vector2(2, 2)
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

func _is_on_water() -> bool:
	var map = get_parent().get_parent().get_node_or_null("Map")
	if !map:
		return false
	var tile_pos = map.tile_map.local_to_map(position)
	var atlas = map.tile_map.get_cell_atlas_coords(0, tile_pos)
	return atlas in [Vector2i(18, 0), Vector2i(19, 0)]

func _on_area_entered(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_boat = self
		$InteractLabel.text = "Press E to board" if _is_on_water() else "Press E to pick up"
		$InteractLabel.visible = true

func _on_area_exited(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_boat = null
		$InteractLabel.visible = false

@rpc("any_peer", "call_local", "reliable")
func set_boarded(player_id: String):
	boarded_player_id = player_id
	$InteractLabel.text = "Press E to disembark" if player_id != "" else "Press E to board"

@rpc("any_peer", "call_remote", "reliable")
func pickup(player_id: String):
	if !multiplayer.is_server():
		return
	Inventory.addItem(player_id, "boat", 1)
	destroySelf.rpc()

@rpc("authority", "call_local", "reliable")
func destroySelf():
	queue_free()
