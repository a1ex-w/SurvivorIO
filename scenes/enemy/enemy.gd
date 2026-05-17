extends CharacterBody2D

const TORCH_REPEL_RADIUS := 220.0

var spawner : Node2D
var targetPlayer : CharacterBody2D
@export var targetPlayerId : int:
	set(value):
		targetPlayerId = value
		targetPlayer = get_node("../../Players/"+str(value))

#stats
@export var enemyId := "":
	set(value):
		enemyId = value
		var enemyData = Items.mobs[value]
		%Sprite2D.texture = load("res://assets/characters/enemy/"+value+".png")
		for stat in enemyData.keys():
			set(stat, enemyData[stat])

var maxhp := 100.0:
	set(value):
		maxhp = value
		hp = value
var hp := maxhp:
	set(value):
		hp = value
		$EnemyUI/HPBar.value = hp/maxhp
var speed := 2000.0
var attack := ""
var attackRange := 50.0
var attackDamage := 20.0
var drops := {}

func _process(_delta):
	if !multiplayer.is_server():
		return
	if is_instance_valid(targetPlayer):
		rotateToTarget()
		var repulsion := _get_torch_repulsion()
		if repulsion != Vector2.ZERO:
			velocity = repulsion * speed
			move_and_slide()
		elif position.distance_to(targetPlayer.position) > attackRange:
			move_towards_position()
		else:
			tryAttack()
	else:
		die(false)

func _get_torch_repulsion() -> Vector2:
	for torch in get_tree().get_nodes_in_group("torch_light"):
		if position.distance_to(torch.global_position) < TORCH_REPEL_RADIUS:
			return (position - torch.global_position).normalized()
	return Vector2.ZERO

func rotateToTarget():
	$MovingParts.look_at(targetPlayer.position)

const TORCH_REPEL_RADIUS = 200.0

func move_towards_position():
	var direction = (targetPlayer.position - position).normalized()
	velocity = direction * speed

	# Repel away from placed torches
	for torch in get_tree().get_nodes_in_group("coal_repeller"):
		if not is_instance_valid(torch): continue
		var dist: float = position.distance_to((torch as Node2D).position)
		if dist < TORCH_REPEL_RADIUS and dist > 0:
			var repel: Vector2 = (position - (torch as Node2D).position).normalized()
			# Square root curve: force kicks in strongly across most of the radius
			var t := sqrt(1.0 - dist / TORCH_REPEL_RADIUS)
			velocity += repel * speed * 4.0 * t

	move_and_slide()

func tryAttack():
	if multiplayer.is_server() and $AttackCooldown.is_stopped():
		$AttackCooldown.start()
		var projectileScene := load("res://scenes/attacks/"+attack+".tscn")
		var projectile = projectileScene.instantiate()
		spawner.get_node("Projectiles").add_child(projectile,true)
		projectile.position = position
		projectile.get_node("MovingParts").rotation = $MovingParts.rotation
		projectile.hitPlayer.connect(hitPlayer)
		projectile.targetPos = targetPlayer.position
		
func hitPlayer(body):
	if multiplayer.is_server():
		body.getDamage(self, attackDamage, "normal")
	
func getDamage(causer, amount, _type):
	hp -= amount
	$bloodParticles.emitting = true
	if hp <= 0:
		if causer.is_in_group("player"):
			causer.mob_killed.emit()
		die(true)

func die(dropLoot):
	if multiplayer.is_server():
		spawner.decreasePlayerEnemyCount(targetPlayerId)
		queue_free()
		if dropLoot:
			dropLoots()

func dropLoots():
	for drop in drops.keys():
		Items.spawnPickups(drop, position, randi_range(drops[drop]["min"],drops[drop]["max"]))
