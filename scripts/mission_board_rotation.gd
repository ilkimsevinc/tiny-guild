class_name MissionBoardRotation
extends Node

signal changed
signal countdown_changed
signal opportunity_spawned(instance: MissionInstance)

# Exactly one opportunity; persistent base missions are owned by their static list.
@export var config: MissionRotationConfig = preload("res://data/rotation/default.tres").duplicate()
var slot: MissionInstance
var next_refresh_at: float = 0.0
var rng := RandomNumberGenerator.new()
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var initialized: bool = false
var serial: int = 0
var debug_normal_refresh_seconds: float = 0.0

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.timeout.connect(tick)
	add_child(timer)
	timer.start()

func initialize() -> void:
	if initialized:
		return
	initialized = true
	rng.randomize()
	next_refresh_at = now() + config.refresh_seconds
	spawn_opportunity()

func now() -> float:
	return clock.call()

func index_for_roll(value: int) -> int:
	var threshold: int = 0
	for index in range(config.spawn_weights.size()):
		threshold += config.spawn_weights[index]
		if value < threshold:
			return index
	return -1

func tick() -> void:
	if not initialized:
		return
	var time: float = now()
	if slot != null:
		if not slot.active and time >= slot.expires_at:
			slot = null
			# Give an expired slot a visible empty period, even on a refresh boundary.
			next_refresh_at = time + config.refresh_seconds
			changed.emit()
	if time >= next_refresh_at:
		next_refresh_at = time + config.refresh_seconds
		if slot == null:
			spawn_opportunity()
	countdown_changed.emit()

func spawn_opportunity(forced_index: int = -1) -> void:
	var index: int = forced_index
	if index < 0:
		var total: int = 0
		for weight in config.spawn_weights:
			total += weight
		index = index_for_roll(rng.randi_range(0, total - 1))
	if index < 0 or index >= config.missions.size():
		return
	var data: MissionData = config.missions[index]
	var instance := MissionInstance.new()
	serial += 1
	instance.instance_id = "opportunity_%d" % serial
	instance.definition = data
	instance.mission_data_id = data.id
	instance.special_type = data.special_type
	instance.requires_manual_attention = data.requires_manual_attention
	instance.seed = rng.randi()
	instance.spawned_at = now()
	instance.expires_at = instance.spawned_at + config.expiration_seconds[index]
	instance.clock = clock
	instance.mission_modifiers = {"item_weight_multiplier": data.item_weight_multiplier,
		"rare_weight_multiplier": data.rare_weight_multiplier, "material_weight_multiplier": data.material_weight_multiplier}
	slot = instance
	changed.emit()
	opportunity_spawned.emit(instance)

func can_claim(instance: MissionInstance) -> bool:
	return instance != null and instance == slot and instance.can_dispatch(now())

func claim(instance: MissionInstance) -> bool:
	if not can_claim(instance):
		return false
	instance.claimed = true
	instance.active = true
	# Claimed instances are held by MissionRun; rotating slot may refill independently.
	slot = null
	changed.emit()
	return true

func debug_refresh(index: int = -1) -> void:
	if OS.is_debug_build():
		spawn_opportunity(index)
		next_refresh_at = now() + config.refresh_seconds

func debug_expire_soon(instance: MissionInstance) -> void:
	if OS.is_debug_build() and instance != null:
		instance.expires_at = now() + 5.0
		countdown_changed.emit()

func debug_toggle_fast_refresh() -> void:
	if not OS.is_debug_build():
		return
	if debug_normal_refresh_seconds == 0.0:
		debug_normal_refresh_seconds = config.refresh_seconds
		config.refresh_seconds = 10.0
	else:
		config.refresh_seconds = debug_normal_refresh_seconds
		debug_normal_refresh_seconds = 0.0
	next_refresh_at = now() + config.refresh_seconds
	countdown_changed.emit()