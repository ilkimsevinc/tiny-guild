class_name Equipment
extends Node

signal changed

enum Slot { WEAPON, ARMOR, ACCESSORY, RELIC }
const SLOT_NAMES: Array[String] = ["Weapon", "Armor", "Accessory", "Relic"]

var _slots: Dictionary[int, ItemData] = {}


func get_item(slot: int) -> ItemData:
	return _slots.get(slot)


func can_equip(item: ItemData, slot: int) -> bool:
	return item != null and item.is_equippable() and slot == item.item_type - 1


func equip(inventory: Inventory, item_id: String, slot: int = -1) -> bool:
	var item: ItemData = inventory.get_item(item_id)
	if item == null:
		return false
	if slot == -1:
		slot = item.item_type - 1
	if not can_equip(item, slot):
		return false
	var previous: ItemData = get_item(slot)
	if not inventory.remove_item(item_id):
		return false
	_slots[slot] = item
	if previous != null:
		inventory.add_item(previous)
	changed.emit()
	return true


func unequip(inventory: Inventory, slot: int) -> bool:
	var item: ItemData = get_item(slot)
	if item == null:
		return false
	_slots.erase(slot)
	inventory.add_item(item)
	changed.emit()
	return true


func attack_bonus() -> int:
	var total: int = 0
	for item in _slots.values():
		total += item.attack_bonus
	return total


func max_hp_bonus() -> int:
	var total: int = 0
	for item in _slots.values():
		total += item.max_hp_bonus
	return total


func gold_bonus_percent() -> int:
	var total: int = 0
	for item in _slots.values():
		total += item.gold_bonus_percent
	return total


func xp_bonus_percent() -> int:
	var total: int = 0
	for item in _slots.values():
		total += item.xp_bonus_percent
	return total


# Round positive rewards to the nearest integer, with halves rounded up.
func gold_reward(base_reward: int) -> int:
	return RewardCalculator.calculate(base_reward, gold_bonus_percent())


func xp_reward(base_reward: int) -> int:
	return RewardCalculator.calculate(base_reward, xp_bonus_percent())