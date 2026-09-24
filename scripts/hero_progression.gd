extends Node

# Per-hero level / XP / HP. Defaults match Arthur; other heroes call configure().

signal stats_changed
signal leveled_up

var level: int = 1
var xp: int = 0
var xp_required: int = 30
var damage: int = 10
var max_hp: int = 100
var current_hp: int = 100
var damage_per_level: int = 2
var hp_per_level: int = 10


func configure(base_damage: int, base_max_hp: int, damage_growth: int, hp_growth: int) -> void:
	damage = base_damage
	max_hp = base_max_hp
	current_hp = base_max_hp
	damage_per_level = damage_growth
	hp_per_level = hp_growth
	stats_changed.emit()


func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	xp += amount
	# Carry leftover XP forward, including rewards large enough for several levels.
	while xp >= xp_required:
		xp -= xp_required
		level += 1
		damage += damage_per_level
		max_hp += hp_per_level
		current_hp = max_hp
		# Requirements: 30, 45, 65, 90... (each increase grows by 5).
		xp_required += 5 * (level + 1)
		leveled_up.emit()
	stats_changed.emit()
