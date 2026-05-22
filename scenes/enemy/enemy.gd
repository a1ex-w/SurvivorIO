extends CharacterBody2D

# Server-authoritative enemy AI driven by a four-state machine.
# Stats are loaded from Items.mobs by enemyId — adding a new mob type
# requires only a new entry in Items.mobs and a sprite PNG; no code changes needed.
#
# States:
#   IDLE             — wanders randomly; scans for players, then nearby structures
#   CHASE            — moves toward targetPlayer; attacks when in attackRange
#   ATTACK           — attacks targetPlayer; returns to CHASE if target moves away
#   ATTACK_STRUCTURE — attacks a nearby player-placed structure; player detection preempts this
#
# Extending the state machine:
#   1. Add a value to the State enum.
#   2. Add a match branch in _process calling a new _tick_<state>() function.
#   3. Implement _tick_<state>() — set state = State.X to transition out.
#
# Multiplayer: all logic is server-only. Position is synced to clients via
# MultiplayerSynchronizer. Client visuals are driven by position updates.
#
# Structure targeting note: _find_nearest_structure scans the "placeable" group
# (walls, windmills, doors, etc.) — world breakables are excluded.

enum State { IDLE, CHASE, ATTACK, ATTACK_STRUCTURE }
var state := State.IDLE

var spawner: Node2D

# targetPlayerId is set by the spawner at spawn time for enemy-count bookkeeping.
# The AI may chase a different player than this — targetPlayerId should not change
# after spawn. It is only used by die() to update the spawner's count.
var targetPlayer: CharacterBody2D
@export var targetPlayerId: int:
	set(value):
		targetPlayerId = value
		targetPlayer = get_node_or_null("../../Players/" + str(value))
		if is_instance_valid(targetPlayer):
			state = State.CHASE

# Stats — all set automatically from Items.mobs[enemyId] via the enemyId setter.
# IMPORTANT: brute and wraith require PNG sprites at assets/characters/enemy/<id>.png.
# Missing sprites print a load error but do not crash.
@export var enemyId := "":
	set(value):
		enemyId = value
		var data = Items.mobs[value]
		var tex := load("res://assets/characters/enemy/" + value + ".png") as Texture2D
		if tex == null:
			var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
			img.fill(Color(1.0, 0.0, 1.0))  # magenta = missing sprite
			tex = ImageTexture.create_from_image(img)
		%Sprite2D.texture = tex
		%Sprite2D.scale = data.get("sprite_scale", Vector2(1.0, 1.0))
		if "collision_radius" in data:
			var shape := CircleShape2D.new()
			shape.radius = data["collision_radius"]
			$CollisionShape2D.shape = shape
		for stat in data.keys():
			set(stat, data[stat])

var maxhp := 100.0:
	set(value):
		maxhp = value
		hp = value
var hp := maxhp:
	set(value):
		hp = value
		$EnemyUI/HPBar.value = hp / maxhp
var speed := 50.0
var attack := ""
var attackRange := 50.0
var attackDamage := 20.0
var drops := {}

# detect_radius: player must be this close before enemy starts chasing.
# lose_radius:   enemy gives up chase when target moves beyond this (>= detect_radius
#                to prevent rapid IDLE↔CHASE flickering at the boundary).
var detect_radius := 300.0
var lose_radius := 500.0

const WANDER_ARRIVAL_DIST := 48.0
var _wander_target := Vector2.ZERO

# Current structure target. Cleared when the structure is destroyed or a player
# enters detect_radius. Player targets always preempt structure targets.
var _structure_target: Node2D = null

func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	match state:
		State.IDLE:             _tick_idle()
		State.CHASE:            _tick_chase()
		State.ATTACK:           _tick_attack()
		State.ATTACK_STRUCTURE: _tick_attack_structure()

# Wanders to random tiles. Scans for players first; if none found, scans for
# damageable structures within attackRange and attacks them.
func _tick_idle() -> void:
	var nearest_player := _find_nearest_player()
	if nearest_player:
		targetPlayer = nearest_player
		_structure_target = null
		state = State.CHASE
		return
	var nearest_structure := _find_nearest_structure()
	if nearest_structure:
		_structure_target = nearest_structure
		state = State.ATTACK_STRUCTURE
		return
	if _wander_target == Vector2.ZERO or position.distance_to(_wander_target) < WANDER_ARRIVAL_DIST:
		_pick_wander_target()
	if _wander_target != Vector2.ZERO:
		var dir := (_wander_target - position).normalized()
		velocity = dir * speed * 0.5
		$MovingParts.look_at(_wander_target)
		move_and_slide()

# Chases targetPlayer. Retargets to the nearest player each tick so a closer
# player always takes priority. Drops to IDLE if target is lost or moves beyond lose_radius.
func _tick_chase() -> void:
	if not is_instance_valid(targetPlayer) \
			or position.distance_to(targetPlayer.position) > lose_radius:
		targetPlayer = null
		state = State.IDLE
		_wander_target = Vector2.ZERO
		return
	var nearest := _find_nearest_player()
	if nearest:
		targetPlayer = nearest
	rotateToTarget()
	if position.distance_to(targetPlayer.position) <= attackRange:
		state = State.ATTACK
	else:
		_move_toward_target()

# Attacks targetPlayer. Retargets to nearest player between shots (when cooldown
# has elapsed) so the enemy finishes its current attack before switching focus.
func _tick_attack() -> void:
	if not is_instance_valid(targetPlayer):
		targetPlayer = null
		state = State.IDLE
		_wander_target = Vector2.ZERO
		return
	if $AttackCooldown.is_stopped():
		var nearest := _find_nearest_player()
		if nearest:
			targetPlayer = nearest
	rotateToTarget()
	if position.distance_to(targetPlayer.position) > attackRange:
		state = State.CHASE
	else:
		_try_attack()

# Distance from structure center at which an attack fires.
# 100px covers windmill half-size (64px) + brute collision radius (20px) + margin.
# Must be larger than windmill_half + max_enemy_radius or large enemies can't reach threshold.
const STRUCTURE_ATTACK_DIST := 100.0

# Moves toward and attacks _structure_target. Preempted if a player enters detect_radius.
# Ranged mobs fire a projectile toward the structure; melee mobs call getDamage directly.
func _tick_attack_structure() -> void:
	var nearest_player := _find_nearest_player()
	if nearest_player:
		targetPlayer = nearest_player
		_structure_target = null
		state = State.CHASE
		return
	if not is_instance_valid(_structure_target):
		_structure_target = null
		state = State.IDLE
		return
	$MovingParts.look_at(_structure_target.position)
	var dist := position.distance_to(_structure_target.position)
	if dist > STRUCTURE_ATTACK_DIST:
		var dir := (_structure_target.position - position).normalized()
		velocity = dir * speed
		move_and_slide()
	elif $AttackCooldown.is_stopped():
		$AttackCooldown.start()
		if attack.contains("projectile"):
			_fire_projectile_at(_structure_target.position)
		else:
			_structure_target.getDamage(self, attackDamage, "normal")

# Returns the nearest player node within detect_radius, or null.
func _find_nearest_player() -> CharacterBody2D:
	var nearest: CharacterBody2D = null
	var nearest_dist := detect_radius
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p): continue
		var d := position.distance_to((p as Node2D).position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest

# Returns the nearest player-placed structure within detect_radius, or null.
# Scans the "placeable" group — only objects placed by players (walls, windmills, etc.).
# World breakables (trees, rocks) are excluded because they are not in "placeable".
# To make a new placeable targetable by enemies: add "placeable" to its scene groups.
func _find_nearest_structure() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist := detect_radius
	for obj in get_tree().get_nodes_in_group("placeable"):
		if not is_instance_valid(obj): continue
		var d := position.distance_to((obj as Node2D).position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = obj
	return nearest

# Picks a random walkable tile as the next wander destination.
func _pick_wander_target() -> void:
	if Multihelper.map and not Multihelper.map.walkable_tiles.is_empty():
		_wander_target = Multihelper.map.tile_map.map_to_local(
			Multihelper.map.walkable_tiles.pick_random()
		)

# Rotates MovingParts to face targetPlayer. Only valid in CHASE and ATTACK states.
func rotateToTarget() -> void:
	$MovingParts.look_at(targetPlayer.position)

# Moves toward targetPlayer applying torch repulsion from the coal_repeller group.
func _move_toward_target() -> void:
	var direction := (targetPlayer.position - position).normalized()
	velocity = direction * speed
	for torch in get_tree().get_nodes_in_group("coal_repeller"):
		if not is_instance_valid(torch): continue
		var dist: float = position.distance_to((torch as Node2D).position)
		if dist < Constants.TORCH_REPEL_RADIUS and dist > 0:
			var repel := (position - (torch as Node2D).position).normalized()
			var t := sqrt(1.0 - dist / Constants.TORCH_REPEL_RADIUS)
			velocity += repel * speed * 4.0 * t
	move_and_slide()

# Fires the enemy's attack toward targetPlayer if the cooldown has elapsed.
func _try_attack() -> void:
	if not $AttackCooldown.is_stopped():
		return
	$AttackCooldown.start()
	_fire_projectile_at(targetPlayer.position)

# Instantiates and launches the attack scene toward target_pos.
# Applies projectile_sprite and projectile_color from Items.mobs if set.
# Used for both player attacks (_try_attack) and structure attacks (_tick_attack_structure).
func _fire_projectile_at(target_pos: Vector2) -> void:
	var projectileScene := load("res://scenes/attacks/" + attack + ".tscn")
	var projectile = projectileScene.instantiate()
	spawner.get_node("Projectiles").add_child(projectile, true)
	$MovingParts.look_at(target_pos)
	projectile.position = position
	projectile.get_node("MovingParts").rotation = $MovingParts.rotation
	projectile.hitPlayer.connect(hitPlayer)
	projectile.targetPos = target_pos
	var mob_data: Dictionary = Items.mobs[enemyId]
	var sprite := projectile.get_node_or_null("MovingParts/Adjust/Sprite2D") as Sprite2D
	if sprite:
		var custom_sprite: String = mob_data.get("projectile_sprite", "")
		if custom_sprite:
			var tex := load(custom_sprite) as Texture2D
			if tex:
				sprite.texture = tex
				sprite.hframes = 1
		var color: Color = mob_data.get("projectile_color", Color.WHITE)
		sprite.modulate = color

# Called by the projectile on contact — deals damage to the hit body.
func hitPlayer(body) -> void:
	if multiplayer.is_server():
		body.getDamage(self, attackDamage, "normal")

# Called by the damageable group contract when this enemy is struck.
func getDamage(causer, amount, _type) -> void:
	hp -= amount
	$bloodParticles.emitting = true
	if hp <= 0:
		if causer.is_in_group("player"):
			causer.mob_killed.emit()
		die(true)

# Notifies the spawner, drops loot, and frees the node. Server-only.
func die(drop_loot: bool) -> void:
	if multiplayer.is_server():
		spawner.decreasePlayerEnemyCount(targetPlayerId)
		if drop_loot:
			_drop_loot()
		queue_free()

func _drop_loot() -> void:
	for drop in drops.keys():
		Items.spawnPickups(drop, position, randi_range(drops[drop]["min"], drops[drop]["max"]))
