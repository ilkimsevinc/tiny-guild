class_name ItemData
extends Resource

enum ItemType { MATERIAL, WEAPON, ARMOR, ACCESSORY, RELIC }
enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHIC }

@export var id: String = ""
@export var display_name: String = ""
@export var item_type: ItemType = ItemType.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export var base_value: int = 0
@export_multiline var description: String = ""


func rarity_name() -> String:
	return Rarity.keys()[rarity]


func rarity_color() -> Color:
	match rarity:
		Rarity.UNCOMMON: return Color("#70d879")
		Rarity.RARE: return Color("#69b5ff")
		Rarity.EPIC: return Color("#c58aff")
		Rarity.LEGENDARY: return Color("#ffb34d")
		Rarity.MYTHIC: return Color("#ff5fae")
		_: return Color("#dddddd")


func is_rare_or_higher() -> bool:
	return rarity >= Rarity.RARE