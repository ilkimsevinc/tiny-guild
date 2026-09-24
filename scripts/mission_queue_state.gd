class_name MissionQueueState
extends Node

# Expedition Orders: runs player-chosen persistent missions in order.
# Never scores or picks missions itself; main.gd performs the dispatches.

signal changed

enum Outcome { NEXT, FINISHED, PAUSED, STOPPED }

const MASTERY_ID: String = "mission_queue"
const BASE_CAPACITY: int = 3

var mastery: GuildMasteryState
# Future capacity mastery hook.
var capacity_bonus: int = 0
var entries: Array[MissionQueueEntry] = []
# Session state. enabled covers both running and paused sessions.
var enabled: bool = false
var current_index: int = 0
var paused: bool = false
var pause_reason: String = ""
var stop_reason: String = ""
var session_run_count: int = 0
var summary: QueueSessionSummary = QueueSessionSummary.new()
# True between a queue dispatch and its recorded result, so one-off missions never count.
var awaiting_result: bool = false
var stop_requested: bool = false
# Future Boss Portal hook: finish the current mission, then pause for the player.
var pause_after_current_requested: bool = false
var finished: bool = false
# Party chosen at START QUEUE; used for every entry (no per-entry parties yet).
var party_hero_ids: Array[String] = []
# Formation slots fixed for the whole queue session.
var formation_slots: Array[String] = []

var unlocked: bool:
	get:
		return mastery != null and mastery.owns(MASTERY_ID)

var running: bool:
	get:
		return enabled and not paused

var active_entry: MissionQueueEntry:
	get:
		return entries[current_index] if enabled and current_index < entries.size() else null

var completed_entries: int:
	get:
		return entries.filter(func(e): return e.entry_status == MissionQueueEntry.Status.COMPLETED).size()

func setup(mastery_state: GuildMasteryState) -> void:
	mastery = mastery_state
	if not mastery.changed.is_connected(_emit_changed):
		mastery.changed.connect(_emit_changed)
	changed.emit()

func capacity() -> int:
	return BASE_CAPACITY + capacity_bonus

func is_mission_eligible(mission: MissionData) -> bool:
	# Persistent BASE missions only; rotating/Elite/Boss/Anomaly stay manual.
	return mission != null and mission.special_type == "BASE" and mission.is_valid_definition()

func add_reason(mission: MissionData) -> String:
	if not unlocked:
		return "Unlock Mission Queue in Guild Mastery"
	if not is_mission_eligible(mission):
		return "Special missions cannot be queued"
	if entries.size() >= capacity():
		return "Expedition Orders are full (%d / %d)" % [entries.size(), capacity()]
	return ""

func add(mission: MissionData) -> bool:
	if not add_reason(mission).is_empty():
		return false
	entries.append(MissionQueueEntry.create(mission))
	changed.emit()
	return true

# While a session is active only future PENDING entries may change.
func can_edit(index: int) -> bool:
	if index < 0 or index >= entries.size():
		return false
	if not enabled:
		return true
	return index > current_index and entries[index].entry_status == MissionQueueEntry.Status.PENDING

func remove(index: int) -> bool:
	if not can_edit(index):
		return false
	entries.remove_at(index)
	changed.emit()
	return true

func move(index: int, offset: int) -> bool:
	var target: int = index + offset
	if not can_edit(index) or not can_edit(target):
		return false
	var entry: MissionQueueEntry = entries[index]
	entries[index] = entries[target]
	entries[target] = entry
	changed.emit()
	return true

func clear() -> bool:
	if enabled:
		return false
	entries.clear()
	finished = false
	changed.emit()
	return true

func can_start() -> bool:
	return unlocked and not enabled and not entries.is_empty()

func start(hero_ids: Array[String] = [], slots: Array[String] = []) -> MissionData:
	if not can_start():
		return null
	party_hero_ids = hero_ids.duplicate()
	formation_slots = slots.duplicate()
	for entry in entries:
		entry.reset()
	enabled = true
	finished = false
	paused = false
	pause_reason = ""
	stop_reason = ""
	stop_requested = false
	pause_after_current_requested = false
	awaiting_result = false
	current_index = 0
	session_run_count = 0
	summary = QueueSessionSummary.new()
	entries[0].entry_status = MissionQueueEntry.Status.ACTIVE
	changed.emit()
	return entries[0].mission

func next_mission() -> MissionData:
	return active_entry.mission if active_entry != null else null

func record_dispatch(mission: MissionData) -> bool:
	if not running or active_entry == null or mission != active_entry.mission:
		return false
	active_entry.entry_status = MissionQueueEntry.Status.ACTIVE
	awaiting_result = true
	session_run_count += 1
	changed.emit()
	return true

func record_result(run: MissionRun, party_name: String = "Arthur") -> Outcome:
	awaiting_result = false
	summary.record_run(run)
	var entry: MissionQueueEntry = active_entry
	if run.result_status != MissionRun.Result.COMPLETED:
		# RETREATED now; future FAILED/HERO_DOWNED follow the same path.
		entry.entry_status = MissionQueueEntry.Status.BLOCKED
		var result_name: String = MissionRun.Result.keys()[run.result_status].capitalize()
		var reason: String = "%s retreated from %s due to %s." % [party_name, entry.display_name, StopConditionEvaluator.reason_text(run.stop_reason)] \
			if run.result_status == MissionRun.Result.RETREATED else "%s ended as %s." % [entry.display_name, result_name]
		if stop_requested:
			stop(reason)
			return Outcome.STOPPED
		pause(reason)
		return Outcome.PAUSED
	entry.completed_count += 1
	if entry.is_done():
		entry.entry_status = MissionQueueEntry.Status.COMPLETED
		current_index += 1
	if current_index >= entries.size():
		enabled = false
		finished = true
		changed.emit()
		return Outcome.FINISHED
	if stop_requested:
		stop("Expedition Orders stopped by player.")
		return Outcome.STOPPED
	active_entry.entry_status = MissionQueueEntry.Status.ACTIVE
	if pause_after_current_requested:
		pause("Paused after the current mission.")
		return Outcome.PAUSED
	changed.emit()
	return Outcome.NEXT

func pause(reason: String) -> void:
	if not enabled:
		return
	paused = true
	pause_reason = reason
	pause_after_current_requested = false
	changed.emit()

# Retries the interrupted entry from encounter 1.
func resume() -> MissionData:
	if not enabled or not paused or active_entry == null:
		return null
	paused = false
	pause_reason = ""
	active_entry.entry_status = MissionQueueEntry.Status.ACTIVE
	changed.emit()
	return active_entry.mission

func request_stop() -> void:
	if enabled:
		stop_requested = true
		changed.emit()

func request_pause_after_current() -> void:
	if running:
		pause_after_current_requested = true
		changed.emit()

# Ends the session but keeps the configured orders until the player clears them.
func stop(reason: String) -> void:
	enabled = false
	paused = false
	pause_reason = ""
	stop_requested = false
	pause_after_current_requested = false
	awaiting_result = false
	stop_reason = reason
	for entry in entries:
		if entry.entry_status in [MissionQueueEntry.Status.ACTIVE, MissionQueueEntry.Status.BLOCKED]:
			entry.entry_status = MissionQueueEntry.Status.PENDING
	changed.emit()

func progress_text() -> String:
	return "%d / %d" % [completed_entries, entries.size()]

func snapshot() -> Dictionary:
	var rows: Array[String] = []
	for entry in entries:
		rows.append("%s:%s(%d/%d)" % [entry.mission_id, entry.status_name(), entry.completed_count, entry.repeat_count])
	return {"unlocked": unlocked, "enabled": enabled, "paused": paused, "pause_reason": pause_reason,
		"current_index": current_index, "completed_entries": completed_entries, "session_run_count": session_run_count,
		"awaiting_result": awaiting_result, "party_hero_ids": party_hero_ids, "formation_slots": formation_slots, "stop_requested": stop_requested, "entries": rows}

func _emit_changed() -> void:
	changed.emit()
