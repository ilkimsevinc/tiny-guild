class_name HeroData
extends Resource

# Static definition of a playable hero. Runtime values (level, XP, HP, Energy,
# equipment, skills) live on the HeroController and its child nodes.

const MELEE: String = "MELEE"
const RANGED_MAGIC: String = "RANGED_MAGIC"

@export var hero_id: String = ""
@export var display_name: String = ""
@export var class_id: String = ""
@export var combat_style: String = MELEE
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
