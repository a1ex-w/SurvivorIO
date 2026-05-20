# World pickup item — spawned by Items.spawnPickups, auto-collected by players on contact.
#
# Item name display: Items.format_item_name() converts the item ID to a readable label
# shown above the sprite (e.g. "stone_wall" -> "Stone Wall").
#
# TIMING GOTCHA: Items.spawnPickups sets itemId BEFORE add_child (which is call_deferred),
# so is_node_ready() is always false in the setter. _ready() is the authoritative setup path.
# The setter handles runtime changes only (e.g. if itemId is changed after spawn).
extends Area2D

@export var itemId : String:
	set(value):
		itemId = value
		if is_node_ready():
			$Sprite2D.texture = load("res://assets/items/"+value+".png")
			$Label.text = Items.format_item_name(value)

@export var stackCount := 1
var dropper_id: String = ""

func _ready():
	if itemId:
		$Sprite2D.texture = load("res://assets/items/"+itemId+".png")
		$Label.text = Items.format_item_name(itemId)
	if dropper_id != "":
		get_tree().create_timer(3.0).timeout.connect(func(): dropper_id = "")

func _on_body_entered(body):
	if multiplayer.is_server() and body.is_in_group("player"):
		if body.name == dropper_id:
			return
		# Guard: don't destroy the pickup if the inventory is full and this is a new item type.
		# Inventory.addItem silently fails at the slot cap, so we check first to avoid
		# destroying items the player has no room for.
		var inv: Dictionary = Inventory.inventories.get(body.name, {})
		var has_item := itemId in inv
		var has_room := inv.size() < Constants.MAX_INVENTORY_SLOTS
		if not has_item and not has_room:
			return
		queue_free()
		Inventory.addItem(body.name, itemId, stackCount)
