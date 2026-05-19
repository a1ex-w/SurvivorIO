extends Control

const PLAYER_COLOR := Color(1.0, 0.0, 0.0)   # Red color for player
@export var tile_size: Vector2 = Vector2(3, 3)
@export var tilemap: TileMap
@export var player: Node2D

@onready var coordsLabel := $"../../CoordsLabel"

func _ready():
	if Multihelper.map:
		tilemap = Multihelper.map.tile_map
	else:
		Multihelper.data_loaded.connect(_on_map_ready, CONNECT_ONE_SHOT)

func _on_map_ready():
	tilemap = Multihelper.map.tile_map

func _process(_delta):
	queue_redraw()

func _draw():
	if is_instance_valid(player) and tilemap != null:
		var tile_coords := tilemap.local_to_map(player.global_position)
		var player_pos := Vector2(tile_coords) * tile_size
		var player_rect := Rect2(player_pos, tile_size * 2)
		draw_rect(player_rect, PLAYER_COLOR)
		coordsLabel.text = str(tile_coords)
	else:
		var pid := str(multiplayer.get_unique_id())
		player = Multihelper.main.get_node_or_null("Players/" + pid) if Multihelper.main else null
