class_name EnemyData
extends Resource

@export var id: String = "slime"
@export var display_name: String = "Slime"
@export var max_hp: int = 30
@export var gold_reward: int = 10
@export var xp_reward: int = 15
@export var enemy_type: String = "NORMAL"
@export var loot_profile: String = "slime"
@export var completion_loot_profile: String = ""
@export var placeholder_color: Color = Color(0.4, 0.8, 0.42, 1)
@export var placeholder_scale: float = 1.0
@export var placeholder_polygon: PackedVector2Array = PackedVector2Array()
