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
		
const WALL_SNAP := 64.0
# Maximum distance (px) a player can place walls, doors, or windmills from their position.
# Clamped before grid-snapping so walls always land on the nearest tile within range.
const STRUCTURE_PLACE_RANGE := 128.0

var inventory : Control
var is_local := false
var nearby_interactable = null
var on_boat := false
var current_boat = null

# Called by interactables on body_entered. Hides the previous interactable's
# label so only one prompt is ever visible at a time.
func set_nearby_interactable(obj) -> void:
	if nearby_interactable and is_instance_valid(nearby_interactable) \
			and nearby_interactable != obj:
		var old_label = nearby_interactable.get_node_or_null("InteractLabel")
		if old_label:
			old_label.visible = false
	nearby_interactable = obj

var equippedItem : String:
	set(value):
		equippedItem = value
		if value in Items.equips:
			var itemData = Items.equips[value]
			spawnsProjectile = itemData.get("projectile", "")
			$AnimationPlayer.speed_scale = itemData.get("fire_rate", 1.0)
		else:
			spawnsProjectile = ""
			$AnimationPlayer.speed_scale = 1.0

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

const SPRINT_MULT := 1.6
const STAMINA_DRAIN := 25.0
const STAMINA_REGEN := 15.0
var maxStamina := 100.0
var stamina := 100.0
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
	is_local = (name == str(multiplayer.get_unique_id()))
	if is_local:
		inventory = get_parent().get_parent().get_node("HUD/Inventory")
		inventory.player = self
		$Camera2D.enabled = true
	Multihelper.player_disconnected.connect(disconnected)
	call_deferred("_init_crown")

func _exit_tree():
	if Multihelper.player_disconnected.is_connected(disconnected):
		Multihelper.player_disconnected.disconnect(disconnected)

func _init_crown() -> void:
	var pid := int(str(name))
	if pid in Multihelper.spawnedPlayers:
		$PlayerUi.setCrownWins(Multihelper.spawnedPlayers[pid].get("wins", 0))

# Forwards the updated win count to the player's UI crown label.
func update_crown(win_count: int) -> void:
	$PlayerUi.setCrownWins(win_count)

func visibilityFilter(id):
	if id == int(str(name)):
		return false
	return true

@rpc("any_peer", "call_local", "reliable")
func sendMessage(text):
	if multiplayer.is_server():
		if str(text).begins_with("/"):
			_handle_command(str(text))
			return
		var messageBoxScene := preload("res://scenes/ui/chat/message_box.tscn")
		var messageBox := messageBoxScene.instantiate()
		%PlayerMessages.add_child(messageBox, true)
		messageBox.text = str(text)

# Server-side chat command dispatcher. Only runs on the server (sendMessage guards this).
# To add a new command: add a match branch here and implement a _cmd_<name> handler below.
func _handle_command(text: String) -> void:
	var parts := text.split(" ", false)
	if parts.is_empty():
		return
	match parts[0]:
		"/give":
			if parts.size() < 2:
				_send_server_msg("Usage: /give points <name> <amount>  |  /give item <name> <item_id> <amount>")
				return
			match parts[1]:
				"points":
					if parts.size() < 4:
						_send_server_msg("Usage: /give points <name> <amount>")
						return
					_cmd_give_points(parts[2], parts[3].to_int())
				"item":
					if parts.size() < 5:
						_send_server_msg("Usage: /give item <name> <item_id> <amount>")
						return
					_cmd_give_item(parts[2], parts[3], parts[4].to_int())
				_:
					_send_server_msg("Usage: /give points <name> <amount>  |  /give item <name> <item_id> <amount>")

# Returns the peer ID for a player by display name, or -1 if not found.
func _find_pid(target_name: String) -> int:
	for pid in Multihelper.spawnedPlayers:
		if Multihelper.spawnedPlayers[pid]["name"] == target_name:
			return pid
	return -1

# Grants score to a player and triggers win condition if threshold is met.
func _cmd_give_points(target_name: String, amount: int) -> void:
	var pid := _find_pid(target_name)
	if pid == -1:
		_send_server_msg("Player '%s' not found." % target_name)
		return
	var player_node := get_node_or_null("/root/Game/Level/Main/Players/" + str(pid))
	if player_node:
		Multihelper.spawnedPlayers[pid]["score"] += amount
		var new_score: int = Multihelper.spawnedPlayers[pid]["score"]
		player_node._sync_score.rpc(new_score)
		_send_server_msg("Gave %d points to %s (total: %d)" % [amount, target_name, new_score])
		if new_score >= Victories.WIN_SCORE:
			Multihelper.trigger_win(pid)

# Adds items directly to a player's inventory. Inventory.addItem auto-syncs to the client.
# Validates item_id against known items/placeables/recipes to prevent inventory corruption.
func _cmd_give_item(target_name: String, item_id: String, amount: int) -> void:
	var pid := _find_pid(target_name)
	if pid == -1:
		_send_server_msg("Player '%s' not found." % target_name)
		return
	var known := item_id in Items.equips or item_id in Items.placeables or item_id in Items.recipes
	if not known:
		_send_server_msg("Unknown item '%s'." % item_id)
		return
	Inventory.addItem(str(pid), item_id, amount)
	_send_server_msg("Gave %dx %s to %s." % [amount, item_id, target_name])

func _send_server_msg(msg: String) -> void:
	var messageBoxScene := preload("res://scenes/ui/chat/message_box.tscn")
	var messageBox := messageBoxScene.instantiate()
	%PlayerMessages.add_child(messageBox, true)
	messageBox.text = "[Server] " + msg

func disconnected(id):
	if str(id) == name:
		die()
	
func _process(delta):
	if is_local:
		var is_sprinting = Input.is_key_pressed(KEY_SHIFT) and stamina > 0 and not on_boat and not _is_chat_open()
		var vel = Vector2.ZERO if _is_chat_open() else Input.get_vector("walkLeft", "walkRight", "walkUp", "walkDown") * speed
		if is_sprinting and vel != Vector2.ZERO:
			vel *= SPRINT_MULT
			stamina = max(0.0, stamina - STAMINA_DRAIN * delta)
		else:
			stamina = min(maxStamina, stamina + STAMINA_REGEN * delta)
		$PlayerUi.setStaminaBarRatio(stamina / maxStamina)
		if on_boat and current_boat and is_instance_valid(current_boat):
			var can_leave := _has_nearby_land(position, Constants.DISEMBARK_RANGE)
			current_boat.get_node("InteractLabel").text = "Press E to disembark" if can_leave else "Too far from shore"
		var mouse_position = get_global_mouse_position()
		var direction_to_mouse = mouse_position - global_position
		var angle = direction_to_mouse.angle()
		var doingAction = Input.is_action_pressed("leftClickAction") and not _is_chat_open()
		moveProcess(vel, angle, doingAction)
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

const MAP_BORDER_MARGIN := 32.0
const MAP_WORLD_SIZE := Vector2(
	Constants.MAP_SIZE.x * 64.0,
	Constants.MAP_SIZE.y * 64.0
)

func _clamp_to_map() -> void:
	position.x = clampf(position.x, MAP_BORDER_MARGIN, MAP_WORLD_SIZE.x - MAP_BORDER_MARGIN)
	position.y = clampf(position.y, MAP_BORDER_MARGIN, MAP_WORLD_SIZE.y - MAP_BORDER_MARGIN)

func moveProcess(vel, angle, doingAction):
	if on_boat:
		if vel != Vector2.ZERO:
			var new_pos = position + vel * get_process_delta_time()
			if _is_water_position(new_pos):
				position = new_pos
				_clamp_to_map()
		$MovingParts.rotation = angle
		handleAnims(vel, doingAction)
		return
	velocity = vel
	if velocity != Vector2.ZERO:
		move_and_slide()
		_clamp_to_map()
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

# Returns true while the chat input node is alive, used to suppress movement
# and item actions so typed characters don't trigger game controls.
# Also returns true while the in-game settings overlay is open.
func _is_chat_open() -> bool:
	if not get_tree().get_nodes_in_group("settings_open").is_empty():
		return true
	return inventory != null and is_instance_valid(inventory) \
		and inventory.chatinput != null and is_instance_valid(inventory.chatinput)

func _on_next_item():
	inventory.nextSelection()

# Define what happens when previousItem is triggered
func _on_previous_item():
	inventory.prevSelection()

# Handle input events
func _unhandled_input(event):
	if not is_local:
		return
	if _is_chat_open():
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
		elif key == KEY_Q:
			_on_drop_item()

func _get_selected_item() -> String:
	var inv: Dictionary = Inventory.inventories.get(str(name), {})
	var keys: Array = inv.keys()
	var slot: int = inventory.selectedSlot if inventory else 0
	return keys[slot] if slot < keys.size() else ""

func _on_interact():
	if on_boat:
		if _has_nearby_land(position, Constants.DISEMBARK_RANGE):
			_disembark()
	elif nearby_interactable and is_instance_valid(nearby_interactable):
		nearby_interactable.interact(self)
	else:
		var selected := _get_selected_item()
		if selected not in Items.placeables:
			return
		var at := get_global_mouse_position()
		if selected == "boat":
			at = _clamp_place_range(at, 50.0)
		elif selected in ["wall", "stone_wall", "door", "stone_door"]:
			at = _clamp_place_range(at, STRUCTURE_PLACE_RANGE)
			at = (at / WALL_SNAP).round() * WALL_SNAP
		elif selected == "windmill":
			at = _clamp_place_range(at, STRUCTURE_PLACE_RANGE)
			# Snap to wall-grid midpoints (32, 96, 160...) so windmill edges
			# land exactly on wall boundaries. Two windmills 128px apart = flush.
			var half := Vector2(WALL_SNAP * 0.5, WALL_SNAP * 0.5)
			at = ((at - half) / WALL_SNAP).round() * WALL_SNAP + half
		var err := _placement_error(selected, at)
		if err:
			_show_placement_error(err)
			return
		if multiplayer.is_server():
			_place_selected(selected, at)
		else:
			_place_selected.rpc_id(1, selected, at)

func board(boat):
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

func _get_map():
	return get_parent().get_parent().get_node_or_null("Map")

func _clamp_place_range(target: Vector2, max_dist: float) -> Vector2:
	var offset := target - global_position
	if offset.length() > max_dist:
		offset = offset.normalized() * max_dist
	return global_position + offset

func _has_nearby_land(world_pos: Vector2, max_px: float) -> bool:
	var map = _get_map()
	if !map:
		return false
	var tile_pos = map.tile_map.local_to_map(world_pos)
	var max_tiles := int(ceil(max_px / Constants.TILE_SIZE)) + 1
	for radius in range(0, max_tiles + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var check: Vector2i = tile_pos + Vector2i(dx, dy)
					if map.tile_map.get_cell_atlas_coords(0, check) in Constants.LAND_TILES:
						var land_world: Vector2 = map.tile_map.map_to_local(check)
						if world_pos.distance_to(land_world) <= max_px:
							return true
	return false

func _is_water_position(world_pos: Vector2) -> bool:
	var map = _get_map()
	if !map:
		return false
	var tile_pos = map.tile_map.local_to_map(world_pos)
	var atlas = map.tile_map.get_cell_atlas_coords(0, tile_pos)
	return atlas in Constants.WATER_TILES

func _find_nearest_land(world_pos: Vector2) -> Vector2:
	var map = _get_map()
	if !map:
		return world_pos
	var tile_pos = map.tile_map.local_to_map(world_pos)
	for radius in range(1, 15):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if abs(dx) == radius or abs(dy) == radius:
					var check = tile_pos + Vector2i(dx, dy)
					if map.tile_map.get_cell_atlas_coords(0, check) in Constants.LAND_TILES:
						return map.tile_map.map_to_local(check)
	return world_pos

@rpc("any_peer", "call_remote", "reliable")
func _place_selected(item_id: String, at: Vector2):
	if !multiplayer.is_server():
		return
	if item_id not in Items.placeables:
		return
	if !Inventory.checkHasItem(str(name), item_id):
		return
	if _placement_blocked(at) != "":
		return
	Inventory.removeItem(str(name), item_id, 1)
	Items.spawnPlaceableRpc.rpc(item_id, at, int(name))

# Returns the name of whatever is blocking placement at `at`, or "" if clear.
# TileMap/TileMapLayer excluded (terrain). Player excluded via get_rid().
# Return value is used both to block placement (server) and to label the error (client).
func _placement_blocked(at: Vector2) -> String:
	var space := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40, 40)
	query.shape = shape
	query.transform = Transform2D(0, at)
	query.exclude = [get_rid()]
	for result in space.intersect_shape(query, 4):
		var collider = result.get("collider")
		if collider is TileMap or collider is TileMapLayer:
			continue
		return (collider as Node).name
	return ""

# Checks all placement rules for item_id at world position at.
# Returns a human-readable error string, or "" if placement is allowed.
# Called client-side before the server RPC to give immediate feedback.
# Gotcha: client physics state must match server — safe for call_local spawned objects.
func _placement_error(item_id: String, at: Vector2) -> String:
	if item_id != "boat" and _is_water_position(at):
		return "Cannot place %s in water" % Items.format_item_name(item_id)
	var blocker := _placement_blocked(at)
	if blocker:
		return "Too close to %s" % Items.format_item_name(blocker)
	return ""

# Spawns a temporary floating error label above the player that rises and fades.
# Client-only — only call on the local player (is_local guard not needed, caller ensures it).
func _show_placement_error(msg: String) -> void:
	var label := Label.new()
	label.text = msg
	label.position = Vector2(-80, -90)
	label.add_theme_color_override("font_color", Color(1, 0.35, 0.35))
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	add_child(label)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 1.5)
	tween.tween_property(label, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(label.queue_free)

func _on_drop_item() -> void:
	var inv: Dictionary = Inventory.inventories.get(str(name), {})
	if inv.is_empty():
		return
	var keys: Array = inv.keys()
	if inventory.selectedSlot >= keys.size():
		return
	var item: String = keys[inventory.selectedSlot]
	if multiplayer.is_server():
		dropItem(item)
	else:
		dropItem.rpc_id(1, item)

@rpc("any_peer", "call_remote", "reliable")
func dropItem(item: String):
	if !multiplayer.is_server():
		return
	if !Inventory.checkHasItem(str(name), item):
		return
	Inventory.removeItem(str(name), item, 1)
	var pickups := get_node("/root/Game/Level/Main/Pickups")
	var pickup: Area2D = preload("res://scenes/item/pickup.tscn").instantiate()
	pickup.itemId = item
	pickup.position = position
	pickup.dropper_id = str(name)
	pickups.call_deferred("add_child", pickup, true)

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
func rewardPlayer(by):
	hp += by * 5
	maxHP += by * 5
	attackDamage += by
	speed += by
	if multiplayer.is_server():
		var pid := int(str(name))
		if pid in Multihelper.spawnedPlayers:
			var new_score: int = Multihelper.spawnedPlayers[pid]["score"] + by
			Multihelper.spawnedPlayers[pid]["score"] = new_score
			_sync_score.rpc(new_score)
			if new_score >= Victories.WIN_SCORE:
				Multihelper.trigger_win(pid)

@rpc("authority", "call_local", "reliable")
func _sync_score(new_score: int) -> void:
	var pid := int(str(name))
	if pid in Multihelper.spawnedPlayers:
		Multihelper.spawnedPlayers[pid]["score"] = new_score
	Multihelper.player_score_updated.emit()

func objectDestroyed():
	rewardPlayer.rpc(Constants.OBJECT_SCORE_GAIN)

func mobKilled():
	rewardPlayer.rpc(Constants.MOB_SCORE_GAIN)

func enemyPlayerKilled():
	rewardPlayer.rpc(Constants.PK_SCORE_GAIN)

func getDamage(causer, amount, _type):
	hp -= amount
	if hp <= 0 and causer.is_in_group("player"):
		causer.player_killed.emit()

# Restores full HP on all peers and teleports to a random walkable tile.
# Called by the server at the start of each new round.
@rpc("authority", "call_local", "reliable")
func respawn() -> void:
	hp = maxHP
	if multiplayer.is_server() and Multihelper.map \
			and not Multihelper.map.walkable_tiles.is_empty():
		var spawn_pos: Vector2 = Multihelper.map.tile_map.map_to_local(
			Multihelper.map.walkable_tiles.pick_random()
		)
		sendPos.rpc(spawn_pos)

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
	if name not in Inventory.inventories:
		return
	var inventoryDict = Inventory.inventories[name]
	for item in inventoryDict.keys():
		Items.spawnPickups(item, position, inventoryDict[item])
	Inventory.inventories[name] = {}
	Inventory.inventoryUpdated.emit(name)
	Inventory.inventories.erase(name)

@rpc("any_peer", "call_local", "reliable")
func tryEquipItem(id):
	if name in Inventory.inventories and id in Inventory.inventories[name]:
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
