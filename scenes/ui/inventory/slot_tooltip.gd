# Floating tooltip label that follows the mouse cursor.
# Registered in the "slot_tooltip" group so any slot can call:
#   get_tree().call_group("slot_tooltip", "show_tooltip", "Item Name")
#   get_tree().call_group("slot_tooltip", "hide_tooltip")
# Lives in inventory.tscn at a high z_index — one instance shared by all slots.
# Gotcha: must be in the same viewport as the inventory (not a SubViewport).
extends Label

func _ready() -> void:
	add_to_group("slot_tooltip")
	hide()

func _process(_delta: float) -> void:
	if visible:
		global_position = get_global_mouse_position() + Vector2(10, -28)

func show_tooltip(item_name: String) -> void:
	text = item_name
	show()

func hide_tooltip() -> void:
	hide()
