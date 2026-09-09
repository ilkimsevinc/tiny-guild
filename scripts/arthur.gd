extends Node2D

signal attacked(target: Node2D, damage: int)
signal state_changed(state_name: String)

enum State { IDLE, MOVING, ATTACKING }

const MOVE_SPEED: float = 180.0
const MELEE_RANGE: float = 130.0

var state: State = State.IDLE
var target: Node2D
var loot_target: Node2D
var attack_tween: Tween

@onready var attack_timer: Timer = $AttackTimer
@onready var visuals: Node2D = $Visuals
@onready var progression = $Progression


func _ready() -> void:
	attack_timer.timeout.connect(_on_attack_timer_timeout)


func set_target(new_target: Node2D) -> void:
	target = new_target
	_set_state(State.IDLE)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(target):
		# Use the respawn pause to approach loot; combat always has priority.
		if is_instance_valid(loot_target):
			_set_state(State.MOVING)
			var loot_offset: Vector2 = loot_target.global_position - global_position
			if not is_zero_approx(loot_offset.x):
				visuals.scale.x = signf(loot_offset.x)
			global_position = global_position.move_toward(loot_target.global_position, MOVE_SPEED * delta)
		else:
			_set_state(State.IDLE)
		return

	var offset: Vector2 = target.global_position - global_position
	if not is_zero_approx(offset.x):
		visuals.scale.x = signf(offset.x)

	if is_target_in_range():
		_set_state(State.ATTACKING)
	else:
		_set_state(State.MOVING)
		# Stop at the edge of melee range, even on a slow frame.
		var distance_to_walk: float = minf(MOVE_SPEED * delta, offset.length() - MELEE_RANGE)
		global_position += offset.normalized() * distance_to_walk


func is_target_in_range() -> bool:
	return is_instance_valid(target) and global_position.distance_to(target.global_position) <= MELEE_RANGE + 0.01


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
	_play_attack_feedback()
	# Keep the emitted target stable if a listener clears it on death.
	var attack_target: Node2D = target
	var attack_damage: int = progression.damage
	attacked.emit(attack_target, attack_damage)


func _play_attack_feedback() -> void:
	if attack_tween:
		attack_tween.kill()
	visuals.position = Vector2.ZERO
	attack_tween = create_tween()
	attack_tween.tween_property(visuals, "position:x", 12.0 * visuals.scale.x, 0.08)
	attack_tween.tween_property(visuals, "position:x", 0.0, 0.14)