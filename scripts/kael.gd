extends Node2D

signal attacked(damage: int)

const ATTACK_DAMAGE: int = 10

@onready var attack_timer: Timer = $AttackTimer


func _ready() -> void:
	attack_timer.timeout.connect(_on_attack_timer_timeout)


func start_attacking() -> void:
	attack_timer.start()


func stop_attacking() -> void:
	attack_timer.stop()


func _on_attack_timer_timeout() -> void:
	attacked.emit(ATTACK_DAMAGE)
