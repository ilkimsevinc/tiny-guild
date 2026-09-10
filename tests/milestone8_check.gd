# Headless: logic and UI signals. Rendered: real mouse clicks plus live combat.
extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const BOARD = preload("res://scripts/expedition_panel.gd")
const LOOT = preload("res://scripts/loot_table.gd")
const GEL = preload("res://data/items/slime_gel.tres")
var failures: int = 0
var main: Node2D
var observed_encounters: Array[int] = []
var attacks: int = 0
var transitions: Array[int] = []

func _initialize() -> void:
	run_check.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)

func wait_for(predicate: Callable, description: String, seconds: float = 25.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			check(false, "Timed out: " + description)
			quit(1)
			return false
		await process_frame
	return true

func press(button: Button) -> void:
	if DisplayServer.get_name() == "headless":
		if not button.disabled:
			button.pressed.emit()
	else:
		var event := InputEventMouseButton.new()
		event.position = button.get_global_rect().get_center()
		event.global_position = event.position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = true
		root.push_input(event)
		event = event.duplicate()
		event.pressed = false
		root.push_input(event)
	await process_frame

func select_mission(index: int) -> void:
	var button: Button = main.expedition_ui.mission_buttons[BOARD.MISSIONS[index].id]
	main.expedition_ui.get_node("Margin/Column/Board/Scroll").ensure_control_visible(button)
	await process_frame
	await press(button)

func capture(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + file_name + ".png")

func on_encounter() -> void:
	observed_encounters.append(main.mission_run.current_encounter)
	main.debug_next_drop = GEL
	var active: int = 0
	for child in main.get_children():
		if child.get_script() == preload("res://scripts/slime.gd") and child.hp > 0:
			active += 1
	check(active == 1, "G: Exactly one live enemy at encounter spawn")

func on_attack(target: Node2D, _damage: int) -> void:
	attacks += 1
	check(main.arthur.global_position.distance_to(target.global_position) <= main.arthur.MELEE_RANGE + 0.01, "Existing combat attacks only in melee range")

func returned() -> bool:
	return main.mission_run.summary_pending and main.mission_run.mission_state == MissionRun.State.IDLE

func debug_clear_mission() -> void:
	for encounter in range(1, main.mission_run.total_encounters + 1):
		if not await wait_for(func(): return is_instance_valid(main.slime), "next encounter"):
			return
		check(main.mission_run.current_encounter == encounter, "Encounter advances in order")
		var key := InputEventKey.new()
		key.keycode = KEY_F8
		key.pressed = true
		main._unhandled_key_input(key)
		check(main.mission_run.defeated_encounters == encounter, "H: Defeat counted exactly once")
	if not await wait_for(returned, "return to Guild"):
		return

func run_check() -> void:
	var definitions: Array[MissionData] = BOARD.MISSIONS
	check(definitions[0].encounter_count == 3 and definitions[0].base_gold_reward == 30
		and definitions[0].base_xp_reward == 30, "C: Forest Patrol data")
	check(definitions[1].encounter_count == 6 and definitions[1].base_gold_reward == 70
		and definitions[1].base_xp_reward == 60, "D: Slime Nest data")
	check(definitions[2].encounter_count == 8 and definitions[2].base_gold_reward == 40
		and definitions[2].base_xp_reward == 80, "E: Treasure Trail data")
	var run := MissionRun.new()
	check(run.start(definitions[0]) and run.mission_id == "forest_patrol" and run.current_encounter == 1,
		"F: Starting initializes reusable MissionRun")
	check(not run.start(definitions[1]), "R: Active mission rejects another dispatch")
	run.start_next_encounter()
	check(run.current_encounter == 1, "Active encounter cannot be advanced twice")
	for index in range(3):
		run.record_defeat(10, 15)
		run.record_defeat(10, 15)
		run.resolve_checkpoint({}) # Explicit post-pickup checkpoint.
		check(run.defeated_encounters == index + 1, "Duplicate defeat cannot advance or reward twice")
		if index < 2:
			check(run.mission_state == MissionRun.State.IN_PROGRESS, "I: No early completion")
			run.start_next_encounter()
	check(run.mission_state == MissionRun.State.COMPLETED and run.accumulated_gold == 30
		and run.accumulated_xp == 45, "J/L: Final encounter completes with accurate combat rewards")
	check(run.claim_completion_reward(30, 30) and not run.claim_completion_reward(30, 30)
		and run.total_gold() == 60 and run.total_xp() == 75, "K: Completion reward claim is exactly once")
	run.record_loot(GEL)
	run.record_loot(GEL)
	check(run.collected_loot[GEL.id] == 2 and run.loot_items[GEL.id] == GEL, "P: Run loot aggregates shared ItemData references")
	run.begin_return()
	check(not run.start(definitions[1]), "Dispatch blocked while returning")
	run.finish_return()
	check(not run.start(definitions[1]) and run.summary_pending, "Summary must be acknowledged before another dispatch")
	run.acknowledge_summary()
	check(run.start(definitions[1]) and run.collected_loot.is_empty() and run.accumulated_gold == 0,
		"Fresh run clears totals without altering definitions")
	run.free()

	var loot = LOOT.new()
	var normal: Array[float] = loot.mission_weights(1, 1)
	var nest: Array[float] = loot.mission_weights(1.25, 1)
	var treasure: Array[float] = loot.mission_weights(1, 1.5)
	check(normal == [50.0, 20.0, 15.0, 5.0, 1.0, 9.0], "Forest loot preserves original weights")
	check(nest == [62.5, 25.0, 18.75, 6.25, 1.25, 9.0], "Nest boosts item weights by 25 percent, keeps no-drop weight")
	check(treasure == [50.0, 20.0, 15.0, 7.5, 1.5, 9.0], "Treasure boosts Rare+ weights by 50 percent")
	check(loot.item_for_weight(0, treasure) == GEL and loot.item_for_weight(95, treasure) == null,
		"Treasure still permits common loot and no drop")
	loot.rng.seed = 852
	var expected: ItemData = loot.roll(1.25, 1)
	loot.rng.seed = 852
	check(loot.roll(1.25, 1) == expected and loot.mission_weights(1, 1) == normal,
		"Modified rolls repeat from seed and do not mutate global loot")

	main = MAIN.instantiate()
	root.add_child(main)
	main.mission_run.stop_config.min_energy_percent = 0.0 # Legacy full-run reward coverage.
	await process_frame
	check(main.arthur.guild_status == "IDLE_AT_GUILD" and main.arthur.state == main.arthur.State.IDLE,
		"A: Arthur starts idle at Guild")
	await create_timer(2.1).timeout
	main._spawn_slime()
	check(not is_instance_valid(main.slime) and main.respawn_timer.is_stopped() and main.gold == 0,
		"B: No startup enemy, combat rewards, or stray spawns")
	main.mission_run.encounter_requested.connect(on_encounter)
	main.arthur.attacked.connect(on_attack)
	main.mission_run.changed.connect(func(): transitions.append(main.mission_run.mission_state))
	await select_mission(2)
	check(main.expedition_ui.warning.text.contains("below") and not main.expedition_ui.send_button.disabled,
		"S: Underlevel warning does not block SEND")
	await capture("m8-board")
	await select_mission(0)
	await press(main.expedition_ui.send_button)
	check(main.mission_run.mission_id == "forest_patrol" and not main.expedition_ui.visible
		and main.arthur.guild_status == "ON_EXPEDITION", "Board dispatch starts Forest Patrol and hides board")
	check(not main.start_mission(definitions[1]) and main.expedition_ui.send_button.disabled,
		"R: UI and controller both block overlapping missions")
	if not await wait_for(func(): return main.mission_run.defeated_encounters == 1, "first live kill"):
		return
	check(main.gold == 10 and main.arthur.progression.xp == 15 and main.wallet.guild_tokens == 0,
		"L: First mission encounter awards 10 Gold / 15 XP and no Tokens")
	check(main.mission_run.mission_state == MissionRun.State.IN_PROGRESS, "I: First kill does not complete Forest Patrol")
	await capture("m8-combat")
	if not await wait_for(returned, "Forest Patrol live completion"):
		return
	check(observed_encounters == [1, 2, 3] and attacks == 9, "Exactly three naturally fought Slimes; no endless fourth spawn")
	check(main.gold == 60 and main.mission_run.total_xp() == 75
		and main.arthur.progression.level == 3 and main.arthur.progression.xp == 0,
		"Live completion: 60 Gold / 75 XP total, normal leveling preserved")
	check(main.inventory.quantity(GEL.id) == 3 and main.mission_run.collected_loot[GEL.id] == 3
		and main.ground_loot.get_child_count() == 0, "O/P: All three drops picked up, including final drop; run and inventory agree")
	check(main.arthur.guild_status == "IDLE_AT_GUILD" and main.expedition_ui.summary.visible
		and main.expedition_ui.summary.text.contains("Gold +60 / XP +75"), "Q: Returned to Guild with accurate summary")
	check(MissionRun.State.COMPLETED in transitions and MissionRun.State.RETURNING in transitions,
		"Completion and return transitions both occur")
	main._on_mission_completed()
	main._on_slime_died()
	main._on_encounter_delay_finished()
	await create_timer(2.1).timeout
	check(main.gold == 60 and not is_instance_valid(main.slime), "K: Duplicate callbacks cannot pay twice or restart combat")
	await capture("m8-summary")
	await press(main.expedition_ui.continue_button)
	check(main.mission_run.can_start() and main.expedition_ui.board.visible, "CONTINUE returns to manual board selection")

	# Both equipment and Guild Mastery must also affect completion rewards once.
	main.wallet.add_gold(1000)
	for node_id in ["coin_pouch_1", "coin_pouch_2", "shared_experience_1", "shared_experience_2"]:
		main.guild_mastery.purchase(node_id, main.wallet)
	for item in [LOOT.ITEMS[3], LOOT.ITEMS[4]]:
		main.inventory.add_item(item)
		main.arthur.equipment.equip(main.inventory, item.id)
	var gold_before: int = main.gold
	await select_mission(1)
	await press(main.expedition_ui.send_button)
	await debug_clear_mission()
	check(main.mission_run.defeated_encounters == 6 and main.mission_run.completion_gold == 81
		and main.mission_run.completion_xp == 73, "M/N: Nest completion rounds 70*1.05*1.1 to 81 and 60*1.1*1.1 to 73")
	check(main.gold - gold_before == 153 and main.mission_run.accumulated_gold == 72
		and main.mission_run.accumulated_xp == 108 and main.mission_run.total_xp() == 181,
		"M/N: Encounter and completion rewards each receive modifiers exactly once")
	check(main.mission_run.collected_loot[GEL.id] == 6 and main.inventory.quantity(GEL.id) == 9,
		"Second summary contains only second-run loot")
	await press(main.expedition_ui.continue_button)
	await select_mission(2)
	await press(main.expedition_ui.send_button)
	await debug_clear_mission()
	check(main.mission_run.defeated_encounters == 8 and main.mission_run.total_gold() == 142
		and main.mission_run.total_xp() == 241, "Treasure Trail completes all eight encounters with correct modified totals")
	check(main.wallet.guild_tokens == 0 and not main.guild_mastery.owns("repeat_orders"), "No Tokens, automation, or future mastery activated")
	await press(main.expedition_ui.continue_button)
	await create_timer(2.1).timeout
	check(not is_instance_valid(main.slime) and main.mission_run.can_start(), "No automatic mission repeat after CONTINUE")
	# Dispatch real missions below their recommended level, with normal RNG drops.
	for index in [1, 2]:
		var preview = MAIN.instantiate()
		root.add_child(preview)
		preview.arthur.set_physics_process(false)
		var data: MissionData = definitions[index]
		check(preview.arthur.progression.level < data.recommended_level and preview.start_mission(data),
			"S: Underlevel Arthur can actually dispatch to " + data.display_name)
		var expected_drop: ItemData
		var chosen_seed: int = 0
		for seed_value in range(100):
			preview.loot_table.rng.seed = seed_value
			expected_drop = preview.loot_table.roll(data.item_weight_multiplier, data.rare_weight_multiplier)
			preview.loot_table.rng.seed = seed_value
			if expected_drop != preview.loot_table.roll():
				chosen_seed = seed_value
				break
		preview.loot_table.rng.seed = chosen_seed
		preview.slime.take_damage(30)
		var drops: Array[Node] = preview.ground_loot.get_children()
		check((drops.is_empty() if expected_drop == null else drops.size() == 1 and drops[0].item == expected_drop),
			"Active mission passes its own loot modifiers to the existing roll: " + data.id)
		preview.queue_free()
		await process_frame
	print("Milestone 8 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
