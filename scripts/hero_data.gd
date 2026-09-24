class_name HeroData
extends Resource

# Static definition of a playable hero. Runtime values (level, XP, HP, Energy,
# equipment, skills) live on the HeroController and its child nodes.

# combat_style = how an attack is delivered (lunge vs projectile feedback).
const MELEE: String = "MELEE"
const RANGED_MAGIC: String = "RANGED_MAGIC"

# combat_role = where the hero wants to stand in the party (formation intent).
# A future FRONTLINE/MAGE hybrid such as Regnier can pair FRONTLINE with RANGED_MAGIC.
const FRONTLINE: String = "FRONTLINE"
const MELEE_DPS: String = "MELEE_DPS"
const RANGED_DPS: String = "RANGED_DPS"
const MAGE: String = "MAGE"
const SUPPORT: String = "SUPPORT"
const FRONT_ROLES: Array[String] = [FRONTLINE, MELEE_DPS]

@export var hero_id: String = ""
@export var display_name: String = ""
@export var class_id: String = ""
@export var combat_style: String = MELEE
@export_enum("FRONTLINE", "MELEE_DPS", "RANGED_DPS", "MAGE", "SUPPORT") var combat_role: String = FRONTLINE
@export var base_max_hp: int = 100
@export var base_damage: int = 10
@export var hp_per_level: int = 10
@export var damage_per_level: int = 2
@export var max_energy: int = 100
@export var base_attack_interval: float = 1.0
@export var attack_range: float = 130.0
@export var move_speed: float = 180.0
# Placeholder presentation only.
@export var damage_color: Color = Color.WHITE

func is_ranged() -> bool:
	return combat_style != MELEE

func prefers_front() -> bool:
	return combat_role in FRONT_ROLES
