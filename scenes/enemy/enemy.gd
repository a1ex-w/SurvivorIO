extends CharacterBody2D

# Server-authoritative enemy AI driven by a three-state machine.
# Stats are loaded from Items.mobs by enemyId — adding a new mob type
# requires only a new entry in Items.mobs, no code changes here.
#
# States:
#   IDLE   — wanders randomly at half speed; transitions to CHASE when targetPlayer is set
#   CHASE  — moves toward targetPlayer; transitions to ATTACK when in attackRange
#   ATTACK — attacks targetPlayer; transitions to CHASE if target moves out of range
#
# Multiplayer: all logic runs server-only. Position is synced to clients via
# MultiplayerSynchronizer. Animations are driven by position changes on clients.

enum State { IDLE, CHASE, ATTACK }
var state := State.IDLE

var spawner: Node2D

# targetPlayerId is set by the spawner at spawn time for enemy-count tracking.
# It is also used to initialise targetPlayer. Do not change after spawn —
# use the state machine target instead.
var targetPlayer: CharacterBody2D
@export var targetPlayerId: int:
	set(value):
		targetPlayerId = value
		targetPlayer = get_node_or_null("../../Players/" + str(value))
		if is_instance_valid(targetPlayer):
			state = State.CHASE

# Stats — set automatically from Items.mobs[enemyId] via the enemyId setter.
@export var enemyId := "":
	set(value):
		enemyId = value
		var data = Items.mobs[value]
		%Sprite2D.texture = load("res://assets/characters/enemy/" + value + ".png")
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

# Distance at which the enemy notices and picks a new wander destination.
const WANDER_ARRIVAL_DIST := 48.0
var _wander_target := Vector2.ZERO

func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	match state:
		State.IDLE:   _tick_idle()
		State.CHASE:  _tick_chase()
		State.ATTACK: _tick_attack()

# Wanders to random walkable tiles until a target player is assigned.
func _tick_idle() -> void:
	if is_instance_valid(targetPlayer):
		state = State.CHASE
		return
	if _wander_target == Vector2.ZERO or position.distance_to(_wander_target) < WANDER_ARRIVAL_DIST:
		_pick_wander_target()
	if _wander_target != Vector2.ZERO:
		var dir := (_wander_target - position).normalized()
		velocity = dir * speed * 0.5
		$MovingParts.look_at(_wander_target)
		move_and_slide()

# Picks a random reachable tile as the next wander destination.
func _pick_wander_target() -> void:
	if Multihelper.map and not Multihelper.map.walkable_tiles.is_empty():
		_wander_target = Multihelper.map.tile_map.map_to_local(
			Multihelper.map.walkable_tiles.pick_random()
		)

# Chases target player. Transitions to ATTACK when close enough, IDLE if target lost.
func _tick_chase() -> void:
	if not is_instance_valid(targetPlayer):
		state = State.IDLE
		_wander_target = Vector2.ZERO
		return
	rotateToTarget()
	if position.distance_to(targetPlayer.position) <= attackRange:
		state = State.ATTACK
	else:
		_move_toward_target()

# Attacks target player. Transitions to CHASE if target moves out of range.
func _tick_attack() -> void:
	if not is_instance_valid(targetPlayer):
		state = State.IDLE
		_wander_target = Vector2.ZERO
		return
	rotateToTarget()
	if position.distance_to(targetPlayer.position) > attackRange:
		state = State.CHASE
	else:
		_try_attack()

func rotateToTarget() -> void:
	$MovingParts.look_at(targetPlayer.position)

# Moves toward targetPlayer with torch repulsion applied.
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

# Fires the enemy's attack from the attacks/ scene library if the cooldown has elapsed.
func _try_attack() -> void:
	if not $AttackCooldown.is_stopped():
		return
	$AttackCooldown.start()
	var projectileScene := load("res://scenes/attacks/" + attack + ".tscn")
	var projectile = projectileScene.instantiate()
	spawner.get_node("Projectiles").add_child(projectile, true)
	projectile.position = position
	projectile.get_node("MovingParts").rotation = $MovingParts.rotation
	projectile.hitPlayer.connect(hitPlayer)
	projectile.targetPos = targetPlayer.position

func hitPlayer(body) -> void:
	if multiplayer.is_server():
		body.getDamage(self, attackDamage, "normal")

func getDamage(causer, amount, _type) -> void:
	hp -= amount
	$bloodParticles.emitting = true
	if hp <= 0:
		if causer.is_in_group("player"):
			causer.mob_killed.emit()
		die(true)

func die(drop_loot: bool) -> void:
	if multiplayer.is_server():
		spawner.decreasePlayerEnemyCount(targetPlayerId)
		if drop_loot:
			_drop_loot()
		queue_free()

func _drop_loot() -> void:
	for drop in drops.keys():
		Items.spawnPickups(drop, position, randi_range(drops[drop]["min"], drops[drop]["max"]))
