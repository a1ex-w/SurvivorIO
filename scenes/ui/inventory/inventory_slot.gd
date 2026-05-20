# Single inventory slot in the hotbar/inventory UI.
# On hover, calls the "slot_tooltip" group to show a floating label with the
# item's formatted name. The tooltip label lives in inventory.tscn (not inside
# this slot) so it doesn't affect slot sizing.
# To display a new item type, just ensure its PNG exists at
# res://assets/items/<item_id>.png — no other changes needed here.
extends PanelContainer

signal itemSelected(id)

var pId : int
var index : int
var selected := false
var itemId : String:
	set(value):
		itemId = value
		if value:
			$itemTexture.texture = _loadItemTexture(value)
			setItemDurability()
		else:
			$itemTexture.texture = null
			%durabilityBar.visible = false
			$Label.text = ""

var itemCount : int:
	set(value):
		itemCount = value
		$Label.text = "x"+str(value)

func _loadItemTexture(item_id: String) -> Texture2D:
	var tex = load("res://assets/items/" + item_id + ".png")
	if tex:
		return tex
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.8, 0.5, 0.2, 1.0))
	return ImageTexture.create_from_image(img)

func setItemDurability():
	if str(pId) not in Inventory.durabilities:
		return
	var itemDurabilities = Inventory.durabilities[str(pId)]
	if itemId in itemDurabilities:
		%durabilityBar.visible = true
		%durabilityBar.value = itemDurabilities[itemId] / Items.equips[itemId]["durability"]
	else:
		%durabilityBar.visible = false

func _on_mouse_entered() -> void:
	if itemId:
		get_tree().call_group("slot_tooltip", "show_tooltip", Items.format_item_name(itemId))

func _on_mouse_exited() -> void:
	get_tree().call_group("slot_tooltip", "hide_tooltip")

func selectionChanged(selectedId):
	if selectedId == index:
		selected = true
		$AnimationPlayer.play("selected")
		itemSelected.emit(itemId)
	elif selected:
		selected = false
		$AnimationPlayer.play("deselected")

func setRecipeText(count, needed):
	$Label.text = str(count)+"/"+str(needed)
	if count < needed:
		$bgTexture.modulate = Color.RED
