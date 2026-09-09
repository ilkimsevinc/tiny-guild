# Run with --headless for logic/UI-signal checks; omit it to exercise rendered mouse input.
extends SceneTree

const MAIN_SCENE = preload("res://scenes/main.tscn")
const ITEMS = preload("res://scripts/loot_table.gd").ITEMS
var failures: int = 0
var main: Node2D
var attack_times: Array[int] = []
var attack_values: Array[int] = []


func _initialize() -> void:
	run_check.call_deferred()


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)


func wait_for(predicate: Callable, seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			check(false, "Timed out waiting for combat")
			quit(1)
			return false
		await process_frame
	return true


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


func select_skill(node_id: String) -> void:
	await press(main.skill_ui.node_buttons[node_id])


func capture(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + file_name + ".png")


func on_attack(_target: Node2D, damage: int) -> void:
	attack_times.append(Time.get_ticks_msec())
	attack_values.append(damage)


func run_check() -> void:
	var wallet := GoldWallet.new()
	var skills := SkillTree.new()
	check(skills.load_class("knight") and skills.tree.class_id == "knight", "Class ID loads the Knight resource")
	check(not skills.load_class("missing_class") and skills.tree.class_id == "knight", "Unknown class cannot replace loaded tree")
	check(skills.node_state("battle_training") == "AVAILABLE"
		and skills.node_state("iron_body") == "LOCKED", "Only the root is initially available")
	check(not skills.purchase("battle_training", wallet) and wallet.balance == 0
		and skills.unlocked_ids.is_empty(), "Insufficient funds do not spend or unlock")
	wallet.add_gold(500)
	check(not skills.purchase("iron_body", wallet) and wallet.balance == 500, "D: Iron Body requires Battle Training")
	check(not skills.purchase("unknown", wallet) and wallet.balance == 500, "Unknown node cannot spend Gold")
	check(skills.can_purchase("battle_training", wallet.balance), "A: Battle Training is purchasable with enough Gold")
	check(skills.purchase("battle_training", wallet) and wallet.balance == 450, "C: Purchase deducts exactly 50 Gold")
	check(not skills.purchase("battle_training", wallet) and wallet.balance == 450, "B: Duplicate purchase does not spend")
	check(skills.can_purchase("iron_body", wallet.balance), "E: Iron Body unlocks after Battle Training")
	check(skills.can_purchase("quick_strikes", wallet.balance), "F: Quick Strikes unlocks after Battle Training")
	check(skills.purchase("iron_body", wallet) and wallet.balance == 350, "Iron Body costs 100 Gold")
	check(not skills.purchase("veteran", wallet) and wallet.balance == 350, "G: Iron Body alone does not unlock Veteran")
	skills.purchase("quick_strikes", wallet)
	check(skills.purchase("veteran", wallet) and wallet.balance == 0, "G: Both prerequisites allow Veteran for 250 Gold")
	check(skills.attack_bonus() == 5 and skills.max_hp_bonus() == 40
		and skills.attack_speed_percent() == 10, "K: Full tree totals are +5 Attack, +40 HP, +10% speed")
	var second := SkillTree.new()
	second.load_class("knight")
	check(second.unlocked_ids.is_empty() and second.tree == skills.tree,
		"Class Resources are shared while controller state is independent")
	wallet.add_gold(500)
	second.purchase("battle_training", wallet)
	second.purchase("quick_strikes", wallet)
	check(not second.purchase("veteran", wallet), "G: Quick Strikes alone does not unlock Veteran")
	second.free()
	skills.free()
	# A synthetic class verifies that controller logic has no Knight/Arthur branches.
	var generic := SkillTree.new()
	generic.tree = SkillTreeData.new()
	generic.tree.class_id = "test_class"
	var node := SkillNodeData.new()
	node.id = "test_training"
	node.class_id = "test_class"
	node.gold_cost = 5
	node.effect_value = {"attack": 4.0}
	generic.tree.nodes.append(node)
	check(generic.purchase(node.id, wallet) and generic.attack_bonus() == 4,
		"Generic controller purchases another class's data without code changes")
	generic.free()
	wallet.free()

	main = MAIN_SCENE.instantiate()
	main.debug_combat_mode = true # Explicit legacy combat regression mode.
	root.add_child(main)
	main.arthur.set_physics_process(false)
	var sidebar: TabContainer = main.get_node("UI/Sidebar")
	await process_frame
	if DisplayServer.get_name() == "headless":
		sidebar.current_tab = 1
		await process_frame
	else:
		var tabs: TabBar = sidebar.get_tab_bar()
		await click_at(tabs.global_position + tabs.get_tab_rect(1).get_center())
	check(main.skill_ui.is_visible_in_tree(), "UI opens Knight Skill Tree tab")
	await select_skill("battle_training")
	check(main.skill_ui.buy_button.disabled and main.skill_ui.reason_label.text == "Not enough Gold",
		"UI distinguishes available node from affordability")
	await select_skill("iron_body")
	check(main.skill_ui.buy_button.disabled and main.skill_ui.reason_label.text.contains("Battle Training"),
		"UI explains missing prerequisite")
	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.pressed = true
	main._unhandled_key_input(key)
	check(main.gold == 500 and main.gold_label.text == "Gold: 500", "Debug F10 grants 500 Gold and refreshes UI")
	await capture("m6-locked")
	await select_skill("battle_training")
	await press(main.skill_ui.buy_button)
	check(main.gold == 450 and main.arthur.total_attack() == 12
		and main.arthur.progression.damage == 10, "H/M: UI purchase adds exactly 2 Attack without altering base")
	check(main.gold_label.text == "Gold: 450" and main.arthur_label.text.contains("Damage: 12"),
		"Gold and total Attack refresh immediately")
	check(main.skill_ui.buy_button.disabled and main.skill_ui.reason_label.text == "Already learned", "Owned node cannot be bought in UI")
	await select_skill("iron_body")
	await press(main.skill_ui.buy_button)
	check(main.gold == 350 and main.arthur.total_max_hp() == 120
		and main.arthur.progression.current_hp == 120 and main.arthur.progression.max_hp == 100,
		"I/M: Iron Body adds 20 max/current HP without altering base")
	await select_skill("veteran")
	check(main.skill_ui.buy_button.disabled and main.skill_ui.reason_label.text.contains("Quick Strikes"),
		"UI requires second Veteran prerequisite")
	await select_skill("quick_strikes")
	await press(main.skill_ui.buy_button)
	check(main.gold == 250 and is_equal_approx(main.arthur.attack_interval(), 1.0 / 1.1)
		and is_equal_approx(main.arthur.attack_timer.wait_time, 1.0 / 1.1), "J: Quick Strikes updates calculated and actual timer interval")
	check(main.attack_interval_label.text == "Attack interval: 0.91 s", "Attack-speed UI refreshes")
	await select_skill("veteran")
	await press(main.skill_ui.buy_button)
	check(main.gold == 0 and main.arthur.total_attack() == 15 and main.arthur.total_max_hp() == 140
		and main.arthur.progression.current_hp == 140, "K: Veteran adds exactly 3 Attack and 20 HP")
	await capture("m6-owned")
	for index in range(1, 5):
		main.inventory.add_item(ITEMS[index])
		main.arthur.equipment.equip(main.inventory, ITEMS[index].id)
	check(main.arthur.total_attack() == 18 and main.arthur.total_max_hp() == 150, "L: Equipment and skills combine")
	main.arthur.equipment.unequip(main.inventory, 0)
	check(main.inventory.quantity("rusty_sword") == 1 and main.arthur.total_attack() == 16,
		"O: Unequip returns the sword without removing skill bonuses")
	main.arthur.equipment.equip(main.inventory, "rusty_sword")
	main.arthur.progression.current_hp = 60
	main.arthur.equipment.unequip(main.inventory, 1)
	check(main.arthur.progression.current_hp == 60 and main.arthur.total_max_hp() == 140,
		"HP gear removal preserves valid injured HP with skills")
	main.arthur.equipment.equip(main.inventory, "old_shield")
	check(main.arthur.progression.current_hp == 70, "Positive max-HP bonus adds the same amount to injured HP")
	main.arthur.attacked.connect(on_attack)
	main.arthur.set_physics_process(true)
	if not await wait_for(func(): return main.gold == 11):
		return
	check(main.arthur.progression.xp == 17 and attack_values == [18, 18],
		"P: Skill combat preserves equipment Gold/XP rewards and uses total Attack")
	check(absf(float(attack_times[1] - attack_times[0]) / 1000.0 - 1.0 / 1.1) < 0.08,
		"J: Measured attack cadence is approximately 0.91 seconds")
	if not await wait_for(func(): return main.gold == 22):
		return
	check(main.arthur.progression.level == 2 and main.arthur.progression.damage == 12
		and main.arthur.progression.max_hp == 110 and main.arthur.total_attack() == 20
		and main.arthur.total_max_hp() == 160 and main.arthur.progression.current_hp == 160,
		"N: Level-up preserves separate bonuses and heals to total Max HP")
	check(main.arthur.progression.xp == 4, "Modified XP still carries overflow")
	await capture("m6-combat")
	print("Milestone 6 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)