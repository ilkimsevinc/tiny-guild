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


func roll(item_multiplier: float = 1.0, rare_multiplier: float = 1.0) -> ItemData:
	# Preserve the original integer roll (and seeded tests) for normal loot.
	if item_multiplier == 1.0 and rare_multiplier == 1.0:
		return item_for_roll(rng.randi_range(0, 99))
	var weights: Array[float] = mission_weights(item_multiplier, rare_multiplier)
	var total: float = 0.0
	for weight in weights:
		total += weight
	return item_for_weight(rng.randf() * total, weights)

func mission_weights(item_multiplier: float, rare_multiplier: float) -> Array[float]:
	var weights: Array[float] = []
	for index in range(ITEMS.size()):
		var weight: float = CHANCES[index] * maxf(item_multiplier, 0.0)
		if ITEMS[index].is_rare_or_higher():
			weight *= maxf(rare_multiplier, 0.0)
		weights.append(weight)
	weights.append(9.0) # No drop is never multiplied.
	return weights

func item_for_weight(value: float, weights: Array[float]) -> ItemData:
	var threshold: float = 0.0
	for index in range(ITEMS.size()):
		threshold += weights[index]
		if value < threshold:
			return ITEMS[index]
	return null


# Separate selection from randomness so every outcome can be tested exactly.
func item_for_roll(value: int) -> ItemData:
	assert(value >= 0 and value < 100)
	var threshold: int = 0
	for index in range(ITEMS.size()):
		threshold += CHANCES[index]
		if value < threshold:
			return ITEMS[index]
	return null