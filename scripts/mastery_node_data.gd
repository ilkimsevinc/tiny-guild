class_name MasteryNodeData
extends Resource

const EFFECT_LABELS: Dictionary[String, String] = {
	"global_gold_percent": "Global Gold",
	"global_xp_percent": "Global XP",
	"travel_speed_percent": "Travel Speed",
	"rotating_mission_slots": "Rotating Mission Slot",
	"offline_hours": "Offline Hour",
	"offline_efficiency_percent": "Offline Efficiency",
}

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var branch_id: String = ""
@export var tier: int = 1
@export var gold_cost: int = 0
@export var guild_token_cost: int = 0
@export var prerequisite_ids: Array[String] = []
@export var effect_value: Dictionary[String, float] = {}
@export var max_rank: int = 1
@export var implemented: bool = false
@export var unlock_tags: Array[String] = []


func effect_description() -> String:
	var lines: Array[String] = []
	for stat_id in effect_value:
		var value: float = effect_value[stat_id]
		var number: String = str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)
		lines.append("+%s%s %s" % [number, "%" if stat_id.ends_with("_percent") else "",
			EFFECT_LABELS.get(stat_id, stat_id.replace("_", " ").capitalize())])
	for tag in unlock_tags:
		lines.append("Unlock: " + tag.replace("_", " ").capitalize())
	return "\n".join(lines)