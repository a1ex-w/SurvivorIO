extends StaticBody2D

var chest_inventory := {}
var chest_ui_instance = null

func _ready():
	$Sprite2D.texture = load("res://assets/objects/chest_world.png")
	$Sprite2D.scale = Vector2(0.041, 0.041)
	$InteractArea.body_entered.connect(_on_interact_area_body_entered)
	$InteractArea.body_exited.connect(_on_interact_area_body_exited)

func open_ui():
	request_chest_inventory.rpc_id(1, str(multiplayer.get_unique_id()))
	var chest_ui_scene = preload("res://scenes/ui/chest/chest_ui.tscn")
	chest_ui_instance = chest_ui_scene.instantiate()
	get_parent().get_parent().get_node("HUD").add_child(chest_ui_instance)
	chest_ui_instance.chest = self
	chest_ui_instance.player_id = str(multiplayer.get_unique_id())
	chest_ui_instance.closed.connect(close_ui)

func close_ui():
	if chest_ui_instance and is_instance_valid(chest_ui_instance):
		chest_ui_instance.queue_free()
		chest_ui_instance = null

func interact(_player) -> void:
	if chest_ui_instance and is_instance_valid(chest_ui_instance):
		close_ui()
	else:
		open_ui()

func _on_interact_area_body_entered(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		body.nearby_interactable = self
		$InteractLabel.visible = true

func _on_interact_area_body_exited(body):
	if body.is_in_group("player") and body.name == str(multiplayer.get_unique_id()):
		if body.nearby_interactable == self:
			body.nearby_interactable = null
		$InteractLabel.visible = false
		close_ui()

@rpc("any_peer", "call_local", "reliable")
func request_chest_inventory(player_id: String):
	if !multiplayer.is_server():
		return
	sync_chest_inventory.rpc_id(int(player_id), chest_inventory)

@rpc("authority", "call_local", "reliable")
func sync_chest_inventory(data: Dictionary):
	chest_inventory = data
	if chest_ui_instance and is_instance_valid(chest_ui_instance):
		chest_ui_instance.refresh()

@rpc("any_peer", "call_local", "reliable")
func withdraw_item(player_id: String, item_id: String, amount: int):
	if !multiplayer.is_server():
		return
	if item_id not in chest_inventory:
		return
	var to_take = mini(amount, chest_inventory[item_id])
	chest_inventory[item_id] -= to_take
	if chest_inventory[item_id] <= 0:
		chest_inventory.erase(item_id)
	Inventory.addItem(player_id, item_id, to_take)
	sync_chest_inventory.rpc_id(int(player_id), chest_inventory)

@rpc("any_peer", "call_local", "reliable")
func deposit_item(player_id: String, item_id: String, amount: int):
	if !multiplayer.is_server():
		return
	if !Inventory.checkHasItemAmount(player_id, item_id, amount):
		return
	if !Inventory.removeItem(player_id, item_id, amount):
		return
	if item_id in chest_inventory:
		chest_inventory[item_id] += amount
	else:
		chest_inventory[item_id] = amount
	sync_chest_inventory.rpc_id(int(player_id), chest_inventory)
