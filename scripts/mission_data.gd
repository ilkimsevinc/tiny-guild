class_name MissionData
extends Resource

# Strings leave room for future mission types without implementing them now.
@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var region_id: String = "whispering_forest"
@export var mission_type: String = "patrol"
@export var difficulty: String = "EASY"
@export var recommended_level: int = 1
@export var encounter_count: int = 3
@export var energy_cost_per_encounter: int = 0
@export var base_gold_reward: int = 0
@export var base_xp_reward: int = 0
@export var loot_profile: String = "slime"
@export var loot_identity: String = "Balanced / Common"
@export var enemy_pool: Array[String] = ["slime"]
@export var estimated_duration_text: String = "Short"
@export var tags: Array[String] = []
# Relative weights; the no-drop weight always remains 9.
@export var item_weight_multiplier: float = 1.0
@export var rare_weight_multiplier: float = 1.0

func loot_description() -> String:
	return "%s\nItem weights x%.2f; Rare+ weights x%.2f" % [
		loot_identity, item_weight_multiplier, rare_weight_multiplier]
