extends Node

signal stats_changed
signal leveled_up

var level: int = 1
var xp: int = 0
var xp_required: int = 30
var damage: int = 10
var max_hp: int = 100
var current_hp: int = 100


func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	xp += amount
	# Carry leftover XP forward, including rewards large enough for several levels.
	while xp >= xp_required:
		xp -= xp_required
		level += 1
		damage += 2
		max_hp += 10
		current_hp = max_hp
		# Requirements: 30, 45, 65, 90... (each increase grows by 5).
		xp_required += 5 * (level + 1)
		leveled_up.emit()
	stats_changed.emit()