extends Node2D

const SLIME_SCENE = preload("res://scenes/slime.tscn")
const GOLD_PER_SLIME: int = 10

var gold: int = 0
var slime: Node2D

@onready var kael = $Kael
@onready var slime_spawn: Marker2D = $SlimeSpawn
@onready var respawn_timer: Timer = $RespawnTimer
@onready var gold_label: Label = $UI/GoldLabel
@onready var hp_label: Label = $UI/SlimeHPLabel
@onready var status_label: Label = $UI/StatusLabel


func _ready() -> void:
	kael.attacked.connect(_on_kael_attacked)
	respawn_timer.timeout.connect(_spawn_slime)
	gold_label.text = "Gold: %d" % gold
	_spawn_slime()


func _spawn_slime() -> void:
	slime = SLIME_SCENE.instantiate()
	slime.position = slime_spawn.position
	slime.health_changed.connect(_update_slime_hp)
	slime.died.connect(_on_slime_died)
	add_child(slime)
	_update_slime_hp(slime.hp)
	status_label.text = "Kael attacks automatically every second."
	# Restart the attack timer so each new Slime gets a full second before a hit.
	kael.start_attacking()


func _on_kael_attacked(damage: int) -> void:
	if is_instance_valid(slime):
		status_label.text = "Kael hits the Slime for %d damage!" % damage
		slime.take_damage(damage)


func _update_slime_hp(current_hp: int) -> void:
	hp_label.text = "Slime HP: %d / 30" % current_hp


func _on_slime_died() -> void:
	# The Slime frees itself; clear our target while waiting for the next one.
	slime = null
	kael.stop_attacking()
	gold += GOLD_PER_SLIME
	gold_label.text = "Gold: %d" % gold
	status_label.text = "Slime defeated! +10 Gold. Next Slime in 2 seconds..."
	respawn_timer.start()
