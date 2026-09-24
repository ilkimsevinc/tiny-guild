class_name HeroController
extends Node2D

# Reusable playable hero: movement/combat state plus runtime Energy and Guild status.
# Static identity and base stats come from HeroData; progression, equipment and
# class skills are per-hero child nodes.

signal attacked(target: Node2D, damage: int)
signal state_changed(state_name: String)
signal stats_changed
signal orb_launched(origin: Vector2, target: Node2D)

enum State { IDLE, MOVING, ATTACKING }

# Standard melee reach; melee heroes use it unless their HeroData says otherwise.
const MELEE_RANGE: float = 130.0

@export var hero_data: HeroData = preload("res://data/heroes/arthur.tres")
@export var class_id: String = "knight"

# Guild assignment is separate from the movement/combat state.
var guild_status: String = "IDLE_AT_GUILD"
var max_energy: int = 100
var current_energy: int = 100:
	set(value):
		current_energy = clampi(value, 0, max_energy)
		stats_changed.emit()
var state: State = State.IDLE
var target: Node2D
var loot_target: Node2D
var attack_tween: Tween
var previous_hp_bonus: int = 0
# Where the hero stands at the Guild; set by Main from the scene placement.
var home_position: Vector2
# Formation: back-row heroes follow the hero in the slot ahead of them.
var formation_leader: HeroController
var formation_spacing: float = 0.0
# Regroup point between encounters (formation home).
var rally_point: Vector2
var has_rally_point: bool = false

var hero_id: String:
	get:
		return hero_data.hero_id
var display_name: String:
	get:
		return hero_data.display_name
var attack_range: float:
	get:
		return hero_data.attack_range
var move_speed: float:
	get:
		return hero_data.move_speed

@onready var attack_timer: Timer = $AttackTimer
@onready var visuals: Node2D = $Visuals
@onready var progression = $Progression
@onready var equipment: Equipment = $Equipment
@onready var skills: SkillTree = $Skills


func _ready() -> void:
	class_id = hero_data.class_id
	max_energy = hero_data.max_energy
	current_energy = max_energy
	progression.configure(hero_data.base_damage, hero_data.base_max_hp, hero_data.damage_per_level, hero_data.hp_per_level)
	attack_timer.wait_time = hero_data.base_attack_interval
	skills.load_class(class_id)
	skills.changed.connect(_on_bonuses_changed)
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	equipment.changed.connect(_on_bonuses_changed)
	progression.stats_changed.connect(func(): stats_changed.emit())
	progression.leveled_up.connect(_restore_hp_after_level)


func set_target(new_target: Node2D) -> void:
	target = new_target
	if is_instance_valid(new_target):
		has_rally_point = false
	_set_state(State.IDLE)


func set_formation(leader: HeroController, spacing: float) -> void:
	formation_leader = leader
	formation_spacing = spacing


func rally_to(point: Vector2) -> void:
	rally_point = point
	has_rally_point = true


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		# Use the respawn pause to approach loot; combat always has priority.
		if is_instance_valid(loot_target):
			_set_state(State.MOVING)
			_face(loot_target.global_position)
			global_position = global_position.move_toward(loot_target.global_position, move_speed * delta)
		elif has_rally_point and global_position.distance_to(rally_point) > 1.0:
			_set_state(State.MOVING)
			_face(rally_point)
			global_position = global_position.move_toward(rally_point, move_speed * delta)
		else:
			if has_rally_point:
				visuals.scale.x = 1.0 # Regrouped: face the way enemies come from.
			has_rally_point = false
			_set_state(State.IDLE)
		return

	_face(target.global_position)
	if _follows_leader():
		_follow_formation(delta)
		return
	var offset: Vector2 = target.global_position - global_position
	if is_target_in_range():
		_set_state(State.ATTACKING)
	else:
		_set_state(State.MOVING)
		# Stop at the edge of attack range (melee reach or spell range), even on a slow frame.
		var distance_to_walk: float = minf(move_speed * delta, offset.length() - attack_range)
		global_position += offset.normalized() * distance_to_walk


func _face(point: Vector2) -> void:
	if not is_zero_approx(point.x - global_position.x):
		visuals.scale.x = signf(point.x - global_position.x)


func _follows_leader() -> bool:
	return is_instance_valid(formation_leader) and formation_leader.target == target


# Back-row movement: hold a slot formation_spacing behind the leader (on the side
# away from the enemy), never closer than MIN_HERO_SPACING, and cast from there.
func _follow_formation(delta: float) -> void:
	var leader_x: float = formation_leader.global_position.x
	var toward_enemy: float = signf(target.global_position.x - leader_x)
	if is_zero_approx(toward_enemy):
		toward_enemy = 1.0
	var slot_x: float = leader_x - toward_enemy * formation_spacing
	var limit_x: float = leader_x - toward_enemy * PartyFormation.MIN_HERO_SPACING
	var goal_x: float = slot_x
	if absf(global_position.x - slot_x) <= 2.0:
		if is_target_in_range():
			_set_state(State.ATTACKING)
			return
		# Slot is outside spell range (short-ranged back hero): close in, still behind the leader.
		goal_x = limit_x
	if absf(global_position.x - goal_x) <= 0.5:
		_set_state(State.ATTACKING if is_target_in_range() else State.IDLE)
		return
	_set_state(State.MOVING)
	var next_x: float = move_toward(global_position.x, goal_x, move_speed * delta)
	# Never pass the leader, even while the leader is still walking.
	if not _behind_x(next_x, limit_x, toward_enemy):
		next_x = limit_x
	global_position.x = next_x


func _behind_x(x: float, limit_x: float, toward_enemy: float) -> bool:
	return (x - limit_x) * toward_enemy <= 0.01


func is_target_in_range() -> bool:
	return is_instance_valid(target) and global_position.distance_to(target.global_position) <= attack_range + 0.01


func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	if state == State.ATTACKING:
		attack_timer.start()
	else:
		attack_timer.stop()
	state_changed.emit(State.keys()[state])


func _on_attack_timer_timeout() -> void:
	# Recheck range at impact, not just when starting the timer.
	if state != State.ATTACKING or not is_target_in_range():
		return
	# Keep the emitted target stable if a listener clears it on death.
	var attack_target: Node2D = target
	_play_attack_feedback(attack_target)
	attacked.emit(attack_target, total_attack())


func _play_attack_feedback(attack_target: Node2D) -> void:
	if attack_tween:
		attack_tween.kill()
	visuals.position = Vector2.ZERO
	attack_tween = create_tween()
	if hero_data.is_ranged():
		# Casting pulse on the hero plus a short-lived magic orb toward the target.
		visuals.modulate = Color(1.6, 1.2, 1.9)
		attack_tween.tween_property(visuals, "modulate", Color.WHITE, 0.2)
		_launch_orb(attack_target)
		return
	attack_tween.tween_property(visuals, "position:x", 12.0 * visuals.scale.x, 0.08)
	attack_tween.tween_property(visuals, "position:x", 0.0, 0.14)


func _launch_orb(attack_target: Node2D) -> void:
	if get_parent() == null or not is_instance_valid(attack_target):
		return
	var orb := Polygon2D.new()
	var points := PackedVector2Array()
	for i in 10:
		points.append(Vector2.from_angle(TAU * i / 10.0) * 9.0)
	orb.polygon = points
	orb.color = hero_data.damage_color
	get_parent().add_child(orb)
	# Spawned from the caster's current (backline) position, travels to the target.
	orb.global_position = global_position + Vector2(0, -60)
	orb_launched.emit(orb.global_position, attack_target)
	var tween := orb.create_tween()
	tween.tween_property(orb, "global_position", attack_target.global_position + Vector2(0, -40), 0.18)
	tween.tween_callback(orb.queue_free)


func total_attack() -> int:
	return progression.damage + equipment.attack_bonus() + skills.attack_bonus()


func total_max_hp() -> int:
	return progression.max_hp + equipment.max_hp_bonus() + skills.max_hp_bonus()


func _on_bonuses_changed() -> void:
	var hp_bonus: int = equipment.max_hp_bonus() + skills.max_hp_bonus()
	# Positive max-HP changes add current HP; decreases only clamp it.
	progression.current_hp = mini(progression.current_hp + maxi(hp_bonus - previous_hp_bonus, 0), total_max_hp())
	previous_hp_bonus = hp_bonus
	var interval: float = attack_interval()
	if not is_equal_approx(attack_timer.wait_time, interval):
		attack_timer.wait_time = interval
		if state == State.ATTACKING:
			# Begin a fresh interval when attack speed changes.
			attack_timer.start()
	stats_changed.emit()


func _restore_hp_after_level() -> void:
	progression.current_hp = total_max_hp()


func attack_interval() -> float:
	return hero_data.base_attack_interval / (1.0 + skills.attack_speed_percent() / 100.0)

func consume_energy(amount: int) -> void:
	current_energy -= maxi(amount, 0)

func restore_energy() -> void:
	# Debug/test shortcut only; normal play recovers through EnergyRecovery.
	current_energy = max_energy

func expedition_snapshot() -> Dictionary:
	return {"hero_id": hero_id, "current_hp": progression.current_hp, "max_hp": total_max_hp(),
		"current_energy": current_energy, "max_energy": max_energy}

func summary_line() -> String:
	return "%s - %s Lv %d" % [display_name, skills.class_data.display_name if skills.class_data != null else class_id, progression.level]
