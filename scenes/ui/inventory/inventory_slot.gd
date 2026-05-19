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
			tooltip_text = Items.format_item_name(value)
			setItemDurability()
		else:
			$itemTexture.texture = null
			tooltip_text = ""
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
