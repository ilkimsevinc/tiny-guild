class_name QueueSessionSummary
extends RefCounted

# Aggregates finished MissionRuns; each run keeps its own summary data.

var gold: int = 0
var xp: int = 0
var missions_completed: int = 0
var retreats: int = 0
var total_encounters: int = 0
var loot: Dictionary[String, int] = {}
var loot_items: Dictionary[String, ItemData] = {}

func record_run(run: MissionRun) -> void:
	gold += run.total_gold()
	xp += run.total_xp()
	total_encounters += run.defeated_encounters
	if run.result_status == MissionRun.Result.COMPLETED:
		missions_completed += 1
	else:
		retreats += 1
	for item_id in run.collected_loot:
		loot[item_id] = loot.get(item_id, 0) + run.collected_loot[item_id]
		loot_items[item_id] = run.loot_items[item_id]

func loot_lines() -> Array[String]:
	var lines: Array[String] = []
	for item_id in loot:
		lines.append("%s x%d" % [loot_items[item_id].display_name, loot[item_id]])
	return lines
