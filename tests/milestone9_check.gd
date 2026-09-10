# Run headless for logic; omit --headless to exercise real mouse dispatch/summary.
extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const MISSIONS = preload("res://scripts/expedition_panel.gd").MISSIONS
const GEL = preload("res://data/items/slime_gel.tres")
const REASON = StopConditionEvaluator.Reason
var failures: int = 0
var main: Node2D
var energy_history: Array[int] = []
var spawn_count: int = 0
var seen_defeats: int = 0

func _initialize() -> void:
	run_check.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)

func wait_for(predicate: Callable, description: String, seconds: float = 30.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() > deadline:
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
	var button: Button = main.expedition_ui.mission_buttons[MISSIONS[index].id]
	main.expedition_ui.get_node("Margin/Column/Board/Scroll").ensure_control_visible(button)
	await process_frame
	await press(button)

func capture(file_name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/" + file_name + ".png")

func returned() -> bool:
	return main.mission_run.summary_pending and main.mission_run.mission_state == MissionRun.State.IDLE

func on_run_changed() -> void:
	if main.mission_run.defeated_encounters > seen_defeats:
		seen_defeats = main.mission_run.defeated_encounters
		energy_history.append(main.arthur.current_energy)

func dispatch(index: int) -> void:
	seen_defeats = 0
	spawn_count = 0
	energy_history.clear()
	await select_mission(index)
	await press(main.expedition_ui.send_button)

func defeat_encounter() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_F8
	key.pressed = true
	main._unhandled_key_input(key)

func run_check() -> void:
	var config := ExpeditionStopConfig.new()
	check(config.min_hp_percent == 0.45 and config.min_energy_percent == 0.35
		and config.inventory_capacity == 10 and config.inventory_return_percent == 0.8
		and config.encounter_cap == 8 and config.return_on_hero_downed, "Exact configurable stop defaults")
	check(not StopConditionEvaluator.evaluate({"current_energy": 35}, config).should_stop,
		"Exactly 35 percent Energy does not trigger strict-below threshold")
	check(StopConditionEvaluator.evaluate({"current_energy": 34}, config).reason == REASON.ENERGY_LOW,
		"Below 35 percent triggers ENERGY_LOW")
	check(StopConditionEvaluator.evaluate({"current_energy": 69, "max_energy": 200}, config).reason == REASON.ENERGY_LOW,
		"Threshold scales with maximum Energy")
	check(not StopConditionEvaluator.evaluate({"current_hp": 45}, config).should_stop
		and StopConditionEvaluator.evaluate({"current_hp": 44}, config).reason == REASON.HP_LOW,
		"O: HP_LOW detected below 45 percent in isolation")
	check(not StopConditionEvaluator.evaluate({"carried_units": 10}, config).should_stop,
		"Random inventory trigger disabled in normal gameplay")
	config.inventory_stop_enabled = true
	check(not StopConditionEvaluator.evaluate({"carried_units": 7}, config).should_stop
		and StopConditionEvaluator.evaluate({"carried_units": 8}, config).reason == REASON.INVENTORY_LIMIT,
		"P: Enabled capacity trigger fires at 8/10 units")
	check(StopConditionEvaluator.evaluate({"encounters_completed": 8}, config).reason == REASON.ENCOUNTER_CAP,
		"Q: Encounter cap evaluates at eight")
	check(StopConditionEvaluator.evaluate({"current_hp": 0}, config).reason == REASON.HERO_DOWNED,
		"Downed definition takes precedence without adding death gameplay")
	config.encounter_cap = 11
	check(not StopConditionEvaluator.evaluate({"encounters_completed": 8}, config).should_stop,
		"Future upgrades can modify cap through config")
	config = ExpeditionStopConfig.new()
	for index in range(3):
		check(MISSIONS[index].energy_cost_per_encounter == [15, 18, 20][index], "Data-driven Energy cost: " + MISSIONS[index].id)
		check(StopConditionEvaluator.predict(MISSIONS[index], 100, 100, config) ==
			("LIKELY TO COMPLETE" if index == 0 else "RISK OF RETREAT"), "Prediction matches default outcome")

	var run := MissionRun.new()
	run.start(MISSIONS[0])
	run.resolve_checkpoint({"current_energy": 0})
	check(run.mission_state == MissionRun.State.IN_PROGRESS and run.encounter_active,
		"No stop evaluation in an active fight")
	run.record_defeat(10, 15)
	run.start_next_encounter()
	check(run.current_encounter == 1, "Checkpoint must resolve before next encounter")
	run.record_loot(GEL)
	run.stop_config.inventory_stop_enabled = true
	run.stop_config.inventory_capacity = 1
	run.resolve_checkpoint({})
	check(run.stop_reason == REASON.INVENTORY_LIMIT and run.result_status == MissionRun.Result.RETREATED,
		"Pickup counts reach the run evaluator before dispatching next enemy")
	check(not run.claim_completion_reward(30, 30), "Retreat cannot claim completion rewards")
	run.begin_return()
	run.finish_return()
	check(run.result_status == MissionRun.Result.RETREATED and run.stop_reason == REASON.INVENTORY_LIMIT,
		"Outcome and reason survive RETURNING and IDLE")
	run.free()
	run = MissionRun.new()
	check(not run.stop_config.inventory_stop_enabled and run.stop_config.inventory_capacity == 10,
		"Run configs are independent instances")
	run.start(MISSIONS[0])
	for encounter in range(3):
		run.record_defeat(10, 15)
		run.resolve_checkpoint({"current_energy": 0 if encounter == 2 else 100})
		run.start_next_encounter()
	check(run.result_status == MissionRun.Result.COMPLETED and run.stop_reason == REASON.NONE,
		"Final encounter completion wins over low Energy")
	run.free()

	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	check(main.arthur.current_energy == 100 and main.arthur.max_energy == 100
		and main.energy_bar.value == 100 and main.energy_label.text.contains("100 / 100"), "A: Starts with 100/100 Energy and UI")
	main.mission_run.changed.connect(on_run_changed)
	main.mission_run.encounter_requested.connect(func():
		spawn_count += 1
		main.debug_next_drop = GEL)
	await capture("m9-board")
	await dispatch(0)
	if not await wait_for(returned, "natural Forest Patrol completion"):
		return
	check(energy_history == [85, 70, 55] and main.mission_run.ending_energy == 55,
		"B/C: Forest costs 15 each and completes at 55 Energy")
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and main.gold == 60
		and main.mission_run.total_xp() == 75, "N: Forest retains full completion rewards")
	main._on_mission_completed()
	check(main.gold == 60 and main.arthur.current_energy == 100, "L/N: Full Guild recovery; completion reward cannot repeat")
	await press(main.expedition_ui.continue_button)

	await select_mission(1)
	check(main.expedition_ui.prediction == "RISK OF RETREAT" and not main.expedition_ui.send_button.disabled,
		"Risk warns without blocking dispatch")
	await capture("m9-risk")
	await dispatch(1)
	var gold_before: int = main.gold
	for encounter in range(4):
		if not await wait_for(func(): return is_instance_valid(main.slime), "Nest encounter"):
			return
		defeat_encounter()
	if not await wait_for(func(): return main.mission_run.result_status == MissionRun.Result.RETREATED, "energy retreat"):
		return
	check(energy_history == [82, 64, 46, 28] and main.arthur.current_energy == 28,
		"D/E: Nest retreats after fourth encounter with 28 Energy")
	check(main.mission_run.stop_reason == REASON.ENERGY_LOW and main.mission_run.ending_energy == 28,
		"M: ENERGY_LOW and ending Energy recorded")
	main._on_encounter_delay_finished()
	check(not is_instance_valid(main.slime) and spawn_count == 4, "F: No fifth encounter after stop")
	await capture("m9-stopped")
	if not await wait_for(returned, "Nest return"):
		return
	check(main.gold - gold_before == 40 and main.mission_run.total_xp() == 60
		and main.mission_run.completion_gold == 0 and main.mission_run.completion_xp == 0
		and not main.mission_run.completion_reward_eligible, "H/I: Keep four combat rewards; no completion reward")
	check(main.inventory.quantity(GEL.id) == 7 and main.mission_run.collected_loot[GEL.id] == 4,
		"J: All retreat loot remains in Inventory including final pickup")
	check(main.arthur.guild_status == "IDLE_AT_GUILD" and main.arthur.current_energy == 100
		and main.mission_run.result_status == MissionRun.Result.RETREATED, "K/L: Guild recovers Energy without erasing outcome")
	check(main.expedition_ui.title.text == "EXPEDITION ENDED" and main.expedition_ui.summary.text.contains("NOT EARNED")
		and main.expedition_ui.summary.text.contains("Low Energy"), "Retreat summary clearly distinguishes result and rewards")
	await capture("m9-retreat-summary")
	await press(main.expedition_ui.continue_button)

	# Verify retreat rewards with equipment and Guild modifiers combined.
	main.wallet.add_gold(1000)
	for node_id in ["coin_pouch_1", "coin_pouch_2", "shared_experience_1", "shared_experience_2"]:
		main.guild_mastery.purchase(node_id, main.wallet)
	for item in [preload("res://data/items/slime_ring.tres"), preload("res://data/items/slime_crown.tres")]:
		main.inventory.add_item(item)
		main.arthur.equipment.equip(main.inventory, item.id)
	await dispatch(2)
	gold_before = main.gold
	for encounter in range(4):
		if not await wait_for(func(): return is_instance_valid(main.slime), "Treasure encounter"):
			return
		defeat_encounter()
	if not await wait_for(returned, "Treasure return"):
		return
	check(energy_history == [80, 60, 40, 20] and main.mission_run.ending_energy == 20 and spawn_count == 4,
		"G: Treasure retreats at 4/8 with 20 Energy")
	check(main.gold - gold_before == 48 and main.mission_run.total_xp() == 72
		and not main.mission_run.completion_reward_claimed, "R/S: Modified 12 Gold/18 XP per kill preserved on retreat")
	main._on_mission_completed()
	main._on_slime_died()
	check(main.gold - gold_before == 48 and main.mission_run.defeated_encounters == 4,
		"Duplicate callbacks cannot award completion or consume more Energy")
	await press(main.expedition_ui.continue_button)
	await create_timer(2.1).timeout
	check(main.mission_run.can_start() and not is_instance_valid(main.slime) and main.arthur.current_energy == 100,
		"No automatic repeat or dispatch after recovery")
	check(not main.guild_mastery.owns("repeat_orders") and main.wallet.guild_tokens == 0,
		"No future Mastery activation or Token rewards")
	print("Milestone 9 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
