extends StaticBody2D

var boarded_player_id := ""

var _tex_main: Texture2D
var _tex_diagonal: Texture2D
var _prev_pos := Vector2.ZERO

func _ready():
	_tex_main = load("res://assets/objects/boat_world.png")
	_tex_diagonal = load("res://assets/objects/boat_diagonal.png")
	if _tex_main:
		$Sprite2D.texture = _tex_main
		$Sprite2D.scale = Vector2(0.082, 0.082)
	else:
		var img = Image.create(50, 30, false, Image.FORMAT_RGB8)
		img.fill(Color(0.55, 0.27, 0.07))
		$Sprite2D.texture = ImageTexture.create_from_image(img)
		$Sprite2D.scale = Vector2(2, 2)
	_prev_pos = position
	$InteractArea.body_entered.connect(_on_area_entered)
	$InteractArea.body_exited.connect(_on_area_exited)

func _process(_delta):
	if boarded_player_id != "":
		var players = get_parent().get_parent().get_node_or_null("Players")
		if players:
			var player_node = players.get_node_or_null(boarded_player_id)
			if is_instance_valid(player_node):
				position = player_node.position

	if _tex_main:
		var delta_pos = position - _prev_pos
		if delta_pos.length() > 0.5:
			$Sprite2D.texture = _tex_main
			$Sprite2D.flip_h = false
			$Sprite2D.flip_v = false
			var is_diagonal: bool = abs(delta_pos.x) > abs(delta_pos.y) * 0.4 and abs(delta_pos.y) > abs(delta_pos.x) * 0.4
			if is_diagonal:
				# Swapped: NE↔SW, NW↔SE
				$Sprite2D.texture = _tex_diagonal
				$Sprite2D.rotation = 0.0
				$Sprite2D.flip_h = delta_pos.x > 0
				$Sprite2D.flip_v = delta_pos.y < 0
			elif abs(delta_pos.x) > abs(delta_pos.y):
				# Swapped: E↔W
				$Sprite2D.texture = _tex_main
				$Sprite2D.rotation = -PI / 2.0 if delta_pos.x > 0 else PI / 2.0
				$Sprite2D.flip_h = false
				$Sprite2D.flip_v = false
			else:
				# Swapped: N↔S
				$Sprite2D.texture = _tex_main
				$Sprite2D.rotation = 0.0
				$Sprite2D.flip_h = false
				$Sprite2D.flip_v = delta_pos.y < 0
	_prev_pos = position

func _is_on_water() -> bool:
	var map = get_parent().get_parent().get_node_or_null("Map")
	if !map:
		return false
	var tile_pos = map.tile_map.local_to_map(position)
	var atlas = map.tile_map.get_cell_atlas_coords(0, tile_pos)
	return atlas in Constants.WATER_TILES

func interact(player: Node) -> void:
	if _is_on_water():
		player.board(self)
	else:
		if multiplayer.is_server():
			pickup(str(player.name))
		else:
			pickup.rpc_id(1, str(player.name))

func _on_area_entered(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.set_nearby_interactable(self)
		$InteractLabel.text = "Press E to board" if _is_on_water() else "Press E to pick up"
		$InteractLabel.visible = true

func _on_area_exited(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		if body.nearby_interactable == self:
			body.nearby_interactable = null
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
