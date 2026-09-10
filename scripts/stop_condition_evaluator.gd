class_name StopConditionEvaluator
extends RefCounted

enum Reason { NONE, ENERGY_LOW, HP_LOW, INVENTORY_LIMIT, HERO_DOWNED, ENCOUNTER_CAP, NO_CONSUMABLES }

# Pure snapshot evaluation: no rewards, movement, UI, or stat changes here.
static func evaluate(state: Dictionary, config: ExpeditionStopConfig) -> Dictionary:
	var reason: Reason = Reason.NONE
	var hp: float = state.get("current_hp", 100)
	var max_hp: float = state.get("max_hp", 100)
	var energy: float = state.get("current_energy", 100)
	var max_energy: float = state.get("max_energy", 100)
	if config.return_on_hero_downed and hp <= 0:
		reason = Reason.HERO_DOWNED
	elif hp < max_hp * config.min_hp_percent:
		reason = Reason.HP_LOW
	elif energy < max_energy * config.min_energy_percent:
		reason = Reason.ENERGY_LOW
	elif config.inventory_stop_enabled and state.get("carried_units", 0) >= config.inventory_capacity * config.inventory_return_percent:
		reason = Reason.INVENTORY_LIMIT
	elif config.encounter_cap > 0 and state.get("encounters_completed", 0) >= config.encounter_cap:
		reason = Reason.ENCOUNTER_CAP
	return {"should_stop": reason != Reason.NONE, "reason": reason}

static func reason_text(reason: Reason) -> String:
	match reason:
		Reason.ENERGY_LOW: return "Low Energy"
		Reason.HP_LOW: return "Low HP"
		Reason.INVENTORY_LIMIT: return "Inventory Limit"
		Reason.HERO_DOWNED: return "Hero Downed"
		Reason.ENCOUNTER_CAP: return "Encounter Cap"
		Reason.NO_CONSUMABLES: return "No Consumables"
		_: return "None"

# Energy/cap estimate only. The final encounter wins over return thresholds.
static func predict(mission: MissionData, current_energy: int, max_energy: int, config: ExpeditionStopConfig) -> String:
	var remaining: int = current_energy
	for encounter in range(1, mission.encounter_count):
		remaining = maxi(remaining - mission.energy_for_encounter(encounter), 0)
		if remaining < max_energy * config.min_energy_percent:
			return "RISK OF RETREAT"
		if config.encounter_cap > 0 and encounter >= config.encounter_cap:
			return "RISK OF RETREAT"
	return "LIKELY TO COMPLETE"
