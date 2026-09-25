extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const NEST = preload("res://data/missions/slime_nest.tres")
const TRAIL = preload("res://data/missions/treasure_trail.tres")
const SUPPLY = preload("res://data/missions/forest_supply_run.tres")
const ELITE = preload("res://data/missions/elite_slime_outbreak.tres")
const BOSS = preload("res://data/missions/ancient_treant.tres")
const GEL = preload("res://data/items/slime_gel.tres")

var main: Node2D
var failures: int = 0

func _initialize() -> void:
	run_check.call_deferred()

func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)

func wait_for(predicate: Callable, description: String, seconds: float = 20.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			check(false, "Timed out: " + description)
			return false
		await process_frame
	return true

func press(button: Button) -> void:
	if not button.disabled:
		button.pressed.emit()
	await process_frame

func debug_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	main._unhandled_key_input(event)

func returned() -> bool:
	return main.mission_run.summary_pending and main.mission_run.mission_state == MissionRun.State.IDLE

func defeat_run(force_gel: bool = false) -> bool:
	while main.mission_run.mission_state == MissionRun.State.IN_PROGRESS:
		if not await wait_for(func(): return is_instance_valid(main.slime) or main.mission_run.mission_state != MissionRun.State.IN_PROGRESS,
				"next encounter", 8.0):
			return false
		if main.mission_run.mission_state != MissionRun.State.IN_PROGRESS:
			break
		if force_gel:
			main.debug_next_drop = GEL
		debug_key(KEY_F8)
		await process_frame
	return true

func run_check() -> void:
	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame

	check(not main.repeat_orders.repeat_unlocked and not main.guild_mastery.owns("repeat_orders"),
		"A: Repeat Orders starts locked and unowned")
	check(not main.expedition_ui.repeat_toggle.visible
		and main.expedition_ui.repeat_reason.text == "Unlock Repeat Orders in Guild Mastery",
		"A: Locked UI explains how to unlock Repeat Orders")
	main.wallet.add_gold(250)
	check(main.guild_mastery.purchase("repeat_orders", main.wallet) and main.wallet.balance == 0,
		"B: Purchase deducts exactly 250 Gold")
	check(main.guild_mastery.node_state("repeat_orders") == "OWNED"
		and main.mastery_ui.node_buttons["repeat_orders"].text.contains("OWNED"),
		"S: Mastery model and UI report Repeat Orders as owned")

	# Milestone 12: automatic redispatch now requires Scheduled Rest; debug x10 keeps this fast.
	main.wallet.add_gold(1200)
	main.guild_mastery.purchase("scheduled_rest", main.wallet)
	debug_key(KEY_7)

	check(main.repeat_orders.is_mission_eligible(FOREST), "C: Forest Patrol is repeatable")
	check(main.repeat_orders.is_mission_eligible(NEST), "D: Slime Nest is repeatable")
	check(main.repeat_orders.is_mission_eligible(TRAIL), "E: Treasure Trail is repeatable")
	check(not main.repeat_orders.is_mission_eligible(SUPPLY), "F: rotating Normal is not repeatable")
	check(not main.repeat_orders.is_mission_eligible(ELITE), "G: Elite is not repeatable")
	check(not main.repeat_orders.is_mission_eligible(BOSS), "H: Boss is not repeatable")
	main.expedition_ui.select_mission(FOREST)
	check(main.expedition_ui.repeat_toggle.visible and not main.expedition_ui.repeat_toggle.disabled,
		"C: Forest Patrol toggle becomes available after unlock")
	main.expedition_ui.repeat_toggle.button_pressed = true
	await process_frame
	check(main.repeat_orders.repeat_enabled and main.repeat_orders.mission_id == FOREST.id,
		"Repeat toggle creates a same-mission session")
	await press(main.expedition_ui.send_button)
	check(main.repeat_orders.repeat_run_count == 1 and main.mission_run.mission_id == FOREST.id,
		"First player-selected dispatch is Repeat Run 1")
	debug_key(KEY_F4)
	if not await defeat_run(true):
		quit(1)
		return
	if not await wait_for(func(): return main.repeat_orders.repeat_run_count == 2 and main.mission_run.mission_state == MissionRun.State.IN_PROGRESS,
			"automatic second dispatch", 15.0):
		quit(1)
		return
	check(main.mission_run.mission_id == FOREST.id, "I: Successful mission automatically restarts the same mission")
	check(main.repeat_orders.repeat_run_count == 2, "J: Repeat run counter increments")
	check(main.gold == 60 and main.arthur.progression.level == 3 and main.arthur.progression.xp == 0, "K: First run rewards are granted exactly once")
	check(main.inventory.quantity("slime_gel") == 3, "L: Repeated-run loot enters Inventory")
	check(main.arthur.current_energy == main.arthur.max_energy, "M: Scheduled Rest restores Energy before redispatch")
	check(not main.expedition_ui.continue_button.visible, "Summary auto-continues during Repeat Orders")

	var active_run: int = main.repeat_orders.repeat_run_count
	debug_key(KEY_4)
	check(main.board_rotation.slot != null and main.board_rotation.slot.special_type == "BOSS"
		and main.mission_run.mission_id == FOREST.id and main.repeat_orders.repeat_run_count == active_run,
		"Q: Boss spawning remains an opportunity and does not interrupt Repeat Orders")
	main._stop_repeat_after_current()
	check(not main.repeat_orders.repeat_enabled and main.repeat_orders.repeat_run_count == 0,
		"P: Disabling Repeat during a mission resets the session without cancelling combat")
	if not await defeat_run():
		quit(1)
		return
	if not await wait_for(returned, "cancelled repeat run return", 10.0):
		quit(1)
		return
	await create_timer(4.0).timeout
	check(main.mission_run.mission_state == MissionRun.State.IDLE and main.mission_run.summary_pending,
		"P: No new mission starts after player cancellation")
	await press(main.expedition_ui.continue_button)

	main.expedition_ui.select_mission(FOREST)
	main.expedition_ui.repeat_toggle.button_pressed = true
	main.repeat_orders.record_dispatch(FOREST)
	main.expedition_ui.select_mission(NEST)
	check(main.repeat_orders.repeat_enabled and main.repeat_orders.mission_id == FOREST.id
		and main.repeat_orders.repeat_run_count == 1, "R: Previewing a different mission does not cancel an armed repeat session")
	check(not main.expedition_ui.repeat_toggle.button_pressed, "R: The toggle reflects the previewed mission, not the armed one")
	main.expedition_ui.repeat_toggle.button_pressed = true
	check(main.repeat_orders.mission_id == NEST.id and main.repeat_orders.repeat_run_count == 0,
		"R: Explicitly toggling Repeat for a new mission redirects the session")
	debug_key(KEY_0)
	await press(main.expedition_ui.send_button)
	debug_key(KEY_F8)
	if not await wait_for(returned, "low-Energy retreat return", 8.0):
		quit(1)
		return
	check(main.mission_run.result_status == MissionRun.Result.RETREATED
		and not main.repeat_orders.repeat_enabled and main.repeat_orders.repeat_run_count == 0,
		"N: Retreat stops and resets Repeat Orders")
	check(main.repeat_orders.stop_reason == "Repeat Orders stopped: Arthur retreated due to Low Energy.",
		"N: Retreat stop reason is explicit")
	await create_timer(4.0).timeout
	check(main.mission_run.mission_state == MissionRun.State.IDLE, "O: No mission starts after retreat")

	var future := RepeatOrderState.new()
	future.setup(main.guild_mastery)
	future.set_enabled(FOREST, true)
	future.stop_for_result("HERO_DOWNED")
	check(not future.repeat_enabled and future.stop_reason.contains("Hero Downed"),
		"Future FAILED/HERO_DOWNED results use the shared terminal stop hook")
	future.free()

	debug_key(KEY_3)
	main.expedition_ui.select_opportunity()
	check(main.expedition_ui.repeat_toggle.disabled
		and main.expedition_ui.repeat_reason.text == "Special missions cannot be repeated",
		"G: Elite opportunity clearly disables Repeat Mission")
	debug_key(KEY_4)
	main.expedition_ui.select_opportunity()
	check(main.expedition_ui.repeat_toggle.disabled, "H: Boss opportunity disables Repeat Mission")

	print("Milestone 11 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)