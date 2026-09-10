extends Node2D

signal health_changed(current_hp: int)
signal damaged(amount: int)
signal died

@export var enemy_data: EnemyData = preload("res://data/enemies/slime.tres")
var base_visual_scale: Vector2 = Vector2.ONE
const MAX_HP: int = 30
var hp: int = MAX_HP
var feedback_tween: Tween

@onready var visuals: Node2D = $Visuals


func _ready() -> void:
	hp = enemy_data.max_hp
	base_visual_scale = Vector2.ONE * enemy_data.placeholder_scale
	visuals.scale = base_visual_scale
	$Visuals/Body.color = enemy_data.placeholder_color
	if not enemy_data.placeholder_polygon.is_empty():
		$Visuals/Body.polygon = enemy_data.placeholder_polygon
	damaged.connect(_play_hit_feedback)
	died.connect(_play_death_feedback)


func take_damage(amount: int) -> void:
	if hp <= 0 or amount <= 0:
		return

	var damage_dealt: int = mini(amount, hp)
	hp = maxi(hp - amount, 0)
	health_changed.emit(hp)
	damaged.emit(damage_dealt)
	if hp == 0:
		died.emit()


func _reset_feedback() -> void:
	if feedback_tween:
		feedback_tween.kill()
	visuals.scale = base_visual_scale
	visuals.modulate = Color.WHITE


func _play_hit_feedback(_amount: int) -> void:
	_reset_feedback()
	visuals.modulate = Color(2.0, 2.0, 2.0)
	visuals.scale = base_visual_scale * Vector2(1.15, 0.8)
	feedback_tween = create_tween().set_parallel(true)
	feedback_tween.tween_property(visuals, "modulate", Color.WHITE, 0.18)
	feedback_tween.tween_property(visuals, "scale", base_visual_scale, 0.18)


func _play_death_feedback() -> void:
	_reset_feedback()
	feedback_tween = create_tween().set_parallel(true)
	feedback_tween.tween_property(visuals, "scale", base_visual_scale * Vector2(1.3, 0.1), 0.25)
	feedback_tween.tween_property(visuals, "modulate:a", 0.0, 0.25)
	feedback_tween.chain().tween_callback(queue_free)