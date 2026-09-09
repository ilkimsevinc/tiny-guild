extends RefCounted

# One integer roll out of 100: 91 item outcomes and 9 empty outcomes.
const ITEMS: Array[ItemData] = [
	preload("res://data/items/slime_gel.tres"),
	preload("res://data/items/rusty_sword.tres"),
	preload("res://data/items/old_shield.tres"),
	preload("res://data/items/slime_ring.tres"),
	preload("res://data/items/slime_crown.tres"),
]
const CHANCES: Array[int] = [50, 20, 15, 5, 1]

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	rng.randomize()


func roll() -> ItemData:
	return item_for_roll(rng.randi_range(0, 99))


# Separate selection from randomness so every outcome can be tested exactly.
func item_for_roll(value: int) -> ItemData:
	assert(value >= 0 and value < 100)
	var threshold: int = 0
	for index in range(ITEMS.size()):
		threshold += CHANCES[index]
		if value < threshold:
			return ITEMS[index]
	return null