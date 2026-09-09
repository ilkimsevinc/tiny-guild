# Run: godot --headless --path . --script res://tests/milestone5_check.gd
extends SceneTree

const ITEMS = preload("res://scripts/loot_table.gd").ITEMS
const MAIN_SCENE = preload("res://scenes/main.tscn")
var failures: int = 0
var main: Node2D
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


func capture(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + file_name + ".png")


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


func select_inventory_item(item_id: String) -> void:
	var list: ItemList = main.inventory_ui.inventory_list
	for index in range(list.item_count):
		if list.get_item_metadata(index) == item_id:
			if DisplayServer.get_name() == "headless":
				# Item rectangles are populated by drawing; headless mode tests UI signals.
				list.select(index)
				list.item_selected.emit(index)
			else:
				await click_at(list.global_position + list.get_item_rect(index).get_center())
			return
	check(false, "Missing UI item " + item_id)


func run_check() -> void:
	var inventory := Inventory.new()
	var equipment := Equipment.new()
	check(inventory.add_item(ITEMS[0], 3) and inventory.quantity("slime_gel") == 3, "A: Add stacks quantity")
	check(inventory.get_item("slime_gel") == ITEMS[0], "Inventory preserves ItemData reference")
	check(inventory.remove_item("slime_gel", 2) and inventory.quantity("slime_gel") == 1, "B: Remove decreases quantity")
	check(not inventory.remove_item("slime_gel", 2) and inventory.quantity("slime_gel") == 1, "Insufficient removal leaves inventory intact")
	check(not inventory.add_item(ITEMS[0], 0) and not inventory.remove_item("slime_gel", -1), "Invalid quantities rejected")
	check(not equipment.equip(inventory, "slime_gel") and inventory.quantity("slime_gel") == 1, "G: Materials cannot be equipped")
	for item_index in range(1, 5):
		var item: ItemData = ITEMS[item_index]
		inventory.add_item(item, 2)
		for slot in range(4):
			if slot != item_index - 1:
				check(not equipment.equip(inventory, item.id, slot), "Wrong slot rejects " + item.display_name)
		check(equipment.equip(inventory, item.id, item_index - 1)
			and equipment.get_item(item_index - 1) == item and inventory.quantity(item.id) == 1,
			"C-F: Correct slot consumes one " + item.display_name)
	check(equipment.gold_reward(10) == 11 and equipment.xp_reward(15) == 17, "L/M: Reward bonuses round halves up")
	check(equipment.gold_reward(1) == 1 and equipment.gold_reward(0) == 0, "Reward rounding works below a half")
	var replacement: ItemData = ITEMS[1].duplicate()
	replacement.id = "test_sword"
	replacement.attack_bonus = 4
	inventory.add_item(replacement)
	check(equipment.equip(inventory, replacement.id) and equipment.get_item(0) == replacement
		and inventory.quantity("rusty_sword") == 2 and inventory.quantity("test_sword") == 0,
		"K: Replacement returns old item and consumes new one")
	check(not equipment.equip(inventory, "missing") and equipment.get_item(0) == replacement, "Missing item cannot replace equipped gear")
	check(equipment.unequip(inventory, 0) and inventory.quantity("test_sword") == 1, "Unequip returns item")
	check(not equipment.unequip(inventory, 0), "Empty slot cannot duplicate items")
	inventory.free()
	equipment.free()

	main = MAIN_SCENE.instantiate()
	main.debug_combat_mode = true # Explicit legacy combat regression mode.
	root.add_child(main)
	main.arthur.set_physics_process(false)
	var arthur = main.arthur
	inventory = main.inventory
	equipment = arthur.equipment
	var stats = arthur.progression
	inventory.add_item(ITEMS[1])
	equipment.equip(inventory, "rusty_sword")
	check(arthur.total_attack() == 12 and stats.damage == 10, "H: Sword adds 2 total Attack without mutating base")
	equipment.unequip(inventory, 0)
	check(arthur.total_attack() == 10 and inventory.quantity("rusty_sword") == 1, "I: Unequip restores Attack")
	inventory.add_item(ITEMS[2])
	stats.current_hp = 60
	equipment.equip(inventory, "old_shield")
	check(arthur.total_max_hp() == 110 and stats.max_hp == 100 and stats.current_hp == 70, "J: Shield adds max and current HP without altering base")
	equipment.unequip(inventory, 1)
	check(stats.current_hp == 70 and arthur.total_max_hp() == 100, "Removing HP gear preserves injured HP below cap")
	equipment.equip(inventory, "old_shield")
	stats.current_hp = 110
	equipment.unequip(inventory, 1)
	check(stats.current_hp == 100, "Unequip clamps HP to new max")
	equipment.equip(inventory, "old_shield")
	equipment.equip(inventory, "rusty_sword")
	stats.current_hp = 1
	stats.add_xp(30)
	check(stats.level == 2 and stats.damage == 12 and stats.max_hp == 110
		and arthur.total_attack() == 14 and arthur.total_max_hp() == 120 and stats.current_hp == 120,
		"N: Level-up with gear keeps base growth separate and heals to total max")
	equipment.unequip(inventory, 0)
	equipment.unequip(inventory, 1)
	check(stats.current_hp == 110 and arthur.total_attack() == 12, "Level-up base growth survives unequip")
	main._spawn_ground_loot(ITEMS[0], arthur.position)
	await physics_frame
	await process_frame
	check(inventory.quantity("slime_gel") == 1, "O: Automatic loot pickup enters Inventory")
	main.queue_free()
	await process_frame

	# Exercise the real controls through viewport mouse input, with combat paused.
	main = MAIN_SCENE.instantiate()
	main.debug_combat_mode = true # Explicit legacy combat regression mode.
	root.add_child(main)
	main.arthur.set_physics_process(false)
	var key := InputEventKey.new()
	key.keycode = KEY_F9
	key.pressed = true
	main._unhandled_key_input(key)
	check(main.inventory.get_items().size() == 5, "Debug F9 grants test items")
	await process_frame
	await select_inventory_item("slime_gel")
	check(main.inventory_ui.equip_button.disabled
		and main.inventory_ui.details.text.contains("sticky alchemical"), "UI shows material details and disables Equip")
	for index in range(1, 5):
		await select_inventory_item(ITEMS[index].id)
		check(not main.inventory_ui.equip_button.disabled
			and main.inventory_ui.details.text.contains(ITEMS[index].bonus_description()), "UI shows bonuses and enables Equip")
		await press_button(main.inventory_ui.equip_button)
		check(main.arthur.equipment.get_item(index - 1) == ITEMS[index], "UI equips " + ITEMS[index].display_name)
	check(main.arthur.total_attack() == 13 and main.arthur.total_max_hp() == 110, "All equipped bonuses combine")
	check(main.arthur_label.text.contains("Damage: 13") and main.arthur_label.text.contains("110 / 110"), "Total stats update on screen")
	await capture("m5-all-equipped")
	var list: ItemList = main.inventory_ui.equipment_list
	if DisplayServer.get_name() == "headless":
		list.select(0)
		list.item_selected.emit(0)
	else:
		await click_at(list.global_position + list.get_item_rect(0).get_center())
	check(not main.inventory_ui.unequip_button.disabled, "Selecting equipment enables Unequip")
	await press_button(main.inventory_ui.unequip_button)
	check(main.inventory.quantity("rusty_sword") == 1 and main.arthur.total_attack() == 11, "UI Unequip returns sword and updates Attack")
	await select_inventory_item("rusty_sword")
	await press_button(main.inventory_ui.equip_button)
	main.inventory.add_item(ITEMS[1])
	await select_inventory_item("rusty_sword")
	await press_button(main.inventory_ui.equip_button)
	check(main.inventory.quantity("rusty_sword") == 1 and main.arthur.total_attack() == 13, "UI replacement preserves quantity and avoids bonus stacking")
	await capture("m5-inventory-details")

	# Resume real timed combat with all four items equipped.
	main.arthur.attacked.connect(func(_target, damage): attack_values.append(damage))
	main.arthur.set_physics_process(true)
	if not await wait_for(func(): return main.gold >= 11):
		return
	check(main.gold == 11 and main.arthur.progression.xp == 17, "L/M: Real Slime death awards 11 Gold and 17 XP")
	check(attack_values == [13, 13, 13], "Real attacks use combined base and equipment Attack")
	check(main.status_label.text.contains("+11 Gold, +17 XP"), "Reward feedback uses modified amounts")
	if not await wait_for(func(): return main.gold >= 22):
		return
	check(main.arthur.progression.level == 2 and main.arthur.progression.xp == 4
		and main.arthur.total_attack() == 15 and main.arthur.total_max_hp() == 120
		and main.arthur.progression.current_hp == 120, "N: Real reward leveling keeps gear and overflow correct")
	await capture("m5-level-equipped")
	print("Milestone 5 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)

func press_button(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		if not button.disabled:
			button.pressed.emit()
		await process_frame
	else:
		await click_at(button.get_global_rect().get_center())
