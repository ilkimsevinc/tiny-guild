extends Node2D

const SLIME_SCENE = preload("res://scenes/slime.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const GOLD_PER_SLIME: int = 10
const XP_PER_SLIME: int = 15
const PICKUP_RANGE: float = 36.0
const GROUND_LOOT_SCENE = preload("res://scenes/ground_loot.tscn")
const LOOT_TABLE = preload("res://scripts/loot_table.gd")
const DEBUG_HINT: String = "DEBUG: 0 Energy=40 | 1 refresh | 2 Normal | 3 Elite | 4 Boss | 5 expire in 5s | 6 fast refresh | F6 = next Rare | F7 = next Epic | F8 = defeat encounter | F9 = test items | F10 = +500 Gold | F11 = +1000 Gold | F12 = +10 Tokens"

# Only automated legacy tests opt into this before adding Main to the tree.
var debug_combat_mode: bool = false
var loot_table = LOOT_TABLE.new()
# Development only: F6/F7 override one kill, then normal rates resume.
var debug_next_drop: ItemData

# The wallet owns the balance; this read-only view keeps game queries simple.
var gold: int:
	get:
		return wallet.balance
var slime: Node2D
var spawn_on_right: bool = true

var last_defeated_position: Vector2
var notification_tween: Tween
@onready var board_rotation: MissionBoardRotation = $MissionBoardRotation
@onready var notification_label: Label = $UI/OpportunityNotification
var return_in_progress: bool = false
@onready var energy_label: Label = $UI/EnergyLabel
@onready var energy_bar: ProgressBar = $UI/EnergyBar
@onready var mission_run: MissionRun = $MissionRun
@onready var expedition_ui = $UI/ExpeditionPanel
@onready var board_button: Button = $UI/BoardButton
@onready var mission_label: Label = $UI/MissionLabel
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
@onready var ground_loot: Node2D = $GroundLoot
@onready var inventory: Inventory = $Inventory
@onready var inventory_ui = $UI/Sidebar/Inventory
@onready var skill_ui = $UI/Sidebar/Skills
@onready var wallet: GoldWallet = $GoldWallet
@onready var guild_mastery: GuildMasteryState = $GuildMastery
@onready var mastery_ui = $UI/Sidebar/Mastery
@onready var attack_interval_label: Label = $UI/AttackIntervalLabel
@onready var loot_debug_label: Label = $UI/LootDebugLabel


func _ready() -> void:
	loot_debug_label.visible = OS.is_debug_build()
	loot_debug_label.text = DEBUG_HINT
	inventory_ui.setup(inventory, arthur.equipment)
	skill_ui.setup(arthur.skills, wallet, arthur.name)
	mastery_ui.setup(guild_mastery, wallet)
	$UI/Sidebar.set_tab_title(1, "Class Skills")
	$UI/Sidebar.set_tab_title(2, "Guild Mastery")
	wallet.changed.connect(_update_gold)
	arthur.attacked.connect(_on_arthur_attacked)
	arthur.state_changed.connect(_on_arthur_state_changed)
	arthur.stats_changed.connect(_update_arthur_stats)
	arthur.progression.leveled_up.connect(_on_arthur_leveled_up)
	_update_arthur_stats()
	respawn_timer.timeout.connect(_on_encounter_delay_finished)
	gold_label.text = "Gold: %d" % gold
	debug_combat_mode = debug_combat_mode and OS.is_debug_build()
	mission_run.encounter_requested.connect(_spawn_slime)
	mission_run.completed.connect(_on_mission_completed)
	mission_run.retreated.connect(_on_mission_retreated)
	mission_run.changed.connect(_update_mission_status)
	expedition_ui.setup(mission_run, arthur, board_rotation)
	expedition_ui.dispatch_requested.connect(start_mission)
	expedition_ui.opportunity_requested.connect(start_opportunity)
	board_rotation.opportunity_spawned.connect(_on_opportunity_spawned)
	board_rotation.initialize()
	expedition_ui.continue_requested.connect(_on_summary_continue)
	board_button.pressed.connect(expedition_ui.show_board)
	if debug_combat_mode:
		expedition_ui.hide()
		board_button.hide()
		mission_label.text = "DEBUG: endless combat regression mode"
		_spawn_slime()
	else:
		hp_label.text = "No active encounter"
		status_label.text = "Choose a mission from the Expedition Board."
		_update_mission_status()


func _spawn_slime() -> void:
	if is_instance_valid(slime):
		return
	if not debug_combat_mode and (mission_run.mission_state != MissionRun.State.IN_PROGRESS or not mission_run.encounter_active):
		return
	slime = SLIME_SCENE.instantiate()
	if not debug_combat_mode:
		slime.enemy_data = mission_run.mission.enemy_for_encounter(mission_run.current_encounter)
	# Alternate sides so every respawn gives Arthur another short walk.
	slime.position = slime_spawn.position if spawn_on_right else alternate_spawn.position
	spawn_on_right = not spawn_on_right
	slime.health_changed.connect(_update_slime_hp)
	slime.damaged.connect(_on_slime_damaged)
	slime.died.connect(_on_slime_died)
	add_child(slime)
	_update_slime_hp(slime.hp)
	status_label.text = "Arthur approaches %s and attacks in melee range." % slime.enemy_data.display_name
	arthur.set_target(slime)


func _on_arthur_attacked(target: Node2D, damage: int) -> void:
	if is_instance_valid(slime) and target == slime and arthur.is_target_in_range():
		status_label.text = "Arthur hits %s for %d damage!" % [slime.enemy_data.display_name, damage]
		slime.take_damage(damage)


func _on_arthur_state_changed(state_name: String) -> void:
	if debug_combat_mode:
		state_label.text = "Arthur: " + state_name
	else:
		state_label.text = "Arthur: " + arthur.guild_status.replace("_", " ").capitalize()


func _on_slime_damaged(amount: int) -> void:
	_show_floating_text("-%d" % amount, slime.position + Vector2(0, -100), Color.WHITE)


func _show_floating_text(message: String, effect_position: Vector2, text_color: Color, font_size: int = 24, duration: float = 0.8) -> void:
	var effect = FLOATING_TEXT_SCENE.instantiate()
	add_child(effect)
	effect.position = effect_position
	effect.play(message, text_color, font_size, duration)


func _update_slime_hp(current_hp: int) -> void:
	hp_label.text = "%s HP: %d / %d" % [slime.enemy_data.display_name, current_hp, slime.enemy_data.max_hp]


func _on_slime_died() -> void:
	if not is_instance_valid(slime):
		return
	var defeated_position: Vector2 = slime.position
	last_defeated_position = defeated_position
	var enemy: EnemyData = slime.enemy_data
	# Resolve death immediately; the Slime's visual finishes independently.
	slime = null
	arthur.set_target(null)
	if not debug_combat_mode:
		arthur.consume_energy(mission_run.mission.energy_for_encounter(mission_run.current_encounter))
	var gold_reward: int = _gold_reward(enemy.gold_reward)
	var xp_reward: int = _xp_reward(enemy.xp_reward)
	wallet.add_gold(gold_reward)
	arthur.progression.add_xp(xp_reward)
	gold_label.text = "Gold: %d" % gold
	status_label.text = "Slime defeated! +%d Gold, +%d XP. Next Slime in 2 seconds..." % [gold_reward, xp_reward]
	_show_floating_text("+%d Gold" % gold_reward, defeated_position + Vector2(0, -65), Color(1, 0.82, 0.35))
	var drop: ItemData
	if debug_combat_mode:
		drop = loot_table.roll()
	elif enemy.loot_profile == "slime":
		drop = loot_table.roll(mission_run.loot_modifier("item_weight_multiplier"), mission_run.loot_modifier("rare_weight_multiplier"), mission_run.loot_modifier("material_weight_multiplier"))
	if OS.is_debug_build() and debug_next_drop != null and enemy.loot_profile == "slime":
		drop = debug_next_drop
		debug_next_drop = null
		loot_debug_label.text = DEBUG_HINT
	if drop != null:
		_spawn_ground_loot(drop, defeated_position)
	if debug_combat_mode:
		respawn_timer.start()
	else:
		status_label.text = "Encounter cleared. Collecting loot before checking expedition limits..."
		mission_run.record_defeat(gold_reward, xp_reward)
		_resolve_mission_checkpoint()

func _update_arthur_stats() -> void:
	energy_label.text = "Energy: %d / %d | Return below %d%%" % [arthur.current_energy, arthur.max_energy, roundi(mission_run.stop_config.min_energy_percent * 100)]
	energy_bar.max_value = arthur.max_energy
	energy_bar.value = arthur.current_energy
	var stats = arthur.progression
	arthur_label.text = "Arthur - Knight | Level %d\nDamage: %d | HP: %d / %d" % [
		stats.level, arthur.total_attack(), stats.current_hp, arthur.total_max_hp()
	]
	xp_label.text = "XP: %d / %d" % [stats.xp, stats.xp_required]
	xp_bar.max_value = stats.xp_required
	xp_bar.value = stats.xp
	attack_interval_label.text = "Attack interval: %.2f s" % arthur.attack_interval()


func _on_arthur_leveled_up() -> void:
	_show_floating_text("LEVEL UP!", arthur.position + Vector2(0, -145), Color(0.5, 0.9, 1))


func _physics_process(_delta: float) -> void:
	var nearest: Node2D
	var nearest_distance: float = INF
	for loot in ground_loot.get_children():
		if loot.collected:
			continue
		var distance: float = arthur.global_position.distance_to(loot.global_position)
		if distance <= PICKUP_RANGE:
			loot.collect()
		elif distance < nearest_distance:
			nearest = loot
			nearest_distance = distance
	arthur.loot_target = nearest


func _spawn_ground_loot(item: ItemData, drop_position: Vector2) -> Node2D:
	var loot = GROUND_LOOT_SCENE.instantiate()
	loot.item = item
	loot.position = drop_position
	loot.picked_up.connect(_on_loot_picked_up)
	ground_loot.add_child(loot)
	if item.is_rare_or_higher():
		_show_floating_text("%s DROP!\n%s" % [item.rarity_name(), item.display_name],
			drop_position + Vector2(0, -240), item.rarity_color(), 30, 1.8)
	return loot


func _on_loot_picked_up(item: ItemData) -> void:
	inventory.add_item(item)
	if not debug_combat_mode:
		mission_run.record_loot(item)
	var message: String = "Picked up " + item.display_name
	var font_size: int = 18
	var duration: float = 0.8
	if item.is_rare_or_higher():
		message = "%s PICKUP: %s" % [item.rarity_name(), item.display_name]
		font_size = 24
		duration = 1.5
	_show_floating_text(message, arthur.position + Vector2(0, -145),
		item.rarity_color(), font_size, duration)



func _unhandled_key_input(event: InputEvent) -> void:
	# Temporary manual testing controls, disabled in release builds.
	if not OS.is_debug_build() or not event is InputEventKey:
		return
	if not event.pressed or event.echo:
		return
	if event.keycode == KEY_6:
		board_rotation.debug_toggle_fast_refresh()
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_0:
		arthur.current_energy = 40
		get_viewport().set_input_as_handled()
		return
	if event.keycode in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]:
		if event.keycode == KEY_5:
			var target: MissionInstance = mission_run.source_instance if mission_run.source_instance != null and mission_run.source_instance.active else board_rotation.slot
			board_rotation.debug_expire_soon(target)
		else:
			board_rotation.debug_refresh(int(event.keycode - KEY_2))
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F8:
		if is_instance_valid(slime):
			slime.take_damage(slime.hp)
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F11:
		wallet.add_gold(1000)
		loot_debug_label.text = "DEBUG: +1000 Gold. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F12:
		wallet.add_guild_tokens(10)
		loot_debug_label.text = "DEBUG: +10 Guild Tokens. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F10:
		wallet.add_gold(500)
		loot_debug_label.text = "DEBUG: +500 Gold. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F9:
		for item in loot_table.ITEMS:
			inventory.add_item(item)
		loot_debug_label.text = "DEBUG: granted one of each test item. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F6:
		debug_next_drop = preload("res://data/items/slime_ring.tres")
	elif event.keycode == KEY_F7:
		debug_next_drop = preload("res://data/items/slime_crown.tres")
	else:
		return
	loot_debug_label.text = "DEBUG: next kill drops " + debug_next_drop.display_name
	get_viewport().set_input_as_handled()


func _update_gold() -> void:
	gold_label.text = "Gold: %d" % gold

func start_mission(data: MissionData, instance: MissionInstance = null) -> bool:
	if debug_combat_mode or not mission_run.can_start():
		return false
	if data.special_type != "BASE" and (instance == null or not instance.claimed or not instance.active or instance.definition != data):
		return false
	arthur.guild_status = "ON_EXPEDITION"
	if not mission_run.start(data, instance):
		arthur.guild_status = "IDLE_AT_GUILD"
		return false
	expedition_ui.hide()
	return true

func _on_encounter_delay_finished() -> void:
	if debug_combat_mode:
		_spawn_slime()
	else:
		mission_run.start_next_encounter()

func _gold_reward(base: int) -> int:
	return RewardCalculator.calculate(base, arthur.equipment.gold_bonus_percent(), guild_mastery.global_gold_multiplier)

func _xp_reward(base: int) -> int:
	return RewardCalculator.calculate(base, arthur.equipment.xp_bonus_percent(), guild_mastery.global_xp_multiplier)

func _on_mission_completed() -> void:
	var gold_reward: int = _gold_reward(mission_run.mission.base_gold_reward)
	var xp_reward: int = _xp_reward(mission_run.mission.base_xp_reward)
	if not mission_run.claim_completion_reward(gold_reward, xp_reward):
		return
	respawn_timer.stop()
	arthur.set_target(null)
	wallet.add_gold(gold_reward)
	arthur.progression.add_xp(xp_reward)
	if mission_run.mission.completion_loot != null:
		for item in mission_run.mission.completion_loot.roll(mission_run.completion_rng):
			_spawn_ground_loot(item, last_defeated_position)
	status_label.text = "MISSION COMPLETE! Returning to the Guild..."
	_show_floating_text("MISSION COMPLETE", arthur.position + Vector2(0, -200), Color(0.5, 1, 0.7), 28, 1.2)
	_return_to_guild()

func _on_mission_retreated() -> void:
	respawn_timer.stop()
	arthur.set_target(null)
	status_label.text = "EXPEDITION STOPPED: %s. Arthur is returning." % StopConditionEvaluator.reason_text(mission_run.stop_reason)
	_show_floating_text("EXPEDITION STOPPED\n" + StopConditionEvaluator.reason_text(mission_run.stop_reason),
		arthur.position + Vector2(0, -200), Color(1, 0.7, 0.3), 26, 1.2)
	_return_to_guild()

func _resolve_mission_checkpoint() -> void:
	# Pickup finishes before evaluating capacity or starting another encounter.
	while ground_loot.get_child_count() > 0:
		await get_tree().physics_frame
	mission_run.resolve_checkpoint(arthur.expedition_snapshot())
	if mission_run.mission_state == MissionRun.State.IN_PROGRESS:
		status_label.text = "Arthur continues the expedition. Next encounter in 2 seconds..."
		respawn_timer.start()

func _return_to_guild() -> void:
	if return_in_progress or mission_run.mission_state not in [MissionRun.State.COMPLETED, MissionRun.State.RETREATED]:
		return
	return_in_progress = true
	await get_tree().create_timer(0.5).timeout
	# Defensive guard: keep earned loot even if a new visual pickup is pending.
	while ground_loot.get_child_count() > 0:
		await get_tree().physics_frame
	mission_run.begin_return()
	arthur.guild_status = "RETURNING"
	_update_mission_status()
	status_label.text = "Arthur is returning to the Guild..."
	await get_tree().create_timer(1.0).timeout
	arthur.position = Vector2(240, 350)
	arthur.visuals.scale.x = 1.0
	arthur.guild_status = "IDLE_AT_GUILD"
	arthur.restore_energy()
	return_in_progress = false
	mission_run.finish_return()
	hp_label.text = "No active encounter"
	status_label.text = "Arthur is back at the Guild. Review the mission summary."
	expedition_ui.show_summary()

func _on_summary_continue() -> void:
	if mission_run.acknowledge_summary():
		status_label.text = "Choose the next mission manually."
		expedition_ui.show_board()

func _update_mission_status() -> void:
	if debug_combat_mode:
		return
	state_label.text = "Arthur: " + arthur.guild_status.replace("_", " ").capitalize()
	board_button.disabled = not mission_run.can_start()
	if mission_run.mission == null:
		mission_label.text = ""
	else:
		mission_label.text = "Mission: %s | Encounter %d / %d | %s" % [
			mission_run.mission.display_name, mission_run.current_encounter,
			mission_run.total_encounters, MissionRun.State.keys()[mission_run.mission_state]]
func start_opportunity(instance: MissionInstance) -> bool:
	if debug_combat_mode or not mission_run.can_start() or not board_rotation.can_claim(instance):
		return false
	if not instance.definition.is_valid_definition():
		return false
	if not board_rotation.claim(instance):
		return false
	return start_mission(instance.definition, instance)

func _on_opportunity_spawned(instance: MissionInstance) -> void:
	if instance.special_type not in ["ELITE", "BOSS"]:
		return
	notification_label.text = "BOSS PORTAL OPENED" if instance.special_type == "BOSS" else "Elite mission appeared!"
	if notification_tween:
		notification_tween.kill()
	notification_label.modulate.a = 1.0
	notification_tween = create_tween()
	notification_tween.tween_interval(4.0)
	notification_tween.tween_property(notification_label, "modulate:a", 0.0, 0.5)