class_name MissionRun
extends Node

signal changed
signal encounter_requested
signal completed

enum State { IDLE, PREPARING, IN_PROGRESS, COMPLETED, RETURNING }

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

func start(data: MissionData) -> bool:
	if not can_start() or data == null or data.encounter_count < 1:
		return false
	# Reject unsupported encounters instead of silently spawning the wrong enemy.
	if data.enemy_pool != ["slime"] or data.loot_profile != "slime":
		return false
	mission = data
	mission_id = data.id
	total_encounters = data.encounter_count
	current_encounter = 0
	defeated_encounters = 0
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
	if mission_state != State.IN_PROGRESS or encounter_active or defeated_encounters >= total_encounters:
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
	if defeated_encounters == total_encounters:
		mission_state = State.COMPLETED
		summary_pending = true
		changed.emit()
		completed.emit()
	else:
		changed.emit()

func claim_completion_reward(gold: int, xp: int) -> bool:
	if mission_state != State.COMPLETED or completion_reward_claimed:
		return false
	completion_reward_claimed = true
	completion_gold = gold
	completion_xp = xp
	changed.emit()
	return true

func record_loot(item: ItemData) -> void:
	if mission_state not in [State.IN_PROGRESS, State.COMPLETED]:
		return
	collected_loot[item.id] = collected_loot.get(item.id, 0) + 1
	loot_items[item.id] = item
	changed.emit()

func begin_return() -> void:
	if mission_state == State.COMPLETED and completion_reward_claimed:
		mission_state = State.RETURNING
		changed.emit()

func finish_return() -> void:
	if mission_state == State.RETURNING:
		mission_state = State.IDLE
		changed.emit()

func acknowledge_summary() -> bool:
	if mission_state != State.IDLE or not summary_pending:
		return false
	summary_pending = false
	changed.emit()
	return true

func total_gold() -> int:
	return accumulated_gold + completion_gold

func total_xp() -> int:
	return accumulated_xp + completion_xp
