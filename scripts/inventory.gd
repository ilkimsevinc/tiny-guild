class_name Inventory
extends Node

signal changed

var _items: Dictionary[String, ItemData] = {}
var _quantities: Dictionary[String, int] = {}


func add_item(item: ItemData, amount: int = 1) -> bool:
	if item == null or item.id.is_empty() or amount <= 0:
		return false
	_items[item.id] = item
	_quantities[item.id] = quantity(item.id) + amount
	changed.emit()
	return true


func remove_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0 or quantity(item_id) < amount:
		return false
	_quantities[item_id] -= amount
	if _quantities[item_id] == 0:
		_quantities.erase(item_id)
		_items.erase(item_id)
	changed.emit()
	return true


func quantity(item_id: String) -> int:
	return _quantities.get(item_id, 0)


func get_item(item_id: String) -> ItemData:
	return _items.get(item_id)


func get_items() -> Array[ItemData]:
	return _items.values()