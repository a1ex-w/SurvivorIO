extends Node2D

const TILE_SIZE := 64
const MAP_H := 14
const VP_W := 1280.0
const SCROLL_SPEED := 55.0
const PLAYER_SPEED := 90.0
const ZOMBIE_SPEED := 58.0
const SPIDER_SPEED := 65.0
const PROJ_SPEED := 200.0
const TILESET_SOURCE := 1
const TERRAIN_SPAWN_CHANCE := 0.35
const GRASS_THRESHOLD := -0.1
const TERRAIN_MIN_SPACING := 100.0
const TERRAIN_COLLISION_RADIUS := 36.0

var grass_coords: Array[Vector2i] = [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0), Vector2i(16,0), Vector2i(17,0)]
var water_coords: Array[Vector2i] = [Vector2i(18,0), Vector2i(19,0)]

@onready var tile_map: TileMap = $TileMap
@onready var camera: Camera2D = $Camera2D
@onready var actors_node: Node2D = $Actors

var players: Array[Sprite2D] = []
var zombies: Array[Sprite2D] = []
var spiders: Array[Sprite2D] = []
var terrain_objects: Array[Sprite2D] = []
var projectiles: Array[Polygon2D] = []

# Each actor gets a waypoint they commit to for a fixed duration.
# No per-frame force recomputation — eliminates oscillation entirely.
var waypoints: Dictionary = {}
var waypoint_timers: Dictionary = {}

var spawn_timer := 0.5
var proj_timer := 0.8

var body_textures: Array[Texture2D] = []
var zombie_tex: Texture2D
var spider_tex: Texture2D
var terrain_textures: Array[Texture2D] = []

var noise := FastNoiseLite.new()
var noise_v := FastNoiseLite.new()
var tiles_generated_x := 0

func _tile_is_grass(tile_x: int, tile_y: int) -> bool:
	var h := noise.get_noise_2d(tile_x * 0.4, tile_y * 2.0)
	var warp := sin(tile_y * PI / 7.0) * 5.0
	var v := noise_v.get_noise_2d((tile_x + warp) * 1.0, tile_y * 0.2)
	return h > GRASS_THRESHOLD and v > GRASS_THRESHOLD

func _is_grass(world_x: float, world_y: float) -> bool:
	return _tile_is_grass(int(world_x / TILE_SIZE), int(world_y / TILE_SIZE))

func _ready() -> void:
	for i in range(9):
		var tex := load("res://assets/characters/bodies/%d.png" % i) as Texture2D
		if tex: body_textures.append(tex)
	zombie_tex = load("res://assets/characters/enemy/zombie.png")
	spider_tex = load("res://assets/characters/enemy/spider.png")
	for obj_name in ["tree1", "rock1", "rock2", "rock3"]:
		var tex := load("res://assets/objects/%s.png" % obj_name) as Texture2D
		if tex: terrain_textures.append(tex)

	noise.seed = 137
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	noise_v.seed = 521
	noise_v.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_v.frequency = 0.08
	noise_v.fractal_octaves = 3

	camera.position = Vector2(VP_W * 0.5, MAP_H * TILE_SIZE * 0.5)
	_generate_columns_up_to(int((VP_W * 1.5) / TILE_SIZE) + 1)

	for _i in range(12):
		var tx := randf_range(0.0, VP_W * 1.4)
		var tile_x := int(tx / TILE_SIZE)
		var tile_y := randi_range(1, MAP_H - 2)
		if _tile_is_grass(tile_x, tile_y):
			_spawn_terrain(tx, tile_y * TILE_SIZE + TILE_SIZE * 0.5)

	for _i in range(2):
		var pos := _rand_grass_pos(VP_W * 0.05, VP_W * 0.85)
		if pos != Vector2.ZERO: _spawn_player(pos.x, pos.y)
	for _i in range(2):
		var pos := _rand_grass_pos(VP_W * 0.1, VP_W * 1.1)
		if pos != Vector2.ZERO: _spawn_zombie(pos.x, pos.y)
	var sp := _rand_grass_pos(VP_W * 0.2, VP_W * 1.2)
	if sp != Vector2.ZERO: _spawn_spider(sp.x, sp.y)

func _generate_columns_up_to(target_x: int) -> void:
	while tiles_generated_x <= target_x:
		var x := tiles_generated_x
		var is_grass_col := false
		for y in range(MAP_H):
			var is_grass := _tile_is_grass(x, y)
			var coord: Vector2i = grass_coords[randi() % grass_coords.size()] if is_grass else water_coords[randi() % water_coords.size()]
			tile_map.set_cell(0, Vector2i(x, y), TILESET_SOURCE, coord, 0)
			if is_grass: is_grass_col = true
		if is_grass_col and randf() < TERRAIN_SPAWN_CHANCE:
			var tile_y := randi_range(1, MAP_H - 2)
			if _tile_is_grass(x, tile_y):
				_spawn_terrain(x * TILE_SIZE + randf_range(8.0, TILE_SIZE - 8.0), tile_y * TILE_SIZE + TILE_SIZE * 0.5)
		tiles_generated_x += 1

func _rand_y() -> float:
	return randf_range(TILE_SIZE * 2.0, (MAP_H - 2) * TILE_SIZE)

func _rand_grass_pos(min_x: float, max_x: float) -> Vector2:
	for _i in range(20):
		var x := randf_range(min_x, max_x)
		var y := _rand_y()
		if _is_grass(x, y): return Vector2(x, y)
	return Vector2.ZERO

func _rand_grass_pos_near(center: Vector2, radius: float) -> Vector2:
	for _i in range(20):
		var x := center.x + randf_range(-radius, radius)
		var y := center.y + randf_range(-radius * 0.6, radius * 0.6)
		y = clampf(y, TILE_SIZE * 2.0, (MAP_H - 2) * TILE_SIZE)
		if _is_grass(x, y): return Vector2(x, y)
	return Vector2.ZERO

# Pick a waypoint in roughly the flee direction, biased away from threat.
func _flee_waypoint(from: Vector2, threat: Vector2) -> Vector2:
	var flee_dir := (from - threat).normalized()
	for _i in range(15):
		var spread := randf_range(-50.0, 50.0)
		var d := flee_dir.rotated(deg_to_rad(spread))
		var dist := randf_range(120.0, 250.0)
		var candidate := from + d * dist
		candidate.y = clampf(candidate.y, TILE_SIZE * 2.0, (MAP_H - 2) * TILE_SIZE)
		if _is_grass(candidate.x, candidate.y):
			return candidate
	# Fallback: any grass point nearby
	return _rand_grass_pos_near(from, 150.0)

func _terrain_too_close(pos: Vector2) -> bool:
	for t in terrain_objects:
		if is_instance_valid(t) and t.position.distance_to(pos) < TERRAIN_MIN_SPACING: return true
	return false

func _terrain_blocks(pos: Vector2) -> bool:
	for t in terrain_objects:
		if is_instance_valid(t) and t.position.distance_to(pos) < TERRAIN_COLLISION_RADIUS: return true
	return false

func _nearest_monster(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for z in zombies:
		if not is_instance_valid(z): continue
		var d := from.distance_to(z.position)
		if d < best_d: best_d = d; best = z.position
	for s in spiders:
		if not is_instance_valid(s): continue
		var d := from.distance_to(s.position)
		if d < best_d: best_d = d; best = s.position
	return best

func _nearest_player(from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for p in players:
		if not is_instance_valid(p): continue
		var d := from.distance_to(p.position)
		if d < best_d: best_d = d; best = p.position
	return best

# Returns a slide direction perpendicular to the nearest blocking obstacle,
# biased toward the desired direction of travel.
func _slide_dir(pos: Vector2, desired: Vector2) -> Vector2:
	var best_away := Vector2.ZERO
	var best_dist := INF
	# Check nearby terrain objects
	for t in terrain_objects:
		if not is_instance_valid(t): continue
		var dist := pos.distance_to(t.position)
		if dist < TERRAIN_COLLISION_RADIUS * 3.0 and dist < best_dist:
			best_dist = dist
			best_away = (pos - t.position).normalized()
	# Check adjacent water tiles
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			if ox == 0 and oy == 0: continue
			if not _is_grass(pos.x + ox * TILE_SIZE, pos.y + oy * TILE_SIZE):
				var away := Vector2(-ox, -oy).normalized()
				var pseudo_dist := TILE_SIZE * 0.5  # treat water edges as close
				if pseudo_dist < best_dist:
					best_dist = pseudo_dist
					best_away = away
	if best_away == Vector2.ZERO: return Vector2.ZERO
	# Two perpendiculars to the obstacle normal — pick the one closer to desired direction
	var perp_a := Vector2(-best_away.y, best_away.x)
	var perp_b := -perp_a
	return perp_a if desired.dot(perp_a) >= desired.dot(perp_b) else perp_b

# Move toward a fixed waypoint. When blocked, slide along the obstacle surface.
# No per-frame force computation — waypoint is stable so direction is steady.
func _move_to(actor: Sprite2D, wp: Vector2, speed: float, delta: float) -> bool:
	var to_wp := wp - actor.position
	if to_wp.length() < 8.0: return true  # reached
	var dir := to_wp.normalized()
	if abs(dir.x) > 0.15:
		actor.flip_h = dir.x < 0
	var step := speed * delta
	# 1. Try direct path
	var np := actor.position + dir * step
	if _is_grass(np.x, np.y) and not _terrain_blocks(np):
		actor.position = np
		return false
	# 2. Slide along nearest obstacle surface
	var slide := _slide_dir(actor.position, dir)
	if slide != Vector2.ZERO:
		var sp := actor.position + slide * step
		if _is_grass(sp.x, sp.y) and not _terrain_blocks(sp):
			actor.position = sp
			return false
		# Try half-speed slide in case we're right at a corner
		var sp2 := actor.position + slide * step * 0.5
		if _is_grass(sp2.x, sp2.y) and not _terrain_blocks(sp2):
			actor.position = sp2
			return false
	# 3. Last resort: try cardinal perpendiculars
	for deg in [90.0, -90.0]:
		var d := dir.rotated(deg_to_rad(deg))
		var ap := actor.position + d * step
		if _is_grass(ap.x, ap.y) and not _terrain_blocks(ap):
			actor.position = ap
			return false
	return false  # fully stuck — waypoint timer will eventually pick a new target

func _process(delta: float) -> void:
	camera.position.x += SCROLL_SPEED * delta
	var needed_x := int((camera.position.x + VP_W) / TILE_SIZE) + 4
	if needed_x > tiles_generated_x:
		_generate_columns_up_to(needed_x)

	_update_players(delta)
	_update_zombies(delta)
	_update_spiders(delta)
	_update_projectiles(delta)
	_cleanup(camera.position.x - VP_W * 0.65)

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = randf_range(2.0, 4.0)
		var min_x := camera.position.x + VP_W * 0.5 + 20.0
		var max_x := camera.position.x + VP_W * 0.5 + 300.0
		if players.size() < 3:
			var pos := _rand_grass_pos(min_x, max_x)
			if pos != Vector2.ZERO: _spawn_player(pos.x, pos.y)
		if zombies.size() < 3:
			var pos := _rand_grass_pos(min_x, max_x)
			if pos != Vector2.ZERO: _spawn_zombie(pos.x, pos.y)
		if spiders.size() < 2:
			var pos := _rand_grass_pos(min_x, max_x)
			if pos != Vector2.ZERO: _spawn_spider(pos.x, pos.y)

	proj_timer -= delta
	if proj_timer <= 0.0:
		proj_timer = randf_range(0.4, 1.1)
		_shoot()

func _update_players(delta: float) -> void:
	for p in players:
		if not is_instance_valid(p): continue
		var threat := _nearest_monster(p.position)
		var fleeing := threat != Vector2.ZERO

		waypoint_timers[p] = waypoint_timers.get(p, 0.0) - delta
		var wp := waypoints.get(p, Vector2.ZERO) as Vector2
		var need_wp: bool = wp == Vector2.ZERO or waypoint_timers[p] <= 0.0

		if need_wp:
			if fleeing:
				wp = _flee_waypoint(p.position, threat)
				waypoint_timers[p] = 1.5
			else:
				wp = _rand_grass_pos_near(p.position, 150.0)
				waypoint_timers[p] = randf_range(2.5, 4.5)
			if wp == Vector2.ZERO: wp = p.position
			waypoints[p] = wp

		var speed := PLAYER_SPEED * 1.5 if fleeing else PLAYER_SPEED * 0.4
		var reached := _move_to(p, wp, speed, delta)
		if reached:
			waypoint_timers[p] = 0.0  # force new waypoint next frame

func _update_zombies(delta: float) -> void:
	for z in zombies:
		if not is_instance_valid(z): continue
		var target := _nearest_player(z.position)
		if target == Vector2.ZERO: continue

		waypoint_timers[z] = waypoint_timers.get(z, 0.0) - delta
		var wp := waypoints.get(z, Vector2.ZERO) as Vector2
		if wp == Vector2.ZERO or waypoint_timers[z] <= 0.0:
			waypoints[z] = target
			waypoint_timers[z] = 0.6  # re-aim at player frequently
			wp = target
		_move_to(z, wp, ZOMBIE_SPEED, delta)

func _update_spiders(delta: float) -> void:
	for s in spiders:
		if not is_instance_valid(s): continue
		var target := _nearest_player(s.position)
		if target == Vector2.ZERO: continue

		waypoint_timers[s] = waypoint_timers.get(s, 0.0) - delta
		var wp := waypoints.get(s, Vector2.ZERO) as Vector2
		if wp == Vector2.ZERO or waypoint_timers[s] <= 0.0:
			waypoints[s] = target
			waypoint_timers[s] = 0.5
			wp = target
		_move_to(s, wp, SPIDER_SPEED, delta)

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
			players.erase(p); waypoints.erase(p); waypoint_timers.erase(p)
	for z in zombies.duplicate():
		if not is_instance_valid(z) or z.position.x < left_x:
			if is_instance_valid(z): z.queue_free()
			zombies.erase(z); waypoints.erase(z); waypoint_timers.erase(z)
	for s in spiders.duplicate():
		if not is_instance_valid(s) or s.position.x < left_x:
			if is_instance_valid(s): s.queue_free()
			spiders.erase(s); waypoints.erase(s); waypoint_timers.erase(s)
	for t in terrain_objects.duplicate():
		if not is_instance_valid(t) or t.position.x < left_x:
			if is_instance_valid(t): t.queue_free()
			terrain_objects.erase(t)
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

func _spawn_terrain(x: float, y: float) -> void:
	if terrain_textures.is_empty(): return
	var pos := Vector2(x, y)
	if _terrain_too_close(pos): return
	var s := Sprite2D.new()
	s.texture = terrain_textures[randi() % terrain_textures.size()]
	s.scale = Vector2(0.8, 0.8)
	s.position = pos
	actors_node.add_child(s)
	terrain_objects.append(s)

func _shoot() -> void:
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
