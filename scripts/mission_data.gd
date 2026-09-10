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
@export var material_weight_multiplier: float = 1.0
@export var special_type: String = "BASE"
@export var requires_manual_attention: bool = false
@export var repeated_enemy: EnemyData = preload("res://data/enemies/slime.tres")
@export var encounters: Array[EncounterData] = []
@export var completion_loot: CompletionLootTable

func enemy_for_encounter(number: int) -> EnemyData:
	return encounters[number - 1].enemy if not encounters.is_empty() else repeated_enemy

func energy_for_encounter(number: int) -> int:
	return encounters[number - 1].energy_cost if not encounters.is_empty() else energy_cost_per_encounter

func total_energy_cost() -> int:
	var total: int = 0
	for number in range(1, encounter_count + 1):
		total += energy_for_encounter(number)
	return total

func energy_description() -> String:
	if encounters.is_empty():
		return "%d each / %d total" % [energy_cost_per_encounter, total_energy_cost()]
	var values: Array[String] = []
	for encounter in encounters:
		values.append(str(encounter.energy_cost))
	return "%s / %d total" % [" + ".join(values), total_energy_cost()]

func is_valid_definition() -> bool:
	if encounter_count < 1 or loot_profile != "slime":
		return false
	if not encounters.is_empty() and encounters.size() != encounter_count:
		return false
	if encounters.is_empty() and (repeated_enemy == null or enemy_pool != [repeated_enemy.id]):
		return false
	for number in range(1, encounter_count + 1):
		var enemy: EnemyData = enemy_for_encounter(number)
		if enemy == null or enemy.max_hp <= 0 or energy_for_encounter(number) < 0 or enemy.loot_profile not in ["slime", "none"]:
			return false
	return true

func loot_description() -> String:
	return "%s\nItem weights x%.2f; Rare+ weights x%.2f; Materials x%.2f" % [
		loot_identity, item_weight_multiplier, rare_weight_multiplier, material_weight_multiplier]
