extends Node2D

const TILE_SIZE := 64
const MAP_W := 160
const MAP_H := 14
const VP_W := 1280.0
const SCROLL_SPEED := 55.0
const PLAYER_SPEED := 70.0
const ZOMBIE_SPEED := 50.0
const SPIDER_SPEED := 55.0
const PROJ_SPEED := 200.0
const TILESET_SOURCE := 1

var grass_coords: Array[Vector2i] = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0), Vector2i(16,0), Vector2i(17,0)]
var water_coords: Array[Vector2i] = [Vector2i(18,0), Vector2i(19,0)]

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D
@onready var actors_node: Node2D = $Actors

var players: Array[Sprite2D] = []
var zombies: Array[Sprite2D] = []
var spiders: Array[Sprite2D] = []
var projectiles: Array[Polygon2D] = []

var player_targets: Dictionary = {}
var player_timers: Dictionary = {}
var spider_targets: Dictionary = {}
var spider_timers: Dictionary = {}

var spawn_timer := 0.5
var proj_timer := 0.8

var body_textures: Array[Texture2D] = []
var zombie_tex: Texture2D
var spider_tex: Texture2D

func _ready() -> void:
	for i in range(9):
		var tex := load("res://assets/characters/bodies/%d.png" % i) as Texture2D
		if tex:
			body_textures.append(tex)
	zombie_tex = load("res://assets/characters/enemy/zombie.png")
	spider_tex = load("res://assets/characters/enemy/spider.png")

	var noise := FastNoiseLite.new()
	noise.seed = 42
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.03
	noise.fractal_octaves = 1
	for y in range(MAP_H):
		for x in range(MAP_W):
			var nv := noise.get_noise_2d(x, y)
			var coord: Vector2i = grass_coords[randi() % grass_coords.size()] if nv > 0.03 else water_coords[randi() % water_coords.size()]
			tile_map.set_cell(0, Vector2i(x, y), TILESET_SOURCE, coord, 0)

	camera.position = Vector2(VP_W * 0.5, MAP_H * TILE_SIZE * 0.5)

	# Spread initial actors across viewport
	for i in range(3):
		_spawn_player(randf_range(VP_W * 0.05, VP_W * 0.85), _rand_y())
	for i in range(4):
		_spawn_zombie(randf_range(VP_W * 0.1, VP_W * 1.1), _rand_y())
	for i in range(3):
		_spawn_spider(randf_range(VP_W * 0.2, VP_W * 1.2), _rand_y())

func _rand_y() -> float:
	return randf_range(TILE_SIZE * 2.0, (MAP_H - 2) * TILE_SIZE)

func _process(delta: float) -> void:
	camera.position.x += SCROLL_SPEED * delta

	_update_players(delta)
	_update_zombies(delta)
	_update_spiders(delta)
	_update_projectiles(delta)
	_cleanup(camera.position.x - VP_W * 0.65)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(1.5, 3.0)
		var rx := camera.position.x + VP_W * 0.5 + randf_range(20.0, 200.0)
		var ry := _rand_y()
		if players.size() < 5:
			_spawn_player(rx, ry)
		if zombies.size() < 6:
			_spawn_zombie(rx + randf_range(30.0, 120.0), clampf(ry + randf_range(-60.0, 60.0), TILE_SIZE * 2.0, (MAP_H - 2) * TILE_SIZE))
		if spiders.size() < 5:
			_spawn_spider(rx + randf_range(50.0, 180.0), clampf(ry + randf_range(-80.0, 80.0), TILE_SIZE * 2.0, (MAP_H - 2) * TILE_SIZE))

	proj_timer -= delta
	if proj_timer <= 0.0:
		proj_timer = randf_range(0.4, 1.1)
		_shoot()

func _update_players(delta: float) -> void:
	for p in players:
		if not is_instance_valid(p): continue
		player_timers[p] -= delta
		if player_timers[p] <= 0.0:
			player_timers[p] = randf_range(1.0, 2.5)
			var t: Vector2 = p.position + Vector2(randf_range(-120.0, 120.0), randf_range(-80.0, 80.0))
			t.y = clampf(t.y, TILE_SIZE, (MAP_H - 1) * TILE_SIZE)
			player_targets[p] = t
		var dir: Vector2 = (player_targets[p] as Vector2) - p.position
		if dir.length() > 4.0:
			p.position += dir.normalized() * PLAYER_SPEED * delta
			p.flip_h = dir.x < 0

func _update_zombies(delta: float) -> void:
	for z in zombies:
		if not is_instance_valid(z): continue
		var nearest: Vector2 = _nearest_player_within(z.position, 500.0)
		if nearest != Vector2.ZERO:
			var dir: Vector2 = nearest - z.position
			if dir.length() > 20.0:
				z.position += dir.normalized() * ZOMBIE_SPEED * delta
				z.flip_h = dir.x < 0
			else:
				z.position += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 10.0 * delta
		else:
			# Wander slowly when no player in range
			z.position.x += 18.0 * delta

func _update_spiders(delta: float) -> void:
	for s in spiders:
		if not is_instance_valid(s): continue
		spider_timers[s] -= delta
		if spider_timers[s] <= 0.0:
			spider_timers[s] = randf_range(1.5, 3.5)
			var t: Vector2 = s.position + Vector2(randf_range(-100.0, 100.0), randf_range(-70.0, 70.0))
			t.y = clampf(t.y, TILE_SIZE, (MAP_H - 1) * TILE_SIZE)
			spider_targets[s] = t
		var dir: Vector2 = (spider_targets[s] as Vector2) - s.position
		if dir.length() > 4.0:
			s.position += dir.normalized() * SPIDER_SPEED * delta
			s.flip_h = dir.x < 0

func _update_projectiles(delta: float) -> void:
	for proj in projectiles.duplicate():
		if not is_instance_valid(proj):
			projectiles.erase(proj)
			continue
		var dir: Vector2 = proj.get_meta("dir")
		proj.position += dir * PROJ_SPEED * delta
		if absf(proj.position.x - camera.position.x) > VP_W:
			proj.queue_free()
			projectiles.erase(proj)

func _cleanup(left_x: float) -> void:
	for p in players.duplicate():
		if not is_instance_valid(p) or p.position.x < left_x:
			if is_instance_valid(p): p.queue_free()
			players.erase(p); player_targets.erase(p); player_timers.erase(p)
	for z in zombies.duplicate():
		if not is_instance_valid(z) or z.position.x < left_x:
			if is_instance_valid(z): z.queue_free()
			zombies.erase(z)
	for s in spiders.duplicate():
		if not is_instance_valid(s) or s.position.x < left_x:
			if is_instance_valid(s): s.queue_free()
			spiders.erase(s); spider_targets.erase(s); spider_timers.erase(s)
	for proj in projectiles.duplicate():
		if not is_instance_valid(proj) or proj.position.x < left_x:
			if is_instance_valid(proj): proj.queue_free()
			projectiles.erase(proj)

func _spawn_player(x: float, y: float) -> void:
	if body_textures.is_empty(): return
	var s := Sprite2D.new()
	s.texture = body_textures[randi() % body_textures.size()]
	s.scale = Vector2(1.8, 1.8)
	s.position = Vector2(x, y)
	actors_node.add_child(s)
	players.append(s)
	player_targets[s] = s.position
	player_timers[s] = 0.0

func _spawn_zombie(x: float, y: float) -> void:
	var s := Sprite2D.new()
	s.texture = zombie_tex
	s.scale = Vector2(1.8, 1.8)
	s.position = Vector2(x, y)
	actors_node.add_child(s)
	zombies.append(s)

func _spawn_spider(x: float, y: float) -> void:
	var s := Sprite2D.new()
	s.texture = spider_tex
	s.scale = Vector2(1.6, 1.6)
	s.position = Vector2(x, y)
	actors_node.add_child(s)
	spiders.append(s)
	spider_targets[s] = s.position
	spider_timers[s] = 0.0

func _nearest_player_within(from: Vector2, max_dist: float) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for p in players:
		if not is_instance_valid(p): continue
		var d := from.distance_to(p.position)
		if d < best_d and d <= max_dist:
			best_d = d; best = p.position
	return best

func _nearest_player(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for p in players:
		if not is_instance_valid(p): continue
		var d := from.distance_to(p.position)
		if d < best_d:
			best_d = d; best = p.position
	return best

func _shoot() -> void:
	# Only spiders shoot
	if spiders.is_empty(): return
	var shooter: Sprite2D = spiders[randi() % spiders.size()]
	if not is_instance_valid(shooter): return

	var target: Vector2 = _nearest_player(shooter.position)
	var dir: Vector2 = (target - shooter.position).normalized() if target != Vector2.ZERO else Vector2.RIGHT.rotated(randf() * TAU)

	var proj := Polygon2D.new()
	proj.polygon = PackedVector2Array([Vector2(-5,-2), Vector2(5,-2), Vector2(5,2), Vector2(-5,2)])
	proj.color = Color(0.6, 0.1, 0.9, 0.9)
	proj.position = shooter.position
	proj.rotation = dir.angle()
	proj.set_meta("dir", dir)
	actors_node.add_child(proj)
	projectiles.append(proj)
