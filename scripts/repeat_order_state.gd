class_name RepeatOrderState
extends Node

signal changed

const MASTERY_ID: String = "repeat_orders"

var mastery: GuildMasteryState
var repeat_enabled: bool = false
var mission_id: String = ""
var repeat_run_count: int = 0
var stop_reason: String = ""
var pending_restart: bool = false

var repeat_unlocked: bool:
	get:
		return mastery != null and mastery.owns(MASTERY_ID)

func setup(mastery_state: GuildMasteryState) -> void:
	mastery = mastery_state
	if not mastery.changed.is_connected(_on_mastery_changed):
		mastery.changed.connect(_on_mastery_changed)
	changed.emit()

func is_mission_eligible(mission: MissionData) -> bool:
	return mission != null and mission.repeatable and mission.special_type == "BASE"

func availability_reason(mission: MissionData) -> String:
	if not repeat_unlocked:
		return "Unlock Repeat Orders in Guild Mastery"
	if not is_mission_eligible(mission):
		return "Special missions cannot be repeated"
	return ""

func select_mission(mission: MissionData) -> void:
	if mission == null:
		return
	if (not mission_id.is_empty() and mission.id != mission_id) or (mission_id.is_empty() and not stop_reason.is_empty()):
		reset()

func set_enabled(mission: MissionData, enabled: bool) -> bool:
	if enabled:
		if not availability_reason(mission).is_empty():
			return false
		repeat_enabled = true
		mission_id = mission.id
		repeat_run_count = 0
		stop_reason = ""
		pending_restart = false
	else:
		stop("Stopped by player")
		return true
	changed.emit()
	return true

func record_dispatch(mission: MissionData, automatic: bool = false) -> bool:
	if mission == null or not repeat_enabled or mission.id != mission_id:
		return false
	if automatic and not pending_restart:
		return false
	pending_restart = false
	repeat_run_count += 1
	changed.emit()
	return true

func record_success(mission: MissionData) -> bool:
	if mission == null or not repeat_enabled or mission.id != mission_id or not is_mission_eligible(mission):
		return false
	pending_restart = true
	changed.emit()
	return true

func stop(reason: String) -> void:
	repeat_enabled = false
	pending_restart = false
	mission_id = ""
	repeat_run_count = 0
	stop_reason = reason
	changed.emit()

func stop_for_result(result_name: String, reason: String = "") -> void:
	var detail: String = reason if not reason.is_empty() else result_name.replace("_", " ").capitalize()
	stop("Repeat Orders stopped: " + detail)

func reset() -> void:
	repeat_enabled = false
	mission_id = ""
	repeat_run_count = 0
	stop_reason = ""
	pending_restart = false
	changed.emit()

func snapshot() -> Dictionary:
	return {"repeat_unlocked": repeat_unlocked, "repeat_enabled": repeat_enabled,
		"mission_id": mission_id, "repeat_run_count": repeat_run_count,
		"stop_reason": stop_reason, "pending_restart": pending_restart}

func _on_mastery_changed() -> void:
	if not repeat_unlocked and repeat_enabled:
		reset()
	else:
		changed.emit()