# Single recipe slot in the crafting menu.
# Uses _process rect-polling for hover detection instead of mouse_entered signals
# because the full-area Button child (MOUSE_FILTER_STOP) blocks mouse_entered from
# reaching the parent PanelContainer. Rect polling works regardless of child filters.
# Turns red (self_modulate) when the player lacks ingredients.
# To add a new craftable item: add it to Items.recipes — this slot handles it automatically.
extends PanelContainer

signal recipeSelected(id)

var canCraft = false
var recipe := {}
var _hovered := false

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

func _ready():
	setState()

func _process(_delta: float) -> void:
	if not itemId:
		return
	var mouse_pos := get_global_mouse_position()
	# Suppress tooltip if the recipe detail panel is open and covers the mouse,
	# otherwise grid slots behind it would still show their tooltip.
	var blocked := false
	for box in get_tree().get_nodes_in_group("recipe_detail_box"):
		if (box as Control).visible and (box as Control).get_global_rect().has_point(mouse_pos):
			blocked = true
			break
	var now_hovered := not blocked and get_global_rect().has_point(mouse_pos)
	if now_hovered and not _hovered:
		get_tree().call_group("slot_tooltip", "show_tooltip", Items.format_item_name(itemId))
	elif not now_hovered and _hovered:
		get_tree().call_group("slot_tooltip", "hide_tooltip")
	_hovered = now_hovered

func setState():
	if canCraft:
		return
	self_modulate = Color.RED

func _on_button_pressed():
	recipeSelected.emit(itemId)
