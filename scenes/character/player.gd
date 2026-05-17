extends CharacterBody2D

signal mob_killed
signal object_destroyed
signal player_killed

@export var playerName : String:
	set(value):
		playerName = value
		$PlayerUi.setPlayerName(value)
		
@export var characterFile : String:
	set(value):
		characterFile = value
		$MovingParts/Sprite2D.texture = load("res://assets/characters/bodies/"+value)
		
var inventory : Control
var nearby_chest = null
var nearby_boat = null
var on_boat := false
var current_boat = null

var equippedItem : String:
	set(value):
		equippedItem = value
		if value in Items.equips:
			var itemData = Items.equips[value]
			if "projectile" in itemData:
				spawnsProjectile = itemData["projectile"]
			else:
				spawnsProjectile = ""

#stats
@export var maxHP := 250.0
@export var hp := maxHP:
	set(value):
		hp = value
		$bloodParticles.emitting = true
		$PlayerUi.setHPBarRatio(hp/maxHP)
		if hp <= 0:
			die()
@export var speed := 200
var spawnsProjectile := ""
@export var attackDamage := 10:
	get:
		if equippedItem:
			return Items.equips[equippedItem]["damage"] + attackDamage
		else:
			return attackDamage
var damageType := "normal":
	get:
		if equippedItem:
			return Items.equips[equippedItem]["damageType"]
		else:
			return damageType
var attackRange := 1.0:
	set(value):
		var clampedVal = clampf(value, 1.0, 5.0)
		attackRange = clampedVal
		%HitCollision.shape.height = 20 * clampedVal

func _ready():
	if multiplayer.is_server():
		Inventory.itemRemoved.connect(itemRemoved)
		mob_killed.connect(mobKilled)
		player_killed.connect(enemyPlayerKilled)
		object_destroyed.connect(objectDestroyed)
	if name == str(multiplayer.get_unique_id()):
		inventory = get_parent().get_parent().get_node("HUD/Inventory")
		inventory.player = self
		$Camera2D.enabled = true
	Multihelper.player_disconnected.connect(disconnected)

func visibilityFilter(id):
	if id == int(str(name)):
		return false
	return true

@rpc("any_peer", "call_local", "reliable")
func sendMessage(text):
	if multiplayer.is_server():
		var messageBoxScene := preload("res://scenes/ui/chat/message_box.tscn")
		var messageBox := messageBoxScene.instantiate()
		%PlayerMessages.add_child(messageBox, true)
		messageBox.text = str(text)

func disconnected(id):
	if str(id) == name:
		die()
	
func _process(_delta):
	if str(multiplayer.get_unique_id()) == name:
		var vel = Input.get_vector("walkLeft", "walkRight", "walkUp", "walkDown") * speed
		var mouse_position = get_global_mouse_position()
		var direction_to_mouse = mouse_position - global_position
		var angle = direction_to_mouse.angle()
		var doingAction = Input.is_action_pressed("leftClickAction")
		#Apply local movement
		moveProcess(vel, angle, doingAction)
		#Send input to server for replication
		var inputData = {
			"vel": vel,
			"angle": angle,
			"doingAction": doingAction
		}
		sendInputstwo.rpc_id(1, inputData)
		sendPos.rpc(position)

@rpc("any_peer", "call_local", "reliable")
func sendInputstwo(data):
	moveServer(data["vel"], data["angle"], data["doingAction"])

@rpc("any_peer", "call_local", "reliable")
func moveServer(vel, angle, doingAction):
	$MovingParts.rotation = angle
	handleAnims(vel,doingAction)

@rpc("any_peer", "call_local", "reliable")
func sendPos(pos):
	position = pos

func moveProcess(vel, angle, doingAction):
	if on_boat:
		if vel != Vector2.ZERO:
			var new_pos = position + vel * get_process_delta_time()
			if _is_water_position(new_pos):
				position = new_pos
		$MovingParts.rotation = angle
		handleAnims(vel, doingAction)
		return
	velocity = vel
	if velocity != Vector2.ZERO:
		move_and_slide()
	$MovingParts.rotation = angle
	handleAnims(vel, doingAction)

func handleAnims(vel, doing_action):
	if doing_action:
		var action_anim = Items.equips[equippedItem]["attack"] if equippedItem else "punching"
		if !$AnimationPlayer.is_playing() or $AnimationPlayer.current_animation != action_anim:
			$AnimationPlayer.play(action_anim)
	elif vel != Vector2.ZERO:
		if !$AnimationPlayer.is_playing() or $AnimationPlayer.current_animation != "walking":
			$AnimationPlayer.play("walking")
	else:
		$AnimationPlayer.stop()

func _on_next_item():
	inventory.nextSelection()

# Define what happens when previousItem is triggered
func _on_previous_item():
	inventory.prevSelection()

# Handle input events
func _unhandled_input(event):
	if name != str(multiplayer.get_unique_id()):
		return
	if event.is_action_pressed("nextItem"):
		_on_next_item()
	elif event.is_action_pressed("previousItem"):
		_on_previous_item()
	elif event.is_action_pressed("interact"):
		_on_interact()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key = event.physical_keycode
		if key >= KEY_1 and key <= KEY_9:
			inventory.setSelection(key - KEY_1)

func _on_interact():
	if on_boat:
		_disembark()
	elif nearby_boat and is_instance_valid(nearby_boat):
		if _is_water_position(nearby_boat.position):
			_board(nearby_boat)
		else:
			if multiplayer.is_server():
				nearby_boat.pickup(str(name))
			else:
				nearby_boat.pickup.rpc_id(1, str(name))
			nearby_boat = null
	elif nearby_chest and is_instance_valid(nearby_chest):
		if nearby_chest.chest_ui_instance and is_instance_valid(nearby_chest.chest_ui_instance):
			nearby_chest.close_ui()
		else:
			nearby_chest.open_ui()
	elif equippedItem == "torch" and Inventory.checkHasItem(str(name), "torch") and not _is_water_position(get_global_mouse_position()):
		if multiplayer.is_server():
			placeTorch(get_global_mouse_position())
		else:
			placeTorch.rpc_id(1, get_global_mouse_position())
	elif Inventory.checkHasItem(str(name), "boat"):
		if multiplayer.is_server():
			placeBoat(get_global_mouse_position())
		else:
			placeBoat.rpc_id(1, get_global_mouse_position())
	elif Inventory.checkHasItem(str(name), "chest"):
		if multiplayer.is_server():
			placeChest(get_global_mouse_position())
		else:
			placeChest.rpc_id(1, get_global_mouse_position())

func _board(boat):
	on_boat = true
	current_boat = boat
	collision_mask = 0
	position = boat.position
	sendPos.rpc(position)
	boat.set_boarded.rpc(str(name))

func _disembark():
	on_boat = false
	collision_mask = 1
	if current_boat and is_instance_valid(current_boat):
		current_boat.set_boarded.rpc("")
		position = _find_nearest_land(position)
		sendPos.rpc(position)
	current_boat = null

func _is_water_position(world_pos: Vector2) -> bool:
	var map = get_parent().get_parent().get_node_or_null("Map")
	if !map:
		return false
	var tile_pos = map.tile_map.local_to_map(world_pos)
	var atlas = map.tile_map.get_cell_atlas_coords(0, tile_pos)
	return atlas in [Vector2i(18, 0), Vector2i(19, 0)]

func _find_nearest_land(world_pos: Vector2) -> Vector2:
	var map = get_parent().get_parent().get_node_or_null("Map")
	if !map:
		return world_pos
	var land_coords = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0),
					   Vector2i(3,0), Vector2i(16,0), Vector2i(17,0)]
	var tile_pos = map.tile_map.local_to_map(world_pos)
	for radius in range(1, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var check = tile_pos + Vector2i(dx, dy)
					if map.tile_map.get_cell_atlas_coords(0, check) in land_coords:
						return map.tile_map.map_to_local(check)
	return world_pos

@rpc("any_peer", "call_remote", "reliable")
func placeBoat(at: Vector2):
	if !multiplayer.is_server():
		return
	if !Inventory.checkHasItem(str(name), "boat"):
		return
	Inventory.removeItem(str(name), "boat", 1)
	Items.spawnPlaceableRpc.rpc("boat", at)

@rpc("any_peer", "call_remote", "reliable")
func placeChest(at: Vector2):
	if !multiplayer.is_server():
		return
	if !Inventory.checkHasItem(str(name), "chest"):
		return
	Inventory.removeItem(str(name), "chest", 1)
	Items.spawnPlaceableRpc.rpc("chest", at)

@rpc("any_peer", "call_remote", "reliable")
func placeTorch(at: Vector2):
	if !multiplayer.is_server():
		return
	if !Inventory.checkHasItem(str(name), "torch"):
		return
	Inventory.removeItem(str(name), "torch", 1)
	Items.spawnPlaceableRpc.rpc("torch", at)

func punchCheckCollision():
	var id = multiplayer.get_unique_id()
	if spawnsProjectile:
		if str(id) == name:
			var mousePos := get_global_mouse_position()
			sendProjectile.rpc_id(1, mousePos)
	if !is_multiplayer_authority():
		return
	if equippedItem:
		Inventory.useItemDurability(str(name), equippedItem)
	for body in %HitArea.get_overlapping_bodies():
		if body != self and body.is_in_group("damageable"):
			body.getDamage(self, attackDamage, damageType)

@rpc("any_peer", "reliable")
func sendProjectile(towards):
	Items.spawnProjectile(self, spawnsProjectile, towards, "damageable")

@rpc("authority", "call_local", "reliable")
func increaseScore(by):
	hp += by * 5
	maxHP += by * 5
	attackDamage += by
	speed += by
	Multihelper.spawnedPlayers[int(str(name))]["score"] += by
	Multihelper.player_score_updated.emit()

func objectDestroyed():
	increaseScore.rpc(Constants.OBJECT_SCORE_GAIN)

func mobKilled():
	increaseScore.rpc(Constants.MOB_SCORE_GAIN)

func enemyPlayerKilled():
	increaseScore.rpc(Constants.PK_SCORE_GAIN)

func getDamage(causer, amount, _type):
	hp -= amount
	if (hp - amount) <= 0 and causer.is_in_group("player"):
		causer.player_killed.emit()

func die():
	if !multiplayer.is_server():
		return
	var peerId := int(str(name))
	Multihelper._deregister_character.rpc(peerId)
	dropInventory()
	queue_free()
	if peerId in multiplayer.get_peers():
		Multihelper.showSpawnUI.rpc_id(peerId)
		
func dropInventory():
	var inventoryDict = Inventory.inventories[name]
	for item in inventoryDict.keys():
		Items.spawnPickups(item, position, inventoryDict[item])
	Inventory.inventories[name] = {}
	Inventory.inventoryUpdated.emit(name)
	Inventory.inventories.erase(name)

@rpc("any_peer", "call_local", "reliable")
func tryEquipItem(id):
	if id in Inventory.inventories[name].keys():
		equipItem.rpc(id)

@rpc("any_peer", "call_local", "reliable")
func equipItem(id):
	equippedItem = id
	%Hands.visible = false
	%HeldItem.texture = load("res://assets/items/"+id+".png")
	if multiplayer.is_server() and "scene" in Items.equips[id]:
		for c in %Equipment.get_children():
			c.queue_free()
		var itemScene := load("res://scenes/character/equipments/"+Items.equips[id]["scene"]+".tscn")
		var item = itemScene.instantiate()
		%Equipment.add_child(item)
		item.data = {"player": str(name), "item": id}

@rpc("any_peer", "call_local", "reliable")
func unequipItem():
	equippedItem = ""
	%Hands.visible = true
	%HeldItem.texture = null
	if multiplayer.is_server():
		for c in %Equipment.get_children():
			c.queue_free()

func itemRemoved(id, item):
	if !multiplayer.is_server():
		return
	if id == str(name) and item == equippedItem:
		unequipItem.rpc()

func projectileHit(body):
	body.getDamage(self, attackDamage, damageType)
