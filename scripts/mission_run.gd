class_name MissionRun
extends Node

signal changed
signal encounter_requested
signal completed
signal retreated

enum State { IDLE, PREPARING, IN_PROGRESS, COMPLETED, RETURNING, RETREATED }
enum Result { NONE, COMPLETED, RETREATED }

@export var stop_config: ExpeditionStopConfig = ExpeditionStopConfig.new()
var result_status: Result = Result.NONE
var stop_reason: StopConditionEvaluator.Reason = StopConditionEvaluator.Reason.NONE
var checkpoint_pending: bool = false
var ending_energy: int = 0
# Party participants for this run. XP is awarded in full to each participant.
var party_hero_ids: Array[String] = []
var party_ending_energy: Dictionary[String, int] = {}
# hero_id -> {"name", "level"} captured when the run ends, for summaries.
var participants: Dictionary = {}
# XP each participant actually received (own equipment modifiers applied).
var hero_xp: Dictionary[String, int] = {}
var completion_reward_eligible: bool:
	get:
		return result_status == Result.COMPLETED and defeated_encounters == total_encounters

var source_instance: MissionInstance
var completion_rng := RandomNumberGenerator.new()
var mission: MissionData
var mission_id: String = ""
var mission_state: State = State.IDLE
var current_encounter: int = 0
var total_encounters: int = 0
var defeated_encounters: int = 0
var encounter_active: bool = false
var accumulated_gold: int = 0
var accumulated_xp: int = 0
var completion_gold: int = 0
var completion_xp: int = 0
var completion_reward_claimed: bool = false
var summary_pending: bool = false
var collected_loot: Dictionary[String, int] = {}
var loot_items: Dictionary[String, ItemData] = {}

func can_start() -> bool:
	return mission_state == State.IDLE and not summary_pending

func start(data: MissionData, instance: MissionInstance = null, hero_ids: Array[String] = []) -> bool:
	if not can_start() or data == null or data.encounter_count < 1:
		return false
	# Reject unsupported encounters instead of silently spawning the wrong enemy.
	if not data.is_valid_definition():
		return false
	source_instance = instance
	if source_instance != null:
		completion_rng.seed = source_instance.seed
	else:
		completion_rng.randomize()
	mission = data
	mission_id = data.id
	total_encounters = data.encounter_count
	current_encounter = 0
	defeated_encounters = 0
	result_status = Result.NONE
	stop_reason = StopConditionEvaluator.Reason.NONE
	checkpoint_pending = false
	ending_energy = 0
	party_hero_ids = hero_ids.duplicate()
	party_ending_energy.clear()
	participants.clear()
	hero_xp.clear()
	accumulated_gold = 0
	accumulated_xp = 0
	completion_gold = 0
	completion_xp = 0
	completion_reward_claimed = false
	collected_loot.clear()
	loot_items.clear()
	mission_state = State.PREPARING
	changed.emit()
	mission_state = State.IN_PROGRESS
	start_next_encounter()
	return true

func start_next_encounter() -> void:
	if mission_state != State.IN_PROGRESS or encounter_active or checkpoint_pending or defeated_encounters >= total_encounters:
		return
	current_encounter = defeated_encounters + 1
	encounter_active = true
	changed.emit()
	encounter_requested.emit()

func record_defeat(gold: int, xp: int) -> void:
	if mission_state != State.IN_PROGRESS or not encounter_active:
		return
	encounter_active = false
	defeated_encounters += 1
	accumulated_gold += gold
	accumulated_xp += xp
	checkpoint_pending = true
	changed.emit()

func resolve_checkpoint(hero_state: Dictionary) -> void:
	resolve_party_checkpoint([hero_state])

# Every hero is evaluated with the shared StopConditionEvaluator; if any member
# breaches a hard stop, the whole party retreats.
func resolve_party_checkpoint(hero_states: Array) -> void:
	if mission_state != State.IN_PROGRESS or not checkpoint_pending or hero_states.is_empty():
		return
	checkpoint_pending = false
	ending_energy = 1 << 30
	for hero_state in hero_states:
		var energy: int = int(hero_state.get("current_energy", 100))
		ending_energy = mini(ending_energy, energy)
		if hero_state.has("hero_id"):
			party_ending_energy[hero_state.hero_id] = energy
	var hero_state: Dictionary = hero_states[0]
	for candidate in hero_states:
		var probe: Dictionary = candidate.duplicate()
		probe["carried_units"] = carried_units()
		probe["encounters_completed"] = defeated_encounters
		if StopConditionEvaluator.evaluate(probe, stop_config).should_stop:
			hero_state = candidate
			break
	# Completing all encounters takes precedence over a stop condition.
	if defeated_encounters == total_encounters:
		mission_state = State.COMPLETED
		result_status = Result.COMPLETED
		summary_pending = true
		changed.emit()
		completed.emit()
		return
	var snapshot: Dictionary = hero_state.duplicate()
	snapshot["carried_units"] = carried_units()
	snapshot["encounters_completed"] = defeated_encounters
	var decision: Dictionary = StopConditionEvaluator.evaluate(snapshot, stop_config)
	if decision.should_stop:
		mission_state = State.RETREATED
		result_status = Result.RETREATED
		stop_reason = decision.reason
		summary_pending = true
		changed.emit()
		retreated.emit()
	else:
		changed.emit()

func carried_units() -> int:
	var total: int = 0
	for quantity in collected_loot.values():
		total += quantity
	return total

func claim_completion_reward(gold: int, xp: int) -> bool:
	if mission_state != State.COMPLETED or not completion_reward_eligible or completion_reward_claimed:
		return false
	completion_reward_claimed = true
	completion_gold = gold
	completion_xp = xp
	changed.emit()
	return true

func record_loot(item: ItemData) -> void:
	if mission_state not in [State.IN_PROGRESS, State.COMPLETED, State.RETREATED]:
		return
	collected_loot[item.id] = collected_loot.get(item.id, 0) + 1
	loot_items[item.id] = item
	changed.emit()

func begin_return() -> void:
	if (mission_state == State.COMPLETED and completion_reward_claimed) or mission_state == State.RETREATED:
		mission_state = State.RETURNING
		changed.emit()

func finish_return() -> void:
	if mission_state == State.RETURNING:
		if source_instance != null:
			source_instance.active = false
		mission_state = State.IDLE
		changed.emit()

func acknowledge_summary() -> bool:
	if mission_state != State.IDLE or not summary_pending:
		return false
	summary_pending = false
	changed.emit()
	return true

func award_hero_xp(hero_id: String, amount: int) -> void:
	hero_xp[hero_id] = hero_xp.get(hero_id, 0) + amount

func record_participants(heroes: Array) -> void:
	participants.clear()
	for member in heroes:
		participants[member.hero_id] = {"name": member.display_name, "level": member.progression.level}

func total_gold() -> int:
	return accumulated_gold + completion_gold

func total_xp() -> int:
	return accumulated_xp + completion_xp

func loot_modifier(key: String) -> float:
	if source_instance != null:
		return source_instance.mission_modifiers.get(key, mission.get(key))
	return mission.get(key)