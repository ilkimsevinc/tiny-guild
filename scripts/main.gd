extends Node2D

const SLIME_SCENE = preload("res://scenes/slime.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const GOLD_PER_SLIME: int = 10
const XP_PER_SLIME: int = 15
const PICKUP_RANGE: float = 36.0
const GROUND_LOOT_SCENE = preload("res://scenes/ground_loot.tscn")
const LOOT_TABLE = preload("res://scripts/loot_table.gd")
const DEBUG_HINT: String = "DEBUG: 0 Arthur Energy=40 | F2 Mimi Energy=40 | F3 +30 Mimi XP | 7 10x recovery | 8 Full Energy (all) | 9 pause queue after current | 1 refresh | 2 Normal | 3 Elite | 4 Boss | 5 expire in 5s | 6 fast refresh | F4 state | F5 stop repeat | F6 Rare | F7 Epic | F8 defeat | F9 items | F10 +500 Gold | F11 +1000 Gold | F12 +10 Tokens"
const REPEAT_SUMMARY_SECONDS: float = 1.75
const REPEAT_PREPARATION_SECONDS: float = 2.0
const QUEUE_RESULT_SECONDS: float = 1.5

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
# Colour of the most recent hit, so damage numbers show who dealt them.
var last_hit_color: Color = Color.WHITE
var heroes: Array[HeroController] = []
# Hero shown in the Stats / Equipment / Skill Tree panels.
var hero_context: HeroController
var roster_buttons: Dictionary[String, Button] = {}
@onready var board_rotation: MissionBoardRotation = $MissionBoardRotation
@onready var notification_label: Label = $UI/OpportunityNotification
@onready var repeat_orders: RepeatOrderState = $RepeatOrderState
# Arthur's recovery; every hero gets one, see recovery_for().
@onready var energy_recovery: EnergyRecovery = $EnergyRecovery
@onready var repeat_status_label: Label = $UI/RepeatStatus
@onready var stop_repeat_button: Button = $UI/StopRepeat
@onready var mission_queue: MissionQueueState = $MissionQueueState
@onready var queue_status_label: Label = $UI/QueueStatus
@onready var stop_queue_button: Button = $UI/StopQueue
@onready var party: PartyState = $PartyState
# Authoritative encounter target; heroes read it instead of searching.
@onready var targeting: TargetingController = $Targeting
# The encounter's single authoritative target (one enemy per encounter for now).
var active_target: Node2D:
	get:
		return targeting.active_target if targeting != null else null
@onready var hero_roster: VBoxContainer = $UI/HeroRoster
var return_in_progress: bool = false
var repeat_preparing: bool = false
var queue_preparing: bool = false
@onready var energy_label: Label = $UI/EnergyLabel
@onready var energy_bar: ProgressBar = $UI/EnergyBar
@onready var mission_run: MissionRun = $MissionRun
@onready var expedition_ui = $UI/ExpeditionPanel
@onready var board_button: Button = $UI/BoardButton
@onready var mission_label: Label = $UI/MissionLabel
@onready var arthur: HeroController = $Arthur
@onready var mimi: HeroController = $Mimi
@onready var slime_spawn: Marker2D = $SlimeSpawn
@onready var alternate_spawn: Marker2D = $AlternateSlimeSpawn
@onready var forward_spawn: Marker2D = $ForwardSlimeSpawn
@onready var respawn_timer: Timer = $RespawnTimer
@onready var gold_label: Label = $UI/GoldLabel
@onready var hp_label: Label = $UI/SlimeHPLabel
@onready var status_label: Label = $UI/StatusLabel
@onready var state_label: Label = $UI/StateLabel
# Shows the context hero's stats (name kept for existing tests).
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
	heroes = [arthur, mimi]
	for member in heroes:
		_register_hero(member)
	# Arthur alone is the default party, matching the single-hero game so far.
	party.select_only(["arthur"])
	hero_context = arthur
	inventory_ui.setup(inventory, arthur.equipment)
	skill_ui.setup(arthur.skills, wallet, arthur.display_name)
	mastery_ui.setup(guild_mastery, wallet)
	repeat_orders.setup(guild_mastery)
	repeat_orders.changed.connect(_update_repeat_status)
	stop_repeat_button.pressed.connect(_stop_repeat_after_current)
	mission_queue.setup(guild_mastery)
	mission_queue.changed.connect(_update_queue_status)
	stop_queue_button.pressed.connect(stop_queue)
	party.changed.connect(_update_hero_roster)
	$UI/Sidebar.set_tab_title(1, "Class Skills")
	$UI/Sidebar.set_tab_title(2, "Guild Mastery")
	wallet.changed.connect(_update_gold)
	arthur.state_changed.connect(_on_arthur_state_changed)
	_build_hero_roster()
	_update_arthur_stats()
	respawn_timer.timeout.connect(_on_encounter_delay_finished)
	gold_label.text = "Gold: %d" % gold
	debug_combat_mode = debug_combat_mode and OS.is_debug_build()
	mission_run.encounter_requested.connect(_spawn_slime)
	mission_run.completed.connect(_on_mission_completed)
	mission_run.retreated.connect(_on_mission_retreated)
	mission_run.changed.connect(_update_mission_status)
	expedition_ui.setup(mission_run, party, board_rotation, guild_mastery, repeat_orders, mission_queue)
	expedition_ui.dispatch_requested.connect(start_mission)
	expedition_ui.queue_start_requested.connect(start_queue)
	expedition_ui.queue_resume_requested.connect(resume_queue)
	expedition_ui.queue_stop_requested.connect(stop_queue)
	expedition_ui.opportunity_requested.connect(start_opportunity)
	board_rotation.opportunity_spawned.connect(_on_opportunity_spawned)
	board_rotation.initialize()
	expedition_ui.continue_requested.connect(_on_summary_continue)
	board_button.pressed.connect(expedition_ui.show_board)
	if debug_combat_mode:
		expedition_ui.hide()
		board_button.hide()
		repeat_status_label.hide()
		stop_repeat_button.hide()
		queue_status_label.hide()
		stop_queue_button.hide()
		mission_label.text = "DEBUG: endless combat regression mode"
		_spawn_slime()
	else:
		hp_label.text = "No active encounter"
		status_label.text = "Choose a mission from the Expedition Board."
		_update_mission_status()
	_update_repeat_status()
	_update_queue_status()


func _register_hero(member: HeroController) -> void:
	member.home_position = member.position
	var recovery: EnergyRecovery = energy_recovery if member == arthur else EnergyRecovery.new()
	if recovery != energy_recovery:
		recovery.name = member.hero_id.capitalize() + "Recovery"
		add_child(recovery)
	recovery.setup(member)
	party.register(member, recovery)
	recovery.ready_reached.connect(_on_recovery_ready)
	recovery.changed.connect(_update_arthur_stats)
	recovery.changed.connect(_update_repeat_status)
	recovery.changed.connect(_update_queue_status)
	recovery.changed.connect(_update_hero_roster)
	member.stats_changed.connect(recovery.sync_guild_status)
	member.stats_changed.connect(_update_arthur_stats)
	member.stats_changed.connect(_update_hero_roster)
	member.attacked.connect(_on_hero_attacked.bind(member))
	member.progression.leveled_up.connect(_on_hero_leveled_up.bind(member))


func recovery_for(member: HeroController) -> EnergyRecovery:
	return party.recoveries.get(member.hero_id)

# Heroes fighting the current encounter (the legacy endless mode is Arthur only).
func combat_heroes() -> Array[HeroController]:
	if debug_combat_mode:
		var solo: Array[HeroController] = [arthur]
		return solo
	return party.active_heroes()


func _spawn_slime() -> void:
	if is_instance_valid(slime):
		return
	if not debug_combat_mode and (mission_run.mission_state != MissionRun.State.IN_PROGRESS or not mission_run.encounter_active):
		return
	slime = SLIME_SCENE.instantiate()
	if not debug_combat_mode:
		slime.enemy_data = mission_run.mission.enemy_for_encounter(mission_run.current_encounter)
	# Missions spawn ahead of the regrouped party so formations always face forward;
	# the legacy endless mode keeps alternating sides.
	var second_spawn: Marker2D = alternate_spawn if debug_combat_mode else forward_spawn
	slime.position = slime_spawn.position if spawn_on_right else second_spawn.position
	spawn_on_right = not spawn_on_right
	slime.health_changed.connect(_update_slime_hp)
	slime.damaged.connect(_on_slime_damaged)
	slime.died.connect(_on_slime_died)
	add_child(slime)
	_update_slime_hp(slime.hp)
	targeting.register_enemy(slime)
	status_label.text = "%s engage %s." % [party.names(_ids_of(combat_heroes())), slime.enemy_data.display_name]
	for member in combat_heroes():
		member.set_target(targeting.target_for(member))


func _on_hero_attacked(target: Node2D, damage: int, member: HeroController) -> void:
	if is_instance_valid(slime) and target == active_target and target == slime and member.is_target_in_range():
		status_label.text = "%s hits %s for %d damage!" % [member.display_name, slime.enemy_data.display_name, damage]
		last_hit_color = member.hero_data.damage_color
		slime.take_damage(damage)


func _on_arthur_state_changed(state_name: String) -> void:
	if debug_combat_mode:
		state_label.text = "Arthur: " + state_name
	else:
		_update_arthur_stats()


func _on_slime_damaged(amount: int) -> void:
	_show_floating_text("-%d" % amount, slime.position + Vector2(0, -100), last_hit_color)


func _show_floating_text(message: String, effect_position: Vector2, text_color: Color, font_size: int = 24, duration: float = 0.8) -> void:
	var effect = FLOATING_TEXT_SCENE.instantiate()
	add_child(effect)
	effect.position = effect_position
	effect.play(message, text_color, font_size, duration)


func _update_slime_hp(current_hp: int) -> void:
	hp_label.text = "%s HP: %d / %d" % [slime.enemy_data.display_name, current_hp, slime.enemy_data.max_hp]


# One enemy death = one encounter for the whole party: Gold and loot once,
# full XP and the encounter's Energy cost for every participant.
func _on_slime_died() -> void:
	# release_enemy succeeds once per enemy, so near-simultaneous hits or duplicate
	# callbacks can never pay Gold, roll loot or advance the encounter twice.
	if not is_instance_valid(slime) or not targeting.release_enemy(slime):
		return
	var defeated_position: Vector2 = slime.position
	last_defeated_position = defeated_position
	var enemy: EnemyData = slime.enemy_data
	# Resolve death immediately; the Slime's visual finishes independently.
	slime = null
	var fighters: Array[HeroController] = combat_heroes()
	for member in fighters:
		member.set_target(null)
		if not debug_combat_mode:
			member.consume_energy(mission_run.mission.energy_for_encounter(mission_run.current_encounter))
	var gold_reward: int = _gold_reward(enemy.gold_reward)
	var xp_reward: int = _award_party_xp(enemy.xp_reward, fighters)
	wallet.add_gold(gold_reward)
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

# Full XP to each participant (no splitting); returns the first participant's amount.
func _award_party_xp(base_xp: int, members: Array[HeroController]) -> int:
	var first_amount: int = 0
	for member in members:
		var amount: int = _xp_reward(base_xp, member)
		member.progression.add_xp(amount)
		if not debug_combat_mode:
			mission_run.award_hero_xp(member.hero_id, amount)
		if member == members[0]:
			first_amount = amount
	return first_amount

func _update_arthur_stats() -> void:
	if hero_context == null:
		return
	var member: HeroController = hero_context
	var recovery: EnergyRecovery = recovery_for(member)
	var resting: bool = recovery != null and recovery.recovery_enabled
	energy_label.text = "Energy: %d / %d | Return below %d%%" % [member.current_energy, member.max_energy, roundi(mission_run.stop_config.min_energy_percent * 100)]
	if resting:
		energy_label.text += " | Resting +%s / sec" % str(snappedf(recovery.recovery_rate(), 0.1)).trim_suffix(".0")
	energy_bar.max_value = member.max_energy
	energy_bar.value = member.current_energy
	# Subtle recovery cue instead of per-tick floating text.
	energy_bar.modulate = Color(0.6, 1.0, 0.7) if resting else Color.WHITE
	if not debug_combat_mode:
		state_label.text = "%s: %s" % [member.display_name, member.guild_status.replace("_", " ").capitalize()]
	var stats = member.progression
	arthur_label.text = "%s - %s | Level %d\nDamage: %d | HP: %d / %d" % [
		member.display_name, member.skills.class_data.display_name if member.skills.class_data != null else member.class_id,
		stats.level, member.total_attack(), stats.current_hp, member.total_max_hp()
	]
	xp_label.text = "XP: %d / %d" % [stats.xp, stats.xp_required]
	xp_bar.max_value = stats.xp_required
	xp_bar.value = stats.xp
	attack_interval_label.text = "Attack interval: %.2f s" % member.attack_interval()


func _build_hero_roster() -> void:
	for member in heroes:
		var button := Button.new()
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 12)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.pressed.connect(set_hero_context.bind(member))
		hero_roster.add_child(button)
		roster_buttons[member.hero_id] = button
	_update_hero_roster()


func _update_hero_roster() -> void:
	for member in heroes:
		var button: Button = roster_buttons.get(member.hero_id)
		if button == null:
			continue
		button.text = "%s | %s | EN %d/%d" % [member.summary_line(),
			member.guild_status.replace("_", " "), member.current_energy, member.max_energy]
		button.set_pressed_no_signal(member == hero_context)


# One set of panels, rebound to whichever hero the player is inspecting.
func set_hero_context(member: HeroController) -> void:
	hero_context = member
	inventory_ui.set_equipment(member.equipment, member.display_name)
	skill_ui.setup(member.skills, wallet, member.display_name)
	_update_arthur_stats()
	_update_hero_roster()


func _on_hero_leveled_up(member: HeroController) -> void:
	_show_floating_text("LEVEL UP!", member.position + Vector2(0, -145), Color(0.5, 0.9, 1))


func _physics_process(_delta: float) -> void:
	# Loot is account-wide: any fighter can pick it up, the party leader walks to it.
	var fighters: Array[HeroController] = [arthur]
	if debug_combat_mode or mission_run.mission_state != MissionRun.State.IDLE:
		fighters = combat_heroes()
	var leader: HeroController = fighters[0] if not fighters.is_empty() else arthur
	var nearest: Node2D
	var nearest_distance: float = INF
	for loot in ground_loot.get_children():
		if loot.collected:
			continue
		var distance: float = leader.global_position.distance_to(loot.global_position)
		for member in fighters:
			if member.global_position.distance_to(loot.global_position) <= PICKUP_RANGE:
				distance = 0.0
		if distance <= PICKUP_RANGE:
			loot.collect()
		elif distance < nearest_distance:
			nearest = loot
			nearest_distance = distance
	for member in heroes:
		member.loot_target = nearest if member == leader else null


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
	var leader: HeroController = combat_heroes()[0] if not combat_heroes().is_empty() else arthur
	_show_floating_text(message, leader.position + Vector2(0, -145),
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
	if event.keycode == KEY_7:
		var mult: float = 1.0 if is_equal_approx(energy_recovery.debug_multiplier, 10.0) else 10.0
		for member in heroes:
			recovery_for(member).debug_set_multiplier(mult)
		loot_debug_label.text = "DEBUG: Recovery speed x%d. " % roundi(mult) + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_8:
		for member in heroes:
			member.restore_energy()
		loot_debug_label.text = "DEBUG: Full Energy restored for every hero. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_0:
		arthur.current_energy = 40
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F2:
		mimi.current_energy = 40
		loot_debug_label.text = "DEBUG: Mimi Energy set to 40. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F3:
		mimi.progression.add_xp(30)
		loot_debug_label.text = "DEBUG: +30 Mimi XP. " + DEBUG_HINT
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_9:
		# Future Boss Portal hook: pause Expedition Orders after the current mission.
		mission_queue.request_pause_after_current()
		loot_debug_label.text = "DEBUG: Expedition Orders pause after current mission. " + DEBUG_HINT
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
	if event.keycode == KEY_F4:
		print("REPEAT: %s | RECOVERY: %s" % [str(repeat_orders.snapshot()), str(energy_recovery.snapshot())])
		print("QUEUE: %s" % str(mission_queue.snapshot()))
		print("PARTY: %s" % str(party.snapshot()))
		loot_debug_label.text = "DEBUG REPEAT: %s\nDEBUG QUEUE: %s\nDEBUG PARTY: %s" % [
			str(repeat_orders.snapshot()), str(mission_queue.snapshot()), str(party.snapshot())]
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_F5:
		_stop_repeat_after_current()
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

func _ids_of(members: Array[HeroController]) -> Array[String]:
	var ids: Array[String] = []
	for member in members:
		ids.append(member.hero_id)
	return ids

# Automation reuses the party it remembered; manual dispatch uses the current selection.
func _dispatch_ids(automatic_repeat: bool, from_queue: bool) -> Array[String]:
	if from_queue:
		return mission_queue.party_hero_ids.duplicate()
	if automatic_repeat and not repeat_orders.party_hero_ids.is_empty():
		return repeat_orders.party_hero_ids.duplicate()
	return party.hero_ids.duplicate()

# Automation keeps the formation it remembered; manual dispatch uses role-based auto formation.
func _dispatch_formation(ids: Array[String], automatic_repeat: bool, from_queue: bool) -> PartyFormation:
	var remembered: Array[String] = []
	if from_queue:
		remembered = mission_queue.formation_slots
	elif automatic_repeat:
		remembered = repeat_orders.formation_slots
	if not remembered.is_empty() and remembered.size() == ids.size():
		return PartyFormation.from_slots(remembered)
	return party.formation_for(ids)

# Slot 0 anchors the front; each later slot follows the hero ahead of it.
func _apply_formation(formation: PartyFormation) -> void:
	for member in heroes:
		var leader: HeroController = party.hero(formation.leader_of(member.hero_id))
		member.set_formation(leader, formation.spacing_of(member.hero_id))

func start_mission(data: MissionData, instance: MissionInstance = null, automatic_repeat: bool = false, from_queue: bool = false) -> bool:
	if debug_combat_mode or not mission_run.can_start():
		return false
	var ids: Array[String] = _dispatch_ids(automatic_repeat, from_queue)
	# Partial Energy is allowed; empty parties and resting/busy heroes are not.
	if not party.dispatch_reason(ids).is_empty():
		return false
	if data.special_type != "BASE" and (instance == null or not instance.claimed or not instance.active or instance.definition != data):
		return false
	# A running queue owns the next dispatch; a paused one allows one-off missions.
	if from_queue != mission_queue.running or (from_queue and (automatic_repeat or data != mission_queue.next_mission())):
		return false
	if automatic_repeat and (not repeat_orders.pending_restart or repeat_orders.mission_id != data.id):
		return false
	if not automatic_repeat and not from_queue:
		repeat_orders.select_mission(data)
	var members: Array[HeroController] = party.heroes_for(ids)
	for member in members:
		member.guild_status = "ON_EXPEDITION"
	var formation: PartyFormation = _dispatch_formation(ids, automatic_repeat, from_queue)
	_apply_formation(formation)
	# Register the party first: MissionRun.start() spawns encounter 1 synchronously.
	party.begin_mission(ids, data.id, formation)
	if not mission_run.start(data, instance, ids):
		party.active_hero_ids.clear()
		party.end_mission()
		for member in members:
			recovery_for(member).arrive_at_guild()
		return false
	for member in members:
		recovery_for(member).apply_dispatch_bonus()
	if from_queue:
		mission_queue.record_dispatch(data)
	else:
		repeat_orders.record_dispatch(data, automatic_repeat, ids, formation.slots)
	expedition_ui.hide()
	_update_hero_roster()
	return true

func _on_encounter_delay_finished() -> void:
	if debug_combat_mode:
		_spawn_slime()
	else:
		mission_run.start_next_encounter()

# Gold is account-wide and paid once; equipped Gold bonuses of all participants add up.
func _gold_reward(base: int) -> int:
	var bonus_percent: float = 0.0
	for member in combat_heroes():
		bonus_percent += member.equipment.gold_bonus_percent()
	return RewardCalculator.calculate(base, bonus_percent, guild_mastery.global_gold_multiplier)

# XP uses the receiving hero's own equipment.
func _xp_reward(base: int, member: HeroController = null) -> int:
	var receiver: HeroController = member if member != null else arthur
	return RewardCalculator.calculate(base, receiver.equipment.xp_bonus_percent(), guild_mastery.global_xp_multiplier)

func _on_mission_completed() -> void:
	var fighters: Array[HeroController] = combat_heroes()
	if fighters.is_empty():
		return
	var gold_reward: int = _gold_reward(mission_run.mission.base_gold_reward)
	var xp_reward: int = _xp_reward(mission_run.mission.base_xp_reward, fighters[0])
	if not mission_run.claim_completion_reward(gold_reward, xp_reward):
		return
	if not mission_queue.awaiting_result:
		repeat_orders.record_success(mission_run.mission)
	respawn_timer.stop()
	for member in fighters:
		member.set_target(null)
	wallet.add_gold(gold_reward)
	_award_party_xp(mission_run.mission.base_xp_reward, fighters)
	if mission_run.mission.completion_loot != null:
		for item in mission_run.mission.completion_loot.roll(mission_run.completion_rng):
			_spawn_ground_loot(item, last_defeated_position)
	status_label.text = "MISSION COMPLETE! Returning to the Guild..."
	_show_floating_text("MISSION COMPLETE", fighters[0].position + Vector2(0, -200), Color(0.5, 1, 0.7), 28, 1.2)
	_return_to_guild()

func _on_mission_retreated() -> void:
	var fighters: Array[HeroController] = combat_heroes()
	var party_name: String = party.names(_ids_of(fighters))
	if repeat_orders.repeat_enabled or repeat_orders.pending_restart:
		repeat_orders.stop_for_result("RETREATED", "%s retreated due to %s." % [party_name, StopConditionEvaluator.reason_text(mission_run.stop_reason)])
	respawn_timer.stop()
	for member in fighters:
		member.set_target(null)
	status_label.text = "EXPEDITION STOPPED: %s. %s returning." % [StopConditionEvaluator.reason_text(mission_run.stop_reason), party_name]
	var anchor: Vector2 = fighters[0].position if not fighters.is_empty() else arthur.position
	_show_floating_text("EXPEDITION STOPPED\n" + StopConditionEvaluator.reason_text(mission_run.stop_reason),
		anchor + Vector2(0, -200), Color(1, 0.7, 0.3), 26, 1.2)
	_return_to_guild()

func _resolve_mission_checkpoint() -> void:
	# Pickup finishes before evaluating capacity or starting another encounter.
	while ground_loot.get_child_count() > 0:
		await get_tree().physics_frame
	var snapshots: Array = []
	for member in combat_heroes():
		snapshots.append(member.expedition_snapshot())
	mission_run.resolve_party_checkpoint(snapshots)
	if mission_run.mission_state == MissionRun.State.IN_PROGRESS:
		status_label.text = "The party regroups. Next encounter in 2 seconds..."
		# Regroup to formation so the next enemy is always approached front-first.
		for member in combat_heroes():
			member.rally_to(member.home_position)
		respawn_timer.start()

func _return_to_guild() -> void:
	if return_in_progress or mission_run.mission_state not in [MissionRun.State.COMPLETED, MissionRun.State.RETREATED]:
		return
	return_in_progress = true
	var members: Array[HeroController] = combat_heroes()
	await get_tree().create_timer(0.5).timeout
	# Defensive guard: keep earned loot even if a new visual pickup is pending.
	while ground_loot.get_child_count() > 0:
		await get_tree().physics_frame
	mission_run.begin_return()
	party.set_returning()
	for member in members:
		member.guild_status = "RETURNING"
	_update_mission_status()
	status_label.text = "%s returning to the Guild..." % party.names(_ids_of(members))
	await get_tree().create_timer(1.0).timeout
	for member in members:
		member.position = member.home_position
		member.visuals.scale.x = 1.0
		# Each hero keeps their own ending Energy; recovery happens through rest.
		recovery_for(member).arrive_at_guild()
	party.end_mission()
	return_in_progress = false
	mission_run.record_participants(members)
	mission_run.finish_return()
	hp_label.text = "No active encounter"
	# Loot pickup has finished, so the queue aggregates the complete run.
	if mission_queue.awaiting_result:
		_handle_queue_return()
		return
	var will_repeat: bool = repeat_orders.repeat_enabled and repeat_orders.pending_restart
	status_label.text = "Back at the Guild. Preparing Repeat Orders." if will_repeat else "Back at the Guild. Review the mission summary."
	expedition_ui.show_summary(will_repeat)
	if will_repeat:
		_continue_repeat_after_summary(mission_run.mission)

# Starts rest for every listed hero below READY; true if anyone is now resting.
func _rest_party(ids: Array[String]) -> bool:
	var any_resting: bool = false
	for member in party.heroes_for(ids):
		var recovery: EnergyRecovery = recovery_for(member)
		if not recovery.is_ready():
			recovery.start()
		any_resting = any_resting or recovery.recovery_enabled
	return any_resting

func _continue_repeat_after_summary(mission: MissionData) -> void:
	await get_tree().create_timer(REPEAT_SUMMARY_SECONDS).timeout
	if not repeat_orders.repeat_enabled or not repeat_orders.pending_restart or repeat_orders.mission_id != mission.id:
		expedition_ui.show_summary(false)
		return
	if not mission_run.acknowledge_summary():
		repeat_orders.stop("Repeat Orders stopped: summary could not be acknowledged.")
		return
	var ids: Array[String] = repeat_orders.party_hero_ids
	if party.all_ready(ids):
		_prepare_repeat(mission)
		return
	# Only COMPLETED runs reach here; retreats already stopped the session.
	repeat_orders.pause_for_recovery(party.names(ids))
	if repeat_orders.scheduled_rest_owned and _rest_party(ids):
		status_label.text = "Scheduled Rest: %s resting before Repeat Orders resume." % party.names(ids)
	else:
		status_label.text = repeat_orders.stop_reason + " Press REST, then dispatch manually."
	expedition_ui.show_board()

func _handle_queue_return() -> void:
	var finished_name: String = mission_run.mission.display_name
	match mission_queue.record_result(mission_run, party.names(mission_queue.party_hero_ids)):
		MissionQueueState.Outcome.NEXT:
			status_label.text = "Expedition Orders: %s complete. Next: %s" % [finished_name, mission_queue.next_mission().display_name]
			expedition_ui.show_summary(true)
			await get_tree().create_timer(QUEUE_RESULT_SECONDS).timeout
			if not mission_queue.running:
				expedition_ui.show_summary(false) # Stopped during the brief result.
				return
			if not mission_run.acknowledge_summary():
				return
			_queue_rest_or_prepare()
		MissionQueueState.Outcome.FINISHED:
			status_label.text = "EXPEDITION ORDERS COMPLETE"
			expedition_ui.show_queue_summary()
		MissionQueueState.Outcome.PAUSED:
			status_label.text = "QUEUE PAUSED: " + mission_queue.pause_reason
			expedition_ui.show_summary(false)
		MissionQueueState.Outcome.STOPPED:
			status_label.text = mission_queue.stop_reason
			expedition_ui.show_summary(false)

# Reuses Scheduled Rest (a Mission Queue prerequisite) between orders.
func _queue_rest_or_prepare() -> void:
	if not mission_queue.running:
		return
	var ids: Array[String] = mission_queue.party_hero_ids
	if party.all_ready(ids):
		_prepare_queue_next()
		return
	_rest_party(ids)
	status_label.text = "Expedition Orders: %s resting. Next: %s" % [party.names(ids), mission_queue.next_mission().display_name]
	expedition_ui.show_board()

func _prepare_queue_next() -> void:
	if queue_preparing:
		return
	queue_preparing = true
	expedition_ui.hide()
	status_label.text = "Party READY. Preparing %s..." % mission_queue.next_mission().display_name
	await get_tree().create_timer(REPEAT_PREPARATION_SECONDS).timeout
	queue_preparing = false
	if not mission_run.can_start():
		return
	if not mission_queue.running:
		expedition_ui.show_board()
		return
	if not party.all_ready(mission_queue.party_hero_ids):
		# Rest was stopped; the next ready_reached continues the queue.
		status_label.text = "Expedition Orders waiting: the party needs to rest."
		expedition_ui.show_board()
		return
	if not start_mission(mission_queue.next_mission(), null, false, true):
		mission_queue.pause("The next order could not be dispatched.")
		status_label.text = "QUEUE PAUSED: " + mission_queue.pause_reason
		expedition_ui.show_board()

func start_queue() -> bool:
	var ids: Array[String] = party.hero_ids.duplicate()
	if not mission_queue.can_start() or not mission_run.can_start() or not party.dispatch_reason(ids).is_empty():
		return false
	# The queue owns dispatch; end any Repeat Orders session first.
	if repeat_orders.repeat_enabled or repeat_orders.pending_restart:
		repeat_orders.reset()
	var mission: MissionData = mission_queue.start(ids, party.formation_for(ids).slots)
	if not start_mission(mission, null, false, true):
		mission_queue.stop("Expedition Orders could not start.")
		return false
	status_label.text = "Expedition Orders started: %s (%s)" % [mission.display_name, party.names(ids)]
	return true

func resume_queue() -> bool:
	if not mission_queue.paused or not mission_run.can_start():
		return false
	var mission: MissionData = mission_queue.resume()
	if party.any_resting(mission_queue.party_hero_ids):
		status_label.text = "Expedition Orders resume when the party is READY."
		expedition_ui.refresh()
		return true
	if not start_mission(mission, null, false, true):
		mission_queue.pause("Resume failed: %s could not be dispatched." % mission.display_name)
		return false
	return true

func stop_queue() -> void:
	if not mission_queue.enabled:
		return
	if mission_queue.awaiting_result:
		# Never cancels combat: the current mission finishes normally.
		mission_queue.request_stop()
		status_label.text = "Expedition Orders will stop after the current mission."
	else:
		mission_queue.stop("Expedition Orders stopped by player.")
		status_label.text = mission_queue.stop_reason
		if mission_run.can_start():
			expedition_ui.show_board()

func _update_queue_status() -> void:
	if debug_combat_mode or mission_queue == null or party == null:
		return
	stop_queue_button.visible = mission_queue.enabled and not mission_queue.stop_requested
	var text: String = ""
	if mission_queue.enabled:
		var ids: Array[String] = mission_queue.party_hero_ids
		text = "EXPEDITION ORDERS | Queue: %s | Party: %s" % [mission_queue.progress_text(), party.names(ids)]
		if mission_queue.paused:
			text += "\nQUEUE PAUSED: " + mission_queue.pause_reason
		elif mission_queue.stop_requested:
			text += "\nStopping after the current mission."
		elif not mission_queue.awaiting_result and mission_queue.next_mission() != null:
			text += "\n%s | Next Mission: %s" % ["Resting" if party.any_resting(ids) else "At Guild", mission_queue.next_mission().display_name]
	elif mission_queue.finished:
		text = "EXPEDITION ORDERS COMPLETE: %s missions" % mission_queue.progress_text()
	elif not mission_queue.stop_reason.is_empty():
		text = mission_queue.stop_reason
	queue_status_label.text = text
	queue_status_label.visible = not text.is_empty()

# Any hero reaching READY re-checks automation; it continues only once the
# whole remembered party is READY.
func _on_recovery_ready() -> void:
	if mission_queue.running and not mission_queue.awaiting_result and mission_run.can_start():
		if party.all_ready(mission_queue.party_hero_ids):
			_prepare_queue_next()
		else:
			status_label.text = "Expedition Orders: waiting for the whole party to be READY."
		return
	if not (repeat_orders.repeat_enabled and repeat_orders.pending_restart and repeat_orders.paused_for_recovery):
		status_label.text = "READY: " + party.names(_ready_ids())
		return
	var ids: Array[String] = repeat_orders.party_hero_ids
	if not party.all_ready(ids):
		status_label.text = "Waiting for the whole party (%s) to be READY." % party.names(ids)
		return
	if repeat_orders.scheduled_rest_owned and mission_run.mission != null and mission_run.mission.id == repeat_orders.mission_id:
		_prepare_repeat(mission_run.mission)
	else:
		status_label.text = "%s READY. Repeat Orders remains paused until you dispatch manually." % party.names(ids)

func _ready_ids() -> Array[String]:
	var ids: Array[String] = []
	for member in heroes:
		if recovery_for(member).is_ready() and member.guild_status == "READY":
			ids.append(member.hero_id)
	return ids

func _prepare_repeat(mission: MissionData) -> void:
	if repeat_preparing:
		return
	repeat_preparing = true
	repeat_orders.resume_from_recovery()
	expedition_ui.hide()
	status_label.text = "%s READY. Preparing %s..." % [party.names(repeat_orders.party_hero_ids), mission.display_name]
	await get_tree().create_timer(REPEAT_PREPARATION_SECONDS).timeout
	repeat_preparing = false
	if not mission_run.can_start():
		return # The player already dispatched manually.
	if not repeat_orders.repeat_enabled or not repeat_orders.pending_restart or repeat_orders.mission_id != mission.id:
		status_label.text = "Repeat Orders stopped. Choose a mission manually."
		expedition_ui.show_board()
		return
	if not party.all_ready(repeat_orders.party_hero_ids) or not start_mission(mission, null, true):
		repeat_orders.stop("Repeat Orders stopped: mission restart was unavailable.")
		status_label.text = repeat_orders.stop_reason
		expedition_ui.show_board()

func _stop_repeat_after_current() -> void:
	if not repeat_orders.repeat_enabled and not repeat_orders.pending_restart:
		return
	var summary_visible: bool = mission_run.summary_pending and mission_run.mission_state == MissionRun.State.IDLE
	repeat_orders.stop("Repeat Orders stopped by player after the current mission.")
	status_label.text = repeat_orders.stop_reason
	if summary_visible:
		expedition_ui.show_summary(false)

func _on_summary_continue() -> void:
	if mission_run.acknowledge_summary():
		status_label.text = "Choose the next mission manually."
		expedition_ui.show_board()

func _update_mission_status() -> void:
	if debug_combat_mode:
		return
	_update_arthur_stats()
	board_button.disabled = not mission_run.can_start()
	if mission_run.mission == null:
		mission_label.text = ""
	else:
		mission_label.text = "Mission: %s | Encounter %d / %d | %s" % [
			mission_run.mission.display_name, mission_run.current_encounter,
			mission_run.total_encounters, MissionRun.State.keys()[mission_run.mission_state]]
		if mission_run.mission_state != MissionRun.State.IDLE:
			mission_label.text += "\nParty: " + formation_text(party.formation)
	_update_repeat_status()
	_update_queue_status()
	_update_hero_roster()

# "Arthur - FRONTLINE [FRONT] | Mimi - MAGE [BACK]"
func formation_text(formation: PartyFormation) -> String:
	var parts: Array[String] = []
	for hero_id in formation.slots:
		var member: HeroController = party.hero(hero_id)
		if member != null:
			parts.append("%s - %s [%s]" % [member.display_name, member.hero_data.combat_role, formation.row_of(hero_id)])
	return " | ".join(parts)

func _update_repeat_status() -> void:
	if debug_combat_mode or party == null:
		return
	stop_repeat_button.visible = repeat_orders.repeat_enabled
	if repeat_orders.repeat_enabled:
		repeat_status_label.text = "Automation: REPEAT ORDERS | Mission: %s | Repeat Run: %d" % [
			repeat_orders.mission_id.replace("_", " ").capitalize(), repeat_orders.repeat_run_count]
		if not repeat_orders.party_hero_ids.is_empty():
			repeat_status_label.text += " | Party: " + party.names(repeat_orders.party_hero_ids)
		if repeat_orders.paused_for_recovery:
			var auto_resume: bool = repeat_orders.scheduled_rest_owned and party.any_resting(repeat_orders.party_hero_ids)
			repeat_status_label.text += "\n" + ("Scheduled Rest: recovering, resumes when READY" if auto_resume
				else repeat_orders.stop_reason)
		repeat_status_label.show()
	elif not repeat_orders.stop_reason.is_empty():
		repeat_status_label.text = repeat_orders.stop_reason
		repeat_status_label.show()
	else:
		repeat_status_label.hide()

func start_opportunity(instance: MissionInstance) -> bool:
	if debug_combat_mode or not mission_run.can_start() or not board_rotation.can_claim(instance):
		return false
	# Special missions stay manual and never interrupt running Expedition Orders.
	if mission_queue.running or not party.dispatch_reason(party.hero_ids).is_empty():
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
