extends PanelContainer

signal recipeSelected(id)

var canCraft = false
var recipe := {}
var itemId := "":
	set(value):
		recipe = Items.recipes[value]
		itemId = value
		var tex = load("res://assets/items/"+value+".png")
		if tex == null:
			var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.8, 0.5, 0.2, 1.0))
			tex = ImageTexture.create_from_image(img)
		$TextureRect.texture = tex
		tooltip_text = Items.format_item_name(value)

func _ready():
	setState()

func setState():
	if canCraft:
		return
	self_modulate = Color.RED

func _on_button_pressed():
	recipeSelected.emit(itemId)
