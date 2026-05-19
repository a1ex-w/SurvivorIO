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
		queue_free()
		Inventory.addItem(body.name, itemId, stackCount)
