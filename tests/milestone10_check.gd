# Headless tests use injected time. Rendered tests also click the real board.
extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const CONFIG = preload("res://data/rotation/default.tres")
const BOSS_LOOT = preload("res://data/loot/ancient_treant_completion.tres")
const GEL = preload("res://data/items/slime_gel.tres")
var main: Node2D
var failures: int = 0
var enemies: Array[String] = []
var boss_hits: int = 0

func _initialize() -> void:
	run_check.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)

func wait_for(predicate: Callable, description: String, seconds: float = 45.0) -> bool:
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

func select_opportunity() -> void:
	var button: Button = main.expedition_ui.opportunity_button
	main.expedition_ui.entries.get_parent().ensure_control_visible(button)
	await process_frame
	await press(button)

func debug_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	main._unhandled_key_input(event)

func returned() -> bool:
	return main.mission_run.summary_pending and main.mission_run.mission_state == MissionRun.State.IDLE

func capture(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + file_name + ".png")

func on_encounter() -> void:
	enemies.append(main.slime.enemy_data.id)
	if main.slime.enemy_data.id == "slime":
		main.debug_next_drop = GEL

func on_attack(target: Node2D, _damage: int) -> void:
	if target.enemy_data.enemy_type == "BOSS":
		boss_hits += 1
		check(main.arthur.global_position.distance_to(target.global_position) <= main.arthur.MELEE_RANGE + 0.01,
			"Boss attack uses existing melee range")

func run_check() -> void:
	var rotation := MissionBoardRotation.new()
	var time: Array[float] = [100.0]
	rotation.clock = func(): return time[0]
	rotation.initialize()
	check(rotation.config.refresh_seconds == 300 and rotation.config.expiration_seconds == [1200.0, 1200.0, 3600.0],
		"Production refresh and expiration values are configurable and correct")
	var counts: Array[int] = [0, 0, 0]
	for value in range(100):
		counts[rotation.index_for_roll(value)] += 1
	check(counts == [65, 25, 10], "E: Exact 65/25/10 weighted selection")
	for index in range(3):
		rotation.spawn_opportunity(index)
		check(rotation.slot.special_type == ["NORMAL", "ELITE", "BOSS"][index], "B/C/D: Slot supports each special type")
		check(rotation.slot.spawned_at == 100 and rotation.slot.remaining_time == CONFIG.expiration_seconds[index]
			and rotation.slot.mission_data_id == CONFIG.missions[index].id, "F: Runtime instance tracks data, spawn and expiry")
	check(rotation.slot.requires_manual_attention and CONFIG.missions[1].requires_manual_attention,
		"Elite and Boss require manual attention")
	rotation.slot.mission_modifiers["rare_weight_multiplier"] = 9.0
	check(rotation.slot.definition.rare_weight_multiplier == 1.0, "Runtime modifiers never mutate static MissionData")
	rotation.debug_toggle_fast_refresh()
	check(rotation.config.refresh_seconds == 10 and CONFIG.refresh_seconds == 300,
		"DEBUG acceleration is isolated from production config data")
	rotation.debug_toggle_fast_refresh()
	check(rotation.config.refresh_seconds == 300, "DEBUG acceleration restores normal interval")
	var first: MissionInstance = rotation.slot
	time[0] = 101
	rotation.tick()
	check(first.countdown_text(time[0]) == "59:59" and first.remaining_time == 3599, "Q: Safe countdown updates from elapsed time")
	time[0] = 400
	rotation.tick()
	check(rotation.slot == first, "Refresh does not replace an unexpired opportunity")
	time[0] = first.expires_at
	check(not rotation.can_claim(first), "G: Expiration blocks dispatch even before timer tick")
	rotation.tick()
	check(rotation.slot == null, "Expired idle slot is removed")
	time[0] += 299
	rotation.tick()
	check(rotation.slot == null, "Expired slot waits for its next refresh")
	time[0] += 1
	rotation.tick()
	check(rotation.slot != null and rotation.slot.instance_id != first.instance_id, "One fresh instance appears on next refresh")
	var active: MissionInstance = rotation.slot
	check(rotation.claim(active) and active.claimed and active.active and rotation.slot == null, "Claim detaches runtime instance from the one slot")
	time[0] = active.expires_at + 1
	rotation.tick()
	check(active.active and active.remaining_time == 0 and not rotation.can_claim(active), "H: Active instance survives expiry and cannot be claimed twice")
	rotation.free()

	var loot = preload("res://scripts/loot_table.gd").new()
	check(loot.mission_weights(1, 3) == [50.0, 20.0, 15.0, 15.0, 3.0, 9.0], "I: Elite triples Ring/Crown weights without guarantees")
	check(loot.mission_weights(1, 1, 1.25) == [62.5, 20.0, 15.0, 5.0, 1.0, 9.0], "Supply Run boosts materials only")
	var boss: MissionData = CONFIG.missions[2]
	check(boss.is_valid_definition() and boss.encounter_count == 3, "J: Boss has valid three-encounter definition")
	check(boss.enemy_for_encounter(1).id == "slime" and boss.enemy_for_encounter(2).id == "slime"
		and boss.enemy_for_encounter(3).id == "ancient_treant", "K: Mixed sequence ends with Ancient Treant")
	check(boss.enemy_for_encounter(3).max_hp == 150 and boss.total_energy_cost() == 55
		and boss.energy_for_encounter(3) == 25, "L: Treant HP and mixed Energy costs")
	check(StopConditionEvaluator.predict(boss, 100, 100, ExpeditionStopConfig.new()) == "LIKELY TO COMPLETE",
		"S: Prediction uses mixed encounter costs")
	for index in range(3):
		var wins: int = 0
		for value in range(100):
			if BOSS_LOOT.wins(index, value):
				wins += 1
		check(wins == [100, 15, 3][index], "M/N/O: Exact independent probability for " + BOSS_LOOT.items[index].id)
	check(not BOSS_LOOT.items[1].is_equippable() and BOSS_LOOT.items[2].is_equippable(), "Relic Material stays material; Legendary relic can equip")
	var completion_rng := RandomNumberGenerator.new()
	var all_loot_seed: int = -1
	for seed_value in range(10000):
		completion_rng.seed = seed_value
		if BOSS_LOOT.roll(completion_rng).size() == 3:
			all_loot_seed = seed_value
			break
	check(all_loot_seed >= 0, "Independent rolls can award all three boss items together")

	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	check(main.expedition_ui.mission_buttons.size() == 3 and not is_instance_valid(main.slime), "A: Three persistent missions remain, no automatic dispatch")
	var board_time: Array[float] = [100.0]
	main.board_rotation.clock = func(): return board_time[0]
	debug_key(KEY_2)
	check(main.board_rotation.slot.definition.id == "forest_supply_run", "DEBUG 2 forces Normal opportunity")
	await select_opportunity()
	check(main.expedition_ui.selected.id == "forest_supply_run" and main.expedition_ui.rotation_status.text.contains("20:00"),
		"Normal card selection and expiry display")
	debug_key(KEY_3)
	check(main.notification_label.text == "Elite mission appeared!", "R: Elite spawn notification")
	await select_opportunity()
	check(main.expedition_ui.details.text.contains("ELITE") and main.expedition_ui.prediction == "RISK OF RETREAT",
		"Elite label and endurance prediction")
	await capture("m10-elite")
	debug_key(KEY_4)
	check(main.notification_label.text == "BOSS PORTAL OPENED", "R: Boss spawn notification")
	await select_opportunity()
	check(main.expedition_ui.opportunity_button.text.contains("Ancient Bark")
		and main.expedition_ui.details.text.contains("Rootbound Relic"), "Unique loot shown on Boss card and details")
	await capture("m10-boss-board")
	var expired: MissionInstance = main.board_rotation.slot
	debug_key(KEY_5)
	board_time[0] += 6
	check(not main.start_opportunity(expired), "G: Expired selected opportunity cannot start")
	main.board_rotation.tick()
	check(main.board_rotation.slot == null and main.expedition_ui.opportunity_button.disabled
		and main.expedition_ui.mission_buttons.size() == 3, "Expired slot empties; base missions stay available")
	debug_key(KEY_4)
	var dispatched: MissionInstance = main.board_rotation.slot
	dispatched.seed = all_loot_seed
	check(not main.start_mission(boss), "Special mission cannot bypass instance claiming")
	await select_opportunity()
	main.mission_run.encounter_requested.connect(on_encounter)
	main.arthur.attacked.connect(on_attack)
	await press(main.expedition_ui.send_button)
	check(main.mission_run.source_instance == dispatched and dispatched.active and not main.expedition_ui.visible,
		"Manual dispatch binds the claimed runtime instance")
	debug_key(KEY_5)
	board_time[0] += 6
	main.board_rotation.tick()
	check(main.mission_run.mission_state == MissionRun.State.IN_PROGRESS and dispatched.active,
		"H: Active mission continues after its expiry")
	if not await wait_for(func(): return is_instance_valid(main.slime) and main.slime.enemy_data.id == "ancient_treant", "boss spawn"):
		return
	check(main.slime.hp == 150 and is_equal_approx(main.slime.visuals.scale.x, 1.6) and main.hp_label.text.contains("Ancient Treant"),
		"L: Actual boss spawns with 150 HP and larger distinct presentation")
	await capture("m10-boss-combat")
	if not await wait_for(returned, "natural boss completion"):
		return
	check(enemies == ["slime", "slime", "ancient_treant"] and boss_hits == 13, "Normal combat defeats the mixed sequence with current damage")
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and main.mission_run.ending_energy == 45
		and main.mission_run.total_gold() == 270 and main.mission_run.total_xp() == 210, "Boss completion awards encounter plus completion rewards once")
	check(main.inventory.quantity("ancient_bark") == 1 and main.inventory.quantity("treant_heart") == 1
		and main.inventory.quantity("rootbound_relic") == 1, "M: Seeded boss completion loot enters Inventory")
	check(main.mission_run.collected_loot.get("ancient_bark", 0) == 1 and not dispatched.active and dispatched.claimed,
		"Boss loot appears in run summary and claimed instance is consumed")
	check(not main.arthur.equipment.equip(main.inventory, "treant_heart") and main.inventory.quantity("treant_heart") == 1,
		"Treant Heart cannot be equipped or lost by an equip attempt")
	main._on_mission_completed()
	check(main.inventory.quantity("ancient_bark") == 1 and main.gold == 270, "Duplicate completion cannot duplicate boss loot or rewards")
	await capture("m10-boss-summary")
	await press(main.expedition_ui.continue_button)
	check(not main.start_opportunity(dispatched), "Consumed boss opportunity cannot be replayed")

	debug_key(KEY_4)
	await select_opportunity()
	debug_key(KEY_0)
	await press(main.expedition_ui.send_button)
	debug_key(KEY_F8)
	if not await wait_for(returned, "retreat before boss"):
		return
	check(main.mission_run.result_status == MissionRun.Result.RETREATED and main.mission_run.defeated_encounters == 1,
		"P: Low Energy retreats before reaching the boss")
	check(main.inventory.quantity("ancient_bark") == 1 and main.inventory.quantity("treant_heart") == 1
		and main.mission_run.completion_gold == 0 and not main.mission_run.collected_loot.has("ancient_bark"),
		"P: Retreat gives no boss loot rolls or completion bonus")
	await press(main.expedition_ui.continue_button)
	# Exercise Elite's instance modifier through the real encounter loot path.
	debug_key(KEY_3)
	await select_opportunity()
	debug_key(KEY_0)
	await press(main.expedition_ui.send_button)
	main.debug_next_drop = null
	var expected_drop: ItemData
	var seed_to_use: int = 0
	for seed_value in range(100):
		main.loot_table.rng.seed = seed_value
		expected_drop = main.loot_table.roll(1, 3)
		main.loot_table.rng.seed = seed_value
		if expected_drop != main.loot_table.roll():
			seed_to_use = seed_value
			break
	main.loot_table.rng.seed = seed_to_use
	debug_key(KEY_F8)
	var drops: Array[Node] = main.ground_loot.get_children()
	check(drops.is_empty() if expected_drop == null else drops.size() == 1 and drops[0].item == expected_drop,
		"I: Elite instance modifier reaches actual encounter loot roll")
	if not await wait_for(returned, "Elite checkpoint return"):
		return
	await press(main.expedition_ui.continue_button)
	debug_key(KEY_1)
	check(main.board_rotation.slot != null and not is_instance_valid(main.slime), "Forced random refresh never auto-dispatches")
	check(not main.guild_mastery.owns("notice_board") and not main.guild_mastery.owns("repeat_orders"), "Future Portal Mastery remains inactive")
	print("Milestone 10 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
