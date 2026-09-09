extends Node2D

signal picked_up(item: ItemData)

var item: ItemData
var collected: bool = false


func _ready() -> void:
	$Shape.color = item.rarity_color()
	$NameLabel.text = item.display_name
	$NameLabel.modulate = item.rarity_color()


func collect() -> void:
	if collected:
		return
	collected = true
	picked_up.emit(item)
	queue_free()