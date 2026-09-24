class_name PartyFormation
extends RefCounted

# Ordered formation slots for a party. Slot 0 is the front anchor; each later
# slot stands BACKLINE_SPACING further behind it (relative to the enemy, not the world).

const SLOT_ROWS: Array[String] = ["FRONT", "BACK"]
const MAX_SLOTS: int = 2
# Distance a back-row hero keeps behind the slot in front of it.
const BACKLINE_SPACING: float = 110.0
# No two heroes stand closer than this, even while moving.
const MIN_HERO_SPACING: float = 56.0

# hero_id per slot, front first.
var slots: Array[String] = []

# Role-based automatic formation: FRONTLINE/MELEE_DPS first, others behind,
# keeping roster order within each group so the result is stable.
static func auto(heroes: Array[HeroController]) -> PartyFormation:
	var formation := PartyFormation.new()
	var front: Array[String] = []
	var back: Array[String] = []
	for member in heroes:
		if member.hero_data.prefers_front():
			front.append(member.hero_id)
		else:
			back.append(member.hero_id)
	formation.slots.append_array(front)
	formation.slots.append_array(back)
	formation.slots.resize(mini(formation.slots.size(), MAX_SLOTS))
	return formation

static func from_slots(hero_ids: Array[String]) -> PartyFormation:
	var formation := PartyFormation.new()
	formation.slots = hero_ids.duplicate()
	return formation

func slot_of(hero_id: String) -> int:
	return slots.find(hero_id)

func row_of(hero_id: String) -> String:
	var index: int = slot_of(hero_id)
	if index < 0:
		return ""
	return SLOT_ROWS[mini(index, SLOT_ROWS.size() - 1)]

func front_id() -> String:
	return slots[0] if not slots.is_empty() else ""

# Hero in the slot directly ahead, or "" for the front anchor.
func leader_of(hero_id: String) -> String:
	var index: int = slot_of(hero_id)
	return slots[index - 1] if index > 0 else ""

func spacing_of(hero_id: String) -> float:
	return BACKLINE_SPACING if slot_of(hero_id) > 0 else 0.0

func describe(names: Dictionary) -> String:
	var parts: Array[String] = []
	for hero_id in slots:
		parts.append("%s %s" % [row_of(hero_id), names.get(hero_id, hero_id)])
	return " | ".join(parts)
