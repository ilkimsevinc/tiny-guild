extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const NEST = preload("res://data/missions/slime_nest.tres")
const SUPPLY = preload("res://data/missions/forest_supply_run.tres")
const ELITE = preload("res://data/missions/elite_slime_outbreak.tres")
const BOSS = preload("res://data/missions/ancient_treant.tres")

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

func defeat_run() -> bool:
	while main.mission_run.mission_state == MissionRun.State.IN_PROGRESS:
		if not await wait_for(func(): return is_instance_valid(main.slime) or main.mission_run.mission_state != MissionRun.State.IN_PROGRESS,
				"next encounter", 8.0):
			return false
		if main.mission_run.mission_state != MissionRun.State.IN_PROGRESS:
			break
		debug_key(KEY_F8)
		await process_frame
	return true

func send(mission: MissionData, repeat: bool = false) -> void:
	main.expedition_ui.select_mission(mission)
	if repeat:
		main.expedition_ui.repeat_toggle.button_pressed = true
	await press(main.expedition_ui.send_button)

func fail_out() -> void:
	print("Milestone 12 check aborted: %d failures" % failures)
	quit(1)

func run_check() -> void:
	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	var recovery: EnergyRecovery = main.energy_recovery
	var ui = main.expedition_ui

	check(is_equal_approx(recovery.base_energy_recovery_per_second, 5.0) and is_equal_approx(recovery.recovery_rate(), 5.0)
		and is_equal_approx(recovery.ready_threshold, 1.0), "Base recovery is 5/sec data with a 100% READY threshold")
	check(main.arthur.guild_status == "READY" and ui.rest_button.disabled
		and ui.rest_button.text == "Party is fully rested.", "Full Energy at start: READY and REST disabled")

	# M: Scheduled Rest is locked behind Repeat Orders.
	main.wallet.add_gold(1200)
	check(main.guild_mastery.node_state("scheduled_rest") == "LOCKED"
		and main.guild_mastery.purchase_reason("scheduled_rest", main.wallet) == "Requires Repeat Orders"
		and not main.guild_mastery.purchase("scheduled_rest", main.wallet) and main.wallet.balance == 1200,
		"M: Scheduled Rest requires Repeat Orders")
	check(main.mastery_ui.node_buttons["scheduled_rest"].text.contains("LOCKED"), "M: Mastery UI shows Scheduled Rest LOCKED")
	main.wallet.try_spend(1200, 0)

	# A/B: manual Forest Patrol keeps its ending Energy on return.
	await send(FOREST)
	if not await defeat_run() or not await wait_for(returned, "Forest return"):
		return fail_out()
	check(main.arthur.current_energy == 55 and main.mission_run.ending_energy == 55,
		"A/B: Arthur returns with his 55 ending Energy, not 100")
	check(main.arthur.guild_status == "IDLE_AT_GUILD" and not recovery.recovery_enabled, "Returns IDLE_AT_GUILD without resting")
	await create_timer(1.3).timeout
	check(main.arthur.current_energy == 55, "A: No passive or instant recovery at the Guild")
	check(ui.rest_button.disabled, "REST waits until the summary is acknowledged")
	await press(ui.continue_button)

	# C/D: manual rest.
	check(not ui.rest_button.disabled and ui.rest_button.text == "REST" and ui.stop_rest_button.disabled, "REST available after return")
	await press(ui.rest_button)
	check(recovery.recovery_enabled and main.arthur.guild_status == "RESTING"
		and ui.rest_status.text.contains("Resting") and ui.rest_status.text.contains("+5 / sec"),
		"C: REST changes status to RESTING and shows +5 / sec")
	recovery.recover(1.0)
	check(main.arthur.current_energy == 60, "D: One second of rest restores 5 Energy (55 -> 60)")
	recovery.recover(3.0)
	check(main.arthur.current_energy == 75, "D: Three more seconds restore 15 Energy (60 -> 75)")

	# H: no dispatch while resting.
	ui.select_mission(FOREST)
	check(ui.send_button.disabled and ui.warning.text.contains("Arthur is resting."), "H: SEND ARTHUR disabled while resting")
	check(not main.start_mission(FOREST) and main.mission_run.mission_state == MissionRun.State.IDLE,
		"H: start_mission rejects dispatch while RESTING")

	# F: stopping rest keeps current Energy.
	await press(ui.stop_rest_button)
	check(not recovery.recovery_enabled and main.arthur.guild_status == "IDLE_AT_GUILD" and main.arthur.current_energy == 75,
		"F: STOP REST keeps 75 Energy and returns to IDLE_AT_GUILD")
	await create_timer(1.2).timeout
	check(main.arthur.current_energy == 75, "F: Energy does not change after rest stops")

	# E/G: clamp at max and become READY.
	var ready_hits: Array[int] = [0]
	recovery.ready_reached.connect(func(): ready_hits[0] += 1)
	await press(ui.rest_button)
	recovery.recover(60.0)
	check(main.arthur.current_energy == 100 and main.arthur.max_energy == 100, "E: Recovery clamps at Max Energy")
	check(main.arthur.guild_status == "READY" and not recovery.recovery_enabled and ready_hits[0] == 1,
		"G: Arthur becomes READY at 100 Energy and rest ends")
	check(ui.rest_button.disabled and ui.rest_button.text == "Party is fully rested.", "Fully rested disables REST")

	# J: predictions use actual current Energy.
	var config: ExpeditionStopConfig = main.mission_run.stop_config
	check(StopConditionEvaluator.predict(FOREST, 100, 100, config) == "LIKELY TO COMPLETE"
		and StopConditionEvaluator.predict(FOREST, 55, 100, config) == "RISK OF RETREAT"
		and StopConditionEvaluator.predict(NEST, 55, 100, config) == "RISK OF RETREAT",
		"J: Evaluator result depends on starting Energy")
	ui.select_mission(FOREST)
	check(ui.prediction == "LIKELY TO COMPLETE", "J: Board predicts Forest Patrol completion at 100 Energy")
	debug_key(KEY_0)
	check(main.arthur.current_energy == 40 and main.arthur.guild_status == "IDLE_AT_GUILD",
		"Energy drop at Guild moves READY back to IDLE_AT_GUILD")
	check(ui.prediction == "RISK OF RETREAT" and ui.details.text.contains("Arthur Energy: 40 / 100"),
		"J: Board prediction refreshes from Arthur's current 40 Energy")

	# I: manual dispatch at partial Energy.
	check(not ui.send_button.disabled, "I: SEND ARTHUR is enabled at partial Energy when not resting")
	await press(ui.send_button)
	check(main.mission_run.mission_state == MissionRun.State.IN_PROGRESS and main.arthur.guild_status == "ON_EXPEDITION",
		"I: Arthur can be dispatched manually at 40 Energy")
	if not await defeat_run() or not await wait_for(returned, "partial-energy return"):
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.RETREATED and main.arthur.current_energy == 25,
		"I: Partial-energy run resolves normally with real Energy")
	await press(ui.continue_button)
	debug_key(KEY_8)
	check(main.arthur.current_energy == 100 and main.arthur.guild_status == "READY", "Debug restore Energy sets READY")

	# K/L: Repeat Orders without Scheduled Rest pauses.
	main.wallet.add_gold(250)
	main.guild_mastery.purchase("repeat_orders", main.wallet)
	check(main.guild_mastery.node_state("scheduled_rest") == "AVAILABLE" or main.wallet.balance < 1200,
		"Scheduled Rest unlocks for purchase after Repeat Orders")
	await send(FOREST, true)
	check(main.repeat_orders.repeat_enabled and main.repeat_orders.repeat_run_count == 1, "Repeat session started")
	if not await defeat_run() or not await wait_for(func(): return main.repeat_orders.paused_for_recovery, "repeat pause", 10.0):
		return fail_out()
	check(main.repeat_orders.repeat_enabled and main.repeat_orders.pending_restart and main.repeat_orders.mission_id == FOREST.id
		and main.repeat_orders.stop_reason == "Repeat Orders paused: Arthur needs to recover.",
		"K: Successful run with 55 Energy pauses Repeat Orders for recovery")
	check(main.repeat_status_label.text.contains("Repeat Orders paused: Arthur needs to recover.") and ui.visible,
		"K: Pause message is shown and the board is available")
	await create_timer(3.0).timeout
	check(not recovery.recovery_enabled and main.arthur.guild_status == "IDLE_AT_GUILD" and main.arthur.current_energy == 55
		and main.mission_run.mission_state == MissionRun.State.IDLE, "L: No auto-rest and no redispatch without Scheduled Rest")
	await press(ui.rest_button)
	recovery.recover(20.0)
	await create_timer(3.0).timeout
	check(main.arthur.guild_status == "READY" and main.mission_run.mission_state == MissionRun.State.IDLE
		and main.repeat_orders.paused_for_recovery and main.repeat_orders.repeat_run_count == 1,
		"L: Reaching READY after manual rest does not auto-resume without Scheduled Rest")
	await press(ui.send_button)
	check(main.repeat_orders.repeat_run_count == 2 and not main.repeat_orders.paused_for_recovery
		and main.mission_run.mission_id == FOREST.id, "Manual dispatch resumes the paused repeat session")
	main._stop_repeat_after_current()
	if not await defeat_run() or not await wait_for(returned, "cancelled repeat return"):
		return fail_out()
	await press(ui.continue_button)

	# N/S: Scheduled Rest purchase and ownership source of truth.
	main.wallet.add_gold(1200 - main.wallet.balance)
	check(main.guild_mastery.node_state("scheduled_rest") == "AVAILABLE", "Scheduled Rest AVAILABLE with prerequisite and Gold")
	check(main.guild_mastery.purchase("scheduled_rest", main.wallet) and main.wallet.balance == 0,
		"N: Scheduled Rest purchase deducts exactly 1200 Gold")
	check(main.guild_mastery.node_state("scheduled_rest") == "OWNED"
		and main.mastery_ui.node_buttons["scheduled_rest"].text.contains("OWNED"), "N: Mastery model and UI report OWNED")
	check(main.repeat_orders.scheduled_rest_owned and not "scheduled_rest_unlocked" in main.repeat_orders
		and not "scheduled_rest_unlocked" in recovery, "S: Ownership is derived, no duplicate unlock flag")
	main.guild_mastery.unlocked_ids.erase("scheduled_rest")
	check(not main.repeat_orders.scheduled_rest_owned, "S: Removing Mastery ownership removes Scheduled Rest")
	main.guild_mastery.unlocked_ids.append("scheduled_rest")

	# O/P: Scheduled Rest loop at the real 5/sec rate.
	await press(ui.rest_button)
	recovery.recover(20.0)
	await send(FOREST, true)
	if not await defeat_run() or not await wait_for(func(): return recovery.recovery_enabled, "scheduled auto-rest", 10.0):
		return fail_out()
	check(main.arthur.guild_status == "RESTING" and main.repeat_orders.paused_for_recovery and main.arthur.current_energy < 100,
		"O: Successful repeat run starts RESTING automatically")
	check(main.repeat_status_label.text.contains("Scheduled Rest"), "O: Status explains Scheduled Rest")
	var rest_started: int = Time.get_ticks_msec()
	if not await wait_for(func(): return main.arthur.guild_status == "READY", "Scheduled Rest READY", 15.0):
		return fail_out()
	var rest_seconds: float = (Time.get_ticks_msec() - rest_started) / 1000.0
	check(rest_seconds > 7.0 and rest_seconds < 11.0, "D/O: 55 -> 100 takes about 9 seconds at 5/sec (%.1fs)" % rest_seconds)
	check(main.mission_run.mission_state == MissionRun.State.IDLE, "Short preparation delay before redispatch")
	if not await wait_for(func(): return main.mission_run.mission_state == MissionRun.State.IN_PROGRESS, "Scheduled Rest redispatch", 5.0):
		return fail_out()
	check(main.mission_run.mission_id == FOREST.id and main.repeat_orders.repeat_run_count == 2
		and main.arthur.current_energy == 100 and not main.repeat_orders.paused_for_recovery,
		"P: Same mission redispatches automatically at READY")

	# Q: retreat stops Repeat Orders even with Scheduled Rest owned.
	debug_key(KEY_0)
	if not await defeat_run() or not await wait_for(returned, "repeat retreat return"):
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.RETREATED and not main.repeat_orders.repeat_enabled
		and main.repeat_orders.stop_reason == "Repeat Orders stopped: Arthur retreated due to Low Energy.",
		"Q: Retreat stops Repeat Orders with Scheduled Rest owned")
	await create_timer(4.0).timeout
	check(not recovery.recovery_enabled and main.arthur.guild_status == "IDLE_AT_GUILD"
		and main.mission_run.mission_state == MissionRun.State.IDLE and main.arthur.current_energy == 25,
		"Q: No auto-rest and no redispatch after retreat")
	await press(ui.continue_button)

	# Slime Nest from full Energy retreats at 28 and stays stopped.
	debug_key(KEY_8)
	await send(NEST, true)
	if not await defeat_run() or not await wait_for(returned, "Nest retreat return"):
		return fail_out()
	check(main.arthur.current_energy == 28 and not main.repeat_orders.repeat_enabled
		and main.repeat_orders.stop_reason.contains("Low Energy"), "Q: Slime Nest retreats at 28 and Repeat stops")
	await create_timer(4.0).timeout
	check(not recovery.recovery_enabled and main.mission_run.mission_state == MissionRun.State.IDLE,
		"Q: Slime Nest is not restarted after retreat")
	await press(ui.continue_button)
	await press(ui.rest_button)
	check(recovery.recovery_enabled and main.arthur.guild_status == "RESTING", "Arthur may manually rest after a retreat")
	await press(ui.stop_rest_button)

	# R: special missions stay manual.
	check(not main.repeat_orders.is_mission_eligible(SUPPLY) and not main.repeat_orders.is_mission_eligible(ELITE)
		and not main.repeat_orders.is_mission_eligible(BOSS), "R: Rotating, Elite and Boss remain non-repeatable")
	debug_key(KEY_3)
	ui.select_opportunity()
	check(ui.repeat_toggle.disabled and ui.repeat_reason.text == "Special missions cannot be repeated",
		"R: Scheduled Rest does not make Elite repeatable")

	# Future extension hooks (no content yet).
	recovery.add_rate_buff("tavern_meal", 1.2, 600.0)
	check(is_equal_approx(recovery.recovery_rate(), 6.0), "Timed rate buff hook (+20%) modifies recovery")
	recovery._expire_buffs(601.0)
	check(is_equal_approx(recovery.recovery_rate(), 5.0), "Timed rate buff expires")
	debug_key(KEY_7)
	check(is_equal_approx(recovery.recovery_rate(), 50.0), "Debug key 7 multiplies recovery by 10")
	debug_key(KEY_7)
	var before: int = main.arthur.current_energy
	recovery.pending_dispatch_energy_bonus = 10
	recovery.apply_dispatch_bonus()
	check(main.arthur.current_energy == mini(before + 10, 100) and recovery.pending_dispatch_energy_bonus == 0,
		"Next-dispatch Energy bonus hook applies once")
	recovery.set_ready_threshold(0.8)
	check(recovery.ready_energy() == 80, "Ready threshold is configurable")
	recovery.set_ready_threshold(1.0)

	print("Milestone 12 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
