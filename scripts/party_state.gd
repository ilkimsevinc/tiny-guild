class_name PartyState
extends Node

# Hero roster, the player's party selection, and the party currently on a mission.
# Hero-agnostic: new heroes only need to be registered with their EnergyRecovery.

signal changed

const BASE_PARTY_SIZE: int = 2
const UNAVAILABLE_STATUSES: Dictionary = {
	"RESTING": "%s is resting.",
	"ON_EXPEDITION": "%s is on an expedition.",
	"RETURNING": "%s is returning.",
}

var party_id: String = "guild_party"
# Future party-capacity mastery hook.
var capacity_bonus: int = 0
var roster: Array[HeroController] = []
var recoveries: Dictionary[String, EnergyRecovery] = {}
# Player selection for the next manual dispatch.
var hero_ids: Array[String] = []
# Heroes on the current mission (empty at the Guild).
var active_hero_ids: Array[String] = []
var status: String = "AT_GUILD"
var current_mission_id: String = ""

func register(hero: HeroController, recovery: EnergyRecovery) -> void:
	if hero in roster:
		return
	roster.append(hero)
	recoveries[hero.hero_id] = recovery
	changed.emit()

func max_party_size() -> int:
	return BASE_PARTY_SIZE + capacity_bonus

func hero(id: String) -> HeroController:
	for member in roster:
		if member.hero_id == id:
			return member
	return null

func heroes_for(ids: Array[String]) -> Array[HeroController]:
	var result: Array[HeroController] = []
	for id in ids:
		var member: HeroController = hero(id)
		if member != null:
			result.append(member)
	return result

func active_heroes() -> Array[HeroController]:
	return heroes_for(active_hero_ids)

func selected_heroes() -> Array[HeroController]:
	return heroes_for(hero_ids)

func is_selected(id: String) -> bool:
	return id in hero_ids

func unavailable_reason(member: HeroController) -> String:
	if member == null:
		return "Unknown hero."
	if UNAVAILABLE_STATUSES.has(member.guild_status):
		return UNAVAILABLE_STATUSES[member.guild_status] % member.display_name
	return ""

# Busy heroes cannot be newly selected; deselecting is always allowed.
func set_selected(id: String, selected: bool) -> bool:
	var member: HeroController = hero(id)
	if member == null:
		return false
	if not selected:
		hero_ids.erase(id)
		changed.emit()
		return true
	if is_selected(id):
		return true
	if hero_ids.size() >= max_party_size() or not unavailable_reason(member).is_empty():
		return false
	hero_ids.append(id)
	# Keep roster order so "Arthur + Mimi" reads the same regardless of click order.
	hero_ids.sort_custom(func(a, b): return roster.find(hero(a)) < roster.find(hero(b)))
	changed.emit()
	return true

func select_only(ids: Array[String]) -> void:
	hero_ids.clear()
	for id in ids:
		set_selected(id, true)
	changed.emit()

func dispatch_reason(ids: Array[String]) -> String:
	if ids.is_empty():
		return "Select at least one hero."
	if ids.size() > max_party_size():
		return "Party is full (%d max)." % max_party_size()
	for member in heroes_for(ids):
		var reason: String = unavailable_reason(member)
		if not reason.is_empty():
			return reason
	return "" if heroes_for(ids).size() == ids.size() else "Unknown hero."

func any_resting(ids: Array[String]) -> bool:
	for id in ids:
		if recoveries.has(id) and recoveries[id].recovery_enabled:
			return true
	return false

func all_ready(ids: Array[String]) -> bool:
	if ids.is_empty():
		return false
	for id in ids:
		if not recoveries.has(id) or not recoveries[id].is_ready():
			return false
	return true

# Party predictions use the weakest member's Energy.
func min_energy(ids: Array[String]) -> int:
	var lowest: int = 1 << 30
	for member in heroes_for(ids):
		lowest = mini(lowest, member.current_energy)
	return lowest if lowest != 1 << 30 else 0

func names(ids: Array[String]) -> String:
	var parts: Array[String] = []
	for member in heroes_for(ids):
		parts.append(member.display_name)
	return " + ".join(parts) if not parts.is_empty() else "None"

func begin_mission(ids: Array[String], mission_id: String) -> void:
	active_hero_ids = ids.duplicate()
	current_mission_id = mission_id
	status = "ON_EXPEDITION"
	changed.emit()

func set_returning() -> void:
	status = "RETURNING"
	changed.emit()

func end_mission() -> void:
	status = "AT_GUILD"
	current_mission_id = ""
	changed.emit()

func readiness() -> Dictionary:
	var info: Dictionary = {}
	for member in roster:
		var recovery: EnergyRecovery = recoveries.get(member.hero_id)
		info[member.hero_id] = {"status": member.guild_status, "energy": member.current_energy,
			"max_energy": member.max_energy, "ready": recovery != null and recovery.is_ready(),
			"level": member.progression.level}
	return info

func snapshot() -> Dictionary:
	return {"party_id": party_id, "selected": hero_ids, "active": active_hero_ids, "status": status,
		"current_mission": current_mission_id, "max_party_size": max_party_size(), "heroes": readiness()}
