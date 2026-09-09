extends Node2D

signal health_changed(current_hp: int)
signal died

const MAX_HP: int = 30
var hp: int = MAX_HP


func take_damage(amount: int) -> void:
	if hp <= 0:
		return

	hp = maxi(hp - amount, 0)
	health_changed.emit(hp)
	if hp == 0:
		died.emit()
		queue_free()
