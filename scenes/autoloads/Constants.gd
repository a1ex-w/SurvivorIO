extends Node

#Multiplayer
var SERVER_IP := "game.dudeltron14.win"
const PORT := 3131
const USE_SSL := false # put certs in assets/certs, a free let's encrypt one works for itch.io
const TRUSTED_CHAIN_PATH := ""
const PRIVATE_KEY_PATH := ""

#Map
const MAP_SIZE := Vector2i(64,64)
const TILE_SIZE := 64
const LAND_TILES: Array[Vector2i] = [
	Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0),
	Vector2i(16,0), Vector2i(17,0)
]
const WATER_TILES: Array[Vector2i] = [Vector2i(18,0), Vector2i(19,0)]
# Base object cap for solo play. Actual cap = max(MAX_OBJECTS_BASE, player_count * OBJECTS_PER_PLAYER).
# Computed dynamically in main.gd so more players always have enough resources to gather.
const MAX_OBJECTS_BASE := 15
const OBJECTS_PER_PLAYER := 8
# Max enemies that can be targeting any single player at once.
const MAX_ENEMIES_PER_PLAYER := 3
# Absolute enemy cap regardless of player count. Actual cap used is
# min(MAX_ENEMIES_TOTAL, player_count * MAX_ENEMIES_PER_PLAYER).
const MAX_ENEMIES_TOTAL := 12
# Minimum world-space distance a replacement object must spawn from the one just destroyed.
# Prevents a new resource appearing in the same spot the player is already farming.
const OBJECT_RESPAWN_MIN_DIST := 512.0

#Player
const MAX_INVENTORY_SLOTS := 9
const OBJECT_SCORE_GAIN := 1
const MOB_SCORE_GAIN := 2
const PK_SCORE_GAIN := 4
const DISEMBARK_RANGE := 45.0
const TORCH_REPEL_RADIUS := 200.0