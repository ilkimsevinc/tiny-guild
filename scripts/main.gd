extends Node2D

const SLIME_SCENE = preload("res://scenes/slime.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const GOLD_PER_SLIME: int = 10
const XP_PER_SLIME: int = 15

var gold: int = 0
var slime: Node2D
var spawn_on_right: bool = true

@onready var arthur = $Arthur
@onready var slime_spawn: Marker2D = $SlimeSpawn
@onready var alternate_spawn: Marker2D = $AlternateSlimeSpawn
@onready var respawn_timer: Timer = $RespawnTimer
@onready var gold_label: Label = $UI/GoldLabel
@onready var hp_label: Label = $UI/SlimeHPLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var state_label: Label = $UI/StateLabel
@onready var arthur_label: Label = $UI/ArthurLabel
@onready var xp_label: Label = $UI/XPLabel
@onready var xp_bar: ProgressBar = $UI/XPBar


func _ready() -> void:
	arthur.attacked.connect(_on_arthur_attacked)
	arthur.state_changed.connect(_on_arthur_state_changed)
	arthur.progression.stats_changed.connect(_update_arthur_stats)
	arthur.progression.leveled_up.connect(_on_arthur_leveled_up)
	_update_arthur_stats()
	respawn_timer.timeout.connect(_spawn_slime)
	gold_label.text = "Gold: %d" % gold
	_spawn_slime()


func _spawn_slime() -> void:
	slime = SLIME_SCENE.instantiate()
	# Alternate sides so every respawn gives Arthur another short walk.
	slime.position = slime_spawn.position if spawn_on_right else alternate_spawn.position
	spawn_on_right = not spawn_on_right
	slime.health_changed.connect(_update_slime_hp)
	slime.damaged.connect(_on_slime_damaged)
	slime.died.connect(_on_slime_died)
	add_child(slime)
	_update_slime_hp(slime.hp)
	status_label.text = "Arthur approaches the Slime and attacks once per second in melee range."
	arthur.set_target(slime)


func _on_arthur_attacked(target: Node2D, damage: int) -> void:
	if is_instance_valid(slime) and target == slime and arthur.is_target_in_range():
		status_label.text = "Arthur hits the Slime for %d damage!" % damage
		slime.take_damage(damage)


func _on_arthur_state_changed(state_name: String) -> void:
	state_label.text = "Arthur: " + state_name


func _on_slime_damaged(amount: int) -> void:
	_show_floating_text("-%d" % amount, slime.position + Vector2(0, -100), Color.WHITE)


func _show_floating_text(message: String, effect_position: Vector2, text_color: Color) -> void:
	var effect = FLOATING_TEXT_SCENE.instantiate()
	add_child(effect)
	effect.position = effect_position
	effect.play(message, text_color)


func _update_slime_hp(current_hp: int) -> void:
	hp_label.text = "Slime HP: %d / 30" % current_hp


func _on_slime_died() -> void:
	var defeated_position: Vector2 = slime.position
	# Resolve death immediately; the Slime's visual finishes independently.
	slime = null
	arthur.set_target(null)
	gold += GOLD_PER_SLIME
	arthur.progression.add_xp(XP_PER_SLIME)
	gold_label.text = "Gold: %d" % gold
	status_label.text = "Slime defeated! +10 Gold, +15 XP. Next Slime in 2 seconds..."
	respawn_timer.start()
	_show_floating_text("+10 Gold", defeated_position + Vector2(0, -65), Color(1, 0.82, 0.35))

func _update_arthur_stats() -> void:
	var stats = arthur.progression
	arthur_label.text = "Arthur - Knight | Level %d\nDamage: %d | HP: %d / %d" % [
		stats.level, stats.damage, stats.current_hp, stats.max_hp
	]
	xp_label.text = "XP: %d / %d" % [stats.xp, stats.xp_required]
	xp_bar.max_value = stats.xp_required
	xp_bar.value = stats.xp


func _on_arthur_leveled_up() -> void:
	_show_floating_text("LEVEL UP!", arthur.position + Vector2(0, -145), Color(0.5, 0.9, 1))
