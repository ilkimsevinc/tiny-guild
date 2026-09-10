class_name CompletionLootTable
extends Resource

@export var items: Array[ItemData] = []
@export var chances_percent: Array[int] = []

func wins(index: int, roll_value: int) -> bool:
	return index >= 0 and index < chances_percent.size() and roll_value >= 0 and roll_value < chances_percent[index]

func roll(rng: RandomNumberGenerator) -> Array[ItemData]:
	var drops: Array[ItemData] = []
	for index in range(items.size()):
		if wins(index, rng.randi_range(0, 99)):
			drops.append(items[index])
	return drops
