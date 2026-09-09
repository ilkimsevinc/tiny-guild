class_name SkillNodeData
extends Resource

const EFFECT_LABELS: Dictionary[String, String] = {
	"attack": "ATK",
	"max_hp": "Max HP",
	"attack_speed_percent": "ATK Speed",
	"crit_chance_percent": "Crit Chance",
	"gold_find_percent": "Gold Find",
	"xp_bonus_percent": "XP",
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var class_id: String = ""
@export var branch_id: String = "foundation"
@export_range(1, 20) var tier: int = 1
@export var gold_cost: int = 0
@export var prerequisite_ids: Array[String] = []
@export var effect_type: String = "stat_bonus"
# Several additive effects can belong to one node. Percent values use 10 for 10%.
# A consumer decides how to use a stat; storing Crit Chance does not add crit combat.
@export var effect_value: Dictionary[String, float] = {}
@export var max_rank: int = 1


func effect_description() -> String:
	var lines: Array[String] = []
	for stat_id in effect_value:
		var value: float = effect_value[stat_id]
		var number: String = str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)
		var label: String = EFFECT_LABELS.get(stat_id, stat_id.replace("_", " ").capitalize())
		lines.append("%s%s%s %s" % [
			"+" if value >= 0 else "", number, "%" if stat_id.ends_with("_percent") else "", label
		])
	return " / ".join(lines)