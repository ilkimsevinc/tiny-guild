class_name TargetingController
extends Node

# Single authority for encounter targets. Heroes never search for enemies
# themselves; they read active_target (or target_for) from here.
# Today every encounter has one enemy; the enemy list and policies are ready
# for multi-enemy encounters later.

signal active_target_changed(target: Node2D)

enum Policy { FIRST_REGISTERED, NEAREST, LOWEST_HP, BOSS_PRIORITY, MARKED }

var policy: Policy = Policy.FIRST_REGISTERED
var enemies: Array[Node2D] = []
var active_target: Node2D
# Future player-marked target.
var marked_target: Node2D
# Position used by NEAREST (e.g. the party's front anchor).
var reference_position: Vector2 = Vector2.ZERO

func register_enemy(enemy: Node2D) -> void:
	if enemy in enemies:
		return
	enemies.append(enemy)
	select_target()

# Removes a dead enemy exactly once. Returns false for an unknown/already-released
# enemy, which lets callers reject duplicate death processing.
func release_enemy(enemy: Node2D) -> bool:
	if enemy == null or not enemy in enemies:
		return false
	enemies.erase(enemy)
	if marked_target == enemy:
		marked_target = null
	select_target()
	return true

func clear() -> void:
	enemies.clear()
	marked_target = null
	_set_active(null)

func select_target() -> Node2D:
	for index in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[index]):
			enemies.remove_at(index)
	var chosen: Node2D = null
	if not enemies.is_empty():
		match policy:
			Policy.MARKED:
				chosen = marked_target if marked_target in enemies else enemies[0]
			Policy.NEAREST:
				chosen = enemies[0]
				for enemy in enemies:
					if enemy.global_position.distance_to(reference_position) < chosen.global_position.distance_to(reference_position):
						chosen = enemy
			Policy.LOWEST_HP:
				chosen = enemies[0]
				for enemy in enemies:
					if enemy.hp < chosen.hp:
						chosen = enemy
			Policy.BOSS_PRIORITY:
				chosen = enemies[0]
				for enemy in enemies:
					if enemy.enemy_data.enemy_type == "BOSS":
						chosen = enemy
						break
			_:
				chosen = enemies[0]
	_set_active(chosen)
	return chosen

# Role-aware targeting hook; all roles share the active target for now.
func target_for(_hero: HeroController) -> Node2D:
	return active_target

func _set_active(target: Node2D) -> void:
	if active_target == target:
		return
	active_target = target
	active_target_changed.emit(target)
