extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const ITEMS = preload("res://scripts/loot_table.gd").ITEMS
var failures: int = 0
var main: Node2D

func _initialize() -> void:
	run_check.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)

func click_at(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
	await process_frame

func press(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		if not button.disabled:
			button.pressed.emit()
		await process_frame
	else:
		await click_at(button.get_global_rect().get_center())

func select_mastery(node_id: String) -> void:
	var button: Button = main.mastery_ui.node_buttons[node_id]
	main.mastery_ui.scroll.ensure_control_visible(button)
	await process_frame
	await press(button)

func wait_for_gold(amount: int) -> bool:
	var deadline: int = Time.get_ticks_msec() + 15000
	while main.gold < amount:
		if Time.get_ticks_msec() > deadline:
			check(false, "Combat timed out")
			return false
		await process_frame
	return true

func run_check() -> void:
	var state := GuildMasteryState.new()
	var wallet := GoldWallet.new()
	check(state.unlocked_ids.is_empty() and wallet.guild_tokens == 0, "A: Empty mastery and zero Tokens")
	check(state.node_state("coin_pouch_1") == "AVAILABLE", "B: Coin Pouch I available")
	check(state.node_state("coin_pouch_2") == "LOCKED", "C: Coin Pouch II locked")
	check(not state.purchase("coin_pouch_1", wallet) and wallet.balance == 0, "Insufficient Gold cannot spend or unlock")
	check(RewardCalculator.calculate(10, 0, state.global_gold_multiplier) == 10
		and RewardCalculator.calculate(15, 0, state.global_xp_multiplier) == 15, "Baseline rewards unchanged")
	wallet.add_gold(1000)
	check(not state.purchase("coin_pouch_2", wallet) and wallet.balance == 1000, "Prerequisite rejects purchase even with funds")
	check(state.purchase("coin_pouch_1", wallet) and wallet.balance == 900, "D: Exactly 100 Gold spent")
	check(not state.purchase("coin_pouch_1", wallet) and wallet.balance == 900, "E: No duplicate purchase")
	check(state.node_state("coin_pouch_2") == "AVAILABLE", "F: Coin Pouch II available afterward")
	check(state.node_state("shared_experience_1") == "AVAILABLE" and state.global_xp_multiplier == 1.0,
		"G: Training independent of Economy")
	check(RewardCalculator.calculate(10, 0, state.global_gold_multiplier) == 11, "H: 10.5 Gold rounds to 11")
	state.purchase("coin_pouch_2", wallet)
	check(is_equal_approx(state.global_gold_multiplier, 1.1)
		and RewardCalculator.calculate(10, 0, state.global_gold_multiplier) == 11, "J: Gold bonuses add to 10 percent")
	state.purchase("shared_experience_1", wallet)
	check(RewardCalculator.calculate(15, 0, state.global_xp_multiplier) == 16, "I: 15.75 XP rounds to 16")
	state.purchase("shared_experience_2", wallet)
	check(wallet.balance == 150 and is_equal_approx(state.global_xp_multiplier, 1.1)
		and RewardCalculator.calculate(15, 0, state.global_xp_multiplier) == 17, "K: XP bonuses add to 10 percent; 16.5 rounds up")
	check(RewardCalculator.calculate(10, 5, state.global_gold_multiplier) == 12, "L: Ring and Guild yield 12 Gold")
	check(RewardCalculator.calculate(15, 10, state.global_xp_multiplier) == 18, "M: Crown and Guild yield 18 XP; no intermediate rounding")
	wallet.add_gold(10000)
	for node_id in ["trail_knowledge", "repeat_orders", "notice_board", "sleeping_guild"]:
		check(state.node_state(node_id) == "NOT YET IMPLEMENTED" and not state.purchase(node_id, wallet)
			and wallet.balance == 10150 and not state.owns(node_id), "N: Disabled " + node_id + " cannot spend or unlock")
	check(not state.has_unlock_tag("repeat_expedition") and not state.has_unlock_tag("offline_progression"), "Future tags inactive")
	var skills := SkillTree.new()
	skills.load_class("knight")
	check(skills.unlocked_ids.is_empty() and skills.attack_bonus() == 0, "Q: Guild purchases do not unlock class skills")
	skills.purchase("battle_training", wallet)
	check(state.unlocked_ids.size() == 4 and is_equal_approx(state.global_gold_multiplier, 1.1)
		and skills.attack_bonus() == 2, "Q: Class purchase leaves Guild state and bonuses unchanged")
	skills.free()
	state.free()
	wallet.free()

	# Synthetic node exists only in this test, never in the playable tree.
	state = GuildMasteryState.new()
	state.tree = GuildMasteryTreeData.new()
	var token_node := MasteryNodeData.new()
	token_node.id = "test_token_purchase"
	token_node.implemented = true
	token_node.gold_cost = 5000
	token_node.guild_token_cost = 1
	state.tree.nodes.append(token_node)
	wallet = GoldWallet.new()
	wallet.add_gold(5000)
	check(not state.purchase(token_node.id, wallet) and wallet.balance == 5000 and wallet.guild_tokens == 0
		and state.unlocked_ids.is_empty(), "O: Missing Token leaves Gold and ownership unchanged")
	wallet.add_guild_tokens(1)
	var observed: Array[Vector2i] = []
	wallet.changed.connect(func(): observed.append(Vector2i(wallet.balance, wallet.guild_tokens)))
	check(state.purchase(token_node.id, wallet) and wallet.balance == 0 and wallet.guild_tokens == 0,
		"P: Funded dual-currency purchase spends both exact costs")
	check(observed == [Vector2i.ZERO], "Currency observers receive one atomic deduction")
	check(not state.purchase(token_node.id, wallet), "Token purchase cannot repeat")
	state.free()
	wallet.free()

	main = MAIN.instantiate()
	root.add_child(main)
	main.arthur.set_physics_process(false)
	await process_frame
	var sidebar: TabContainer = main.get_node("UI/Sidebar")
	if DisplayServer.get_name() == "headless":
		sidebar.current_tab = 2
		await process_frame
	else:
		var tabs := sidebar.get_tab_bar()
		await click_at(tabs.global_position + tabs.get_tab_rect(2).get_center())
	check(main.mastery_ui.is_visible_in_tree(), "UI: Separate Guild Mastery tab opens")
	await select_mastery("coin_pouch_1")
	check(main.mastery_ui.buy_button.disabled and main.mastery_ui.reason.text == "Not enough Gold", "UI: Insufficient Gold explained")
	await select_mastery("coin_pouch_2")
	check(main.mastery_ui.buy_button.disabled and main.mastery_ui.reason.text.contains("Coin Pouch I"), "UI: Prerequisite explained")
	for keycode in [KEY_F11, KEY_F12]:
		var key := InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		main._unhandled_key_input(key)
	check(main.gold == 1000 and main.wallet.guild_tokens == 10
		and main.mastery_ui.currencies.text.contains("Guild Tokens: 10"), "Debug shortcuts and currency UI work")
	for node_id in ["coin_pouch_1", "coin_pouch_2", "shared_experience_1", "shared_experience_2"]:
		await select_mastery(node_id)
		await press(main.mastery_ui.buy_button)
		check(main.guild_mastery.owns(node_id) and main.mastery_ui.buy_button.disabled, "UI: Purchase and owned state " + node_id)
	check(main.gold == 150 and main.arthur.total_attack() == 10 and main.arthur.skills.unlocked_ids.is_empty(),
		"UI purchases deduct 850 Gold without changing Arthur's class stats")
	await select_mastery("sleeping_guild")
	check(main.mastery_ui.buy_button.disabled and main.mastery_ui.reason.text == "System not available"
		and main.mastery_ui.details.text.contains("3000 Gold + 0 Guild Tokens"), "UI: Future effects and costs inspectable but purchase disabled")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m7-future.png")
	for index in [3, 4]:
		main.inventory.add_item(ITEMS[index])
		main.arthur.equipment.equip(main.inventory, ITEMS[index].id)
	main.arthur.set_physics_process(true)
	if await wait_for_gold(162):
		check(main.gold == 162 and main.arthur.progression.xp == 18 and main.wallet.guild_tokens == 10,
			"Live kill: exactly 12 Gold, 18 XP, zero Tokens; modifiers applied once")
	if await wait_for_gold(174):
		check(main.gold == 174 and main.arthur.progression.level == 2 and main.arthur.progression.xp == 6,
			"Live respawn/combat: modified XP levels up with overflow")
	await select_mastery("coin_pouch_2")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/m7-owned.png")
	print("Milestone 7 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
