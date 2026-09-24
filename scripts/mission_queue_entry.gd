class_name MissionQueueEntry
extends RefCounted

# One player-authored Expedition Order. Duplicates are separate entries.

enum Status { PENDING, ACTIVE, COMPLETED, SKIPPED, BLOCKED }

var mission: MissionData
var mission_id: String = ""
# Reserved for future special-mission orders; persistent missions leave it empty.
var mission_instance_id: String = ""
var display_name: String = ""
var repeat_count: int = 1
var completed_count: int = 0
var entry_status: Status = Status.PENDING

static func create(data: MissionData, times: int = 1) -> MissionQueueEntry:
	var entry := MissionQueueEntry.new()
	entry.mission = data
	entry.mission_id = data.id
	entry.display_name = data.display_name
	entry.repeat_count = maxi(times, 1)
	return entry

func reset() -> void:
	completed_count = 0
	entry_status = Status.PENDING

func is_done() -> bool:
	return completed_count >= repeat_count

func status_name() -> String:
	return Status.keys()[entry_status]

# ASCII markers: the default font has no check/play glyphs.
func marker() -> String:
	match entry_status:
		Status.COMPLETED: return "[x]"
		Status.ACTIVE: return "[>]"
		Status.BLOCKED: return "[!]"
		Status.SKIPPED: return "[-]"
		_: return "[ ]"
