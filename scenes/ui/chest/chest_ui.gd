extends PanelContainer

signal closed

var chest = null
var player_id : String

func _ready():
	Inventory.updateReceived.connect(_on_inventory_updated)
	refresh()

func _on_inventory_updated(id):
	if id == player_id:
		_populate_player_slots()

func refresh():
	_populate_player_slots()
	_populate_chest_slots()

func _populate_player_slots():
	for child in %PlayerSlots.get_children():
		child.queue_free()
	if player_id not in Inventory.inventories:
		return
	var inv = Inventory.inventories[player_id]
	if inv.is_empty():
		var empty_label = Label.new()
		empty_label.text = "(empty)"
		%PlayerSlots.add_child(empty_label)
		return
	for item_id in inv.keys():
		var btn = Button.new()
		btn.text = item_id + "  x" + str(inv[item_id])
		btn.pressed.connect(_on_deposit_item.bind(item_id, inv[item_id]))
		%PlayerSlots.add_child(btn)

func _populate_chest_slots():
	for child in %ChestSlots.get_children():
		child.queue_free()
	if chest == null or chest.chest_inventory.is_empty():
		var empty_label = Label.new()
		empty_label.text = "(empty)"
		%ChestSlots.add_child(empty_label)
		return
	for item_id in chest.chest_inventory.keys():
		var amount = chest.chest_inventory[item_id]
		var row = HBoxContainer.new()

		var lbl = Label.new()
		lbl.text = item_id + "  x" + str(amount)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)

		var take_all_btn = Button.new()
		take_all_btn.text = "Take All"
		take_all_btn.pressed.connect(_on_withdraw_item.bind(item_id, amount))
		row.add_child(take_all_btn)

		if amount > 1:
			var take_half_btn = Button.new()
			take_half_btn.text = "Take Half"
			take_half_btn.pressed.connect(_on_withdraw_item.bind(item_id, ceili(amount / 2.0)))
			row.add_child(take_half_btn)

		%ChestSlots.add_child(row)

func _on_deposit_item(item_id: String, amount: int):
	chest.deposit_item.rpc_id(1, player_id, item_id, amount)

func _on_withdraw_item(item_id: String, amount: int):
	chest.withdraw_item.rpc_id(1, player_id, item_id, amount)

func _on_close_pressed():
	closed.emit()
	queue_free()
