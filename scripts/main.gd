extends Node2D

const SLIME_SCENE = preload("res://scenes/slime.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const GOLD_PER_SLIME: int = 10
const XP_PER_SLIME: int = 15
const PICKUP_RANGE: float = 36.0
const GROUND_LOOT_SCENE = preload("res://scenes/ground_loot.tscn")
const LOOT_TABLE = preload("res://scripts/loot_table.gd")
const DEBUG_HINT: String = "DEBUG: F6 = next Rare | F7 = next Epic | F9 = test items | F10 = +500 Gold | F11 = +1000 Gold | F12 = +10 Tokens"

var loot_table = LOOT_TABLE.new()
# Development only: F6/F7 override one kill, then normal rates resume.
var debug_next_drop: ItemData

# The wallet owns the balance; this read-only view keeps game queries simple.
var gold: int:
	get:
		return wallet.balance
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
	status_label.text = "Arthur approaches the Slime and attacks automatically in melee range."
	arthur.set_target(slime)


func _on_arthur_attacked(target: Node2D, damage: int) -> void:
	if is_instance_valid(slime) and target == slime and arthur.is_target_in_range():
		status_label.text = "Arthur hits the Slime for %d damage!" % damage
		slime.take_damage(damage)


func _on_arthur_state_changed(state_name: String) -> void:
	state_label.text = "Arthur: " + state_name


func _on_slime_damaged(amount: int) -> void:
	_show_floating_text("-%d" % amount, slime.position + Vector2(0, -100), Color.WHITE)


func _show_floating_text(message: String, effect_position: Vector2, text_color: Color, font_size: int = 24, duration: float = 0.8) -> void:
	var effect = FLOATING_TEXT_SCENE.instantiate()
	add_child(effect)
	effect.position = effect_position
	effect.play(message, text_color, font_size, duration)


func _update_slime_hp(current_hp: int) -> void:
	hp_label.text = "Slime HP: %d / 30" % current_hp


func _on_slime_died() -> void:
	var defeated_position: Vector2 = slime.position
	# Resolve death immediately; the Slime's visual finishes independently.
	slime = null
	arthur.set_target(null)
	var gold_reward: int = RewardCalculator.calculate(GOLD_PER_SLIME, arthur.equipment.gold_bonus_percent(), guild_mastery.global_gold_multiplier)
	var xp_reward: int = RewardCalculator.calculate(XP_PER_SLIME, arthur.equipment.xp_bonus_percent(), guild_mastery.global_xp_multiplier)
	wallet.add_gold(gold_reward)
	arthur.progression.add_xp(xp_reward)
	gold_label.text = "Gold: %d" % gold
	status_label.text = "Slime defeated! +%d Gold, +%d XP. Next Slime in 2 seconds..." % [gold_reward, xp_reward]
	respawn_timer.start()
	_show_floating_text("+%d Gold" % gold_reward, defeated_position + Vector2(0, -65), Color(1, 0.82, 0.35))
	var drop: ItemData = loot_table.roll()
	if OS.is_debug_build() and debug_next_drop != null:
		drop = debug_next_drop
		debug_next_drop = null
		loot_debug_label.text = DEBUG_HINT
	if drop != null:
		_spawn_ground_loot(drop, defeated_position)

func _update_arthur_stats() -> void:
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
