# Run: godot --headless --path . --script res://tests/milestone4_check.gd
extends SceneTree

const LOOT_TABLE = preload("res://scripts/loot_table.gd")
const MAIN_SCENE = preload("res://scenes/main.tscn")
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


func wait_for(predicate: Callable, seconds: float = 12.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			check(false, "Timed out waiting for loot/combat")
			quit(1)
			return false
		await process_frame
	return true


func find_text(message: String) -> Node2D:
	for child in main.get_children():
		if child.has_node("Label") and child.get_node("Label").text == message:
			return child
	return null


func capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/" + file_name + ".png")


func debug_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	main._unhandled_key_input(event)


func run_check() -> void:
	var table = LOOT_TABLE.new()
	var counts: Dictionary[String, int] = {}
	for value in range(100):
		var item: ItemData = table.item_for_roll(value)
		var id: String = item.id if item != null else "none"
		counts[id] = counts.get(id, 0) + 1
	check(counts == {"slime_gel": 50, "rusty_sword": 20, "old_shield": 15,
		"slime_ring": 5, "slime_crown": 1, "none": 9},
		"A/B: All five items and no-drop have exact configured probabilities")
	var rarities: Array[int] = [0, 0, 0, 2, 3]
	for index in range(table.ITEMS.size()):
		var item: ItemData = table.ITEMS[index]
		check(item.rarity == rarities[index] and not item.description.is_empty()
			and item.base_value > 0 and item.item_type == index,
			"C: Resource fields correct for " + item.display_name)
	var sample := ItemData.new()
	var colors: Array[Color] = []
	for rarity in range(6):
		sample.rarity = rarity
		colors.append(sample.rarity_color())
		check(sample.is_rare_or_higher() == (rarity >= 2), "Rarity feedback classification " + sample.rarity_name())
	check(colors.size() == 6 and colors[2] != colors[3], "Rarity presentation colors available")
	table.rng.seed = 42
	var sequence: Array[ItemData] = []
	for index in range(20):
		sequence.append(table.roll())
	table.rng.seed = 42
	for index in range(20):
		check(table.roll() == sequence[index], "Seeded roll repeats")
	var no_drop_seed: int = -1
	for candidate in range(1000):
		table.rng.seed = candidate
		if table.roll() == null:
			no_drop_seed = candidate
			break
	check(no_drop_seed >= 0, "Deterministic no-drop seed found")

	# Pause movement while inspecting ground lifetime and presentation.
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	main.arthur.set_physics_process(false)
	var ring: ItemData = table.ITEMS[3]
	var gel: ItemData = table.ITEMS[0]
	var loot = main._spawn_ground_loot(ring, Vector2(720, 350))
	check(loot.item == ring and loot.get_node("NameLabel").text == "Slime Ring"
		and loot.get_node("Shape").color == ring.rarity_color(), "D: GroundLoot retains ItemData, name, and rarity color")
	var rare_effect = find_text("RARE DROP!\nSlime Ring")
	check(is_instance_valid(rare_effect) and rare_effect.get_node("Label").get_theme_font_size("font_size") == 30,
		"I: Rare drop gets larger named feedback")
	await capture("m4-rare-ground")
	await create_timer(0.95).timeout
	check(is_instance_valid(rare_effect), "I: Rare feedback lasts longer than ordinary 0.8-second text")
	await create_timer(1.0).timeout
	check(is_instance_valid(loot) and main.inventory.get_items().is_empty(), "Ground loot persists uncollected outside pickup range")
	main.arthur.position = loot.position
	main._physics_process(0.0)
	loot.collect()
	await process_frame
	check(not is_instance_valid(loot), "E: Nearby pickup removes GroundLoot")
	check(main.inventory.quantity("slime_ring") == 1, "F: Pickup is stored exactly once")
	check(is_instance_valid(find_text("RARE PICKUP: Slime Ring")), "Rare pickup includes rarity")
	for index in range(3):
		main._spawn_ground_loot(gel, main.arthur.position)
	main._physics_process(0.0)
	await process_frame
	check(main.inventory.quantity("slime_gel") == 3 and main.inventory_ui.inventory_list.get_item_text(1) == "Slime Gel x3",
		"F: Duplicate materials stack by ID and update history")
	check(main.arthur.progression.damage == 10 and main.gold == 0
		and main.arthur.progression.xp == 0, "Collecting items does not equip them or alter combat rewards")
	main.queue_free()
	await process_frame

	# Real combat: force one Rare, one Epic, then verify the override is consumed.
	main = MAIN_SCENE.instantiate()
	root.add_child(main)
	debug_key(KEY_F6)
	check(main.debug_next_drop == ring, "Debug F6 forces next Rare")
	if not await wait_for(func(): return main.gold == 10):
		return
	check(main.arthur.progression.xp == 15, "G: Slime death still gives 10 Gold and 15 XP")
	check(main.ground_loot.get_child_count() == 1
		and main.ground_loot.get_child(0).item == ring, "One kill produces exactly one forced Rare")
	check(main.debug_next_drop == null, "Debug override consumed after one kill")
	var death_time: int = Time.get_ticks_msec()
	if not await wait_for(func(): return main.inventory.quantity("slime_ring") == 1, 1.5):
		return
	check(main.arthur.position.x > 590.0, "Arthur walks into the small pickup range during respawn pause")
	await capture("m4-rare-pickup")
	if not await wait_for(func(): return is_instance_valid(main.slime), 2.0):
		return
	check(Time.get_ticks_msec() - death_time >= 1900
		and Time.get_ticks_msec() - death_time <= 2200, "H: Slime respawns after two seconds")
	debug_key(KEY_F7)
	if not await wait_for(func(): return main.gold == 20):
		return
	check(main.ground_loot.get_child_count() == 1
		and main.ground_loot.get_child(0).item == table.ITEMS[4], "Debug F7 forces one Epic")
	check(is_instance_valid(find_text("EPIC DROP!\nSlime Crown")), "I: Epic enhanced feedback appears")
	check(main.arthur.progression.level == 2 and main.arthur.progression.damage == 12,
		"Leveling and increased damage preserved")
	await capture("m4-epic")
	main.loot_table.rng.seed = no_drop_seed
	if not await wait_for(func(): return main.inventory.quantity("slime_crown") == 1, 1.5):
		return
	if not await wait_for(func(): return main.gold == 30):
		return
	check(main.ground_loot.get_child_count() == 0 and main.inventory.get_items().size() == 2,
		"A: Normal no-drop resumes after debug override")
	check(main.arthur.progression.xp == 15, "No-drop kill still awards XP")
	print("Milestone 4 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)