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
@export var attack_bonus: int = 0
@export var max_hp_bonus: int = 0
@export var gold_bonus_percent: int = 0
@export var xp_bonus_percent: int = 0


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

func is_equippable() -> bool:
	return item_type != ItemType.MATERIAL


func bonus_description() -> String:
	var lines: Array[String] = []
	if attack_bonus != 0:
		lines.append("%+d Attack" % attack_bonus)
	if max_hp_bonus != 0:
		lines.append("%+d Max HP" % max_hp_bonus)
	if gold_bonus_percent != 0:
		lines.append("%+d%% Gold rewards" % gold_bonus_percent)
	if xp_bonus_percent != 0:
		lines.append("%+d%% XP rewards" % xp_bonus_percent)
	return "\n".join(lines) if not lines.is_empty() else "No combat bonuses."
