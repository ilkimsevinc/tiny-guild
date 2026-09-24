extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const NEST = preload("res://data/missions/slime_nest.tres")
const TRAIL = preload("res://data/missions/treasure_trail.tres")
const SUPPLY = preload("res://data/missions/forest_supply_run.tres")
const ELITE = preload("res://data/missions/elite_slime_outbreak.tres")
const BOSS = preload("res://data/missions/ancient_treant.tres")
const GEL = preload("res://data/items/slime_gel.tres")
const STATUS = MissionQueueEntry.Status

var main: Node2D
var queue: MissionQueueState
var ui
var failures: int = 0
var run_gold: int = 0
var run_xp: int = 0
var run_loot: Dictionary = {}

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
	if not button.disabled and button.is_visible_in_tree():
		button.pressed.emit()
	await process_frame

func debug_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	main._unhandled_key_input(event)

func returned() -> bool:
	return main.mission_run.summary_pending and main.mission_run.mission_state == MissionRun.State.IDLE

func in_progress() -> bool:
	return main.mission_run.mission_state == MissionRun.State.IN_PROGRESS

# Defeats every encounter with a forced Slime Gel drop, then records the run's totals.
func play_run() -> bool:
	while in_progress():
		if not await wait_for(func(): return is_instance_valid(main.slime) or not in_progress(), "next encounter", 8.0):
			return false
		if not in_progress():
			break
		main.debug_next_drop = GEL
		debug_key(KEY_F8)
		await process_frame
	if not await wait_for(returned, "return to Guild", 10.0):
		return false
	run_gold += main.mission_run.total_gold()
	run_xp += main.mission_run.total_xp()
	for item_id in main.mission_run.collected_loot:
		run_loot[item_id] = run_loot.get(item_id, 0) + main.mission_run.collected_loot[item_id]
	return true

# Mirrors a mouse click: select() alone does not emit item_selected.
func pick(index: int) -> void:
	ui.queue_list.select(index)
	ui.queue_list.item_selected.emit(index)

func fill(missions: Array) -> void:
	queue.clear()
	for mission in missions:
		queue.add(mission)

func fail_out() -> void:
	print("Milestone 13 check aborted: %d failures" % failures)
	quit(1)

func run_check() -> void:
	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	queue = main.mission_queue
	ui = main.expedition_ui

	# A-D: Mastery gating.
	check(not queue.unlocked and main.guild_mastery.node_state("mission_queue") == "LOCKED"
		and not ui.queue_box.visible and not ui.add_queue_buttons[FOREST.id].visible, "A: Mission Queue starts locked and hidden")
	var fresh := GuildMasteryState.new()
	check(fresh.purchase_reason("mission_queue", main.wallet) == "Requires Repeat Orders and Scheduled Rest",
		"B: Mission Queue requires Repeat Orders")
	fresh.free()
	main.wallet.add_gold(250)
	main.guild_mastery.purchase("repeat_orders", main.wallet)
	main.wallet.add_gold(10000)
	main.wallet.add_guild_tokens(1)
	check(main.guild_mastery.purchase_reason("mission_queue", main.wallet) == "Requires Scheduled Rest"
		and not main.guild_mastery.purchase("mission_queue", main.wallet) and main.wallet.balance == 10000,
		"C: Mission Queue requires Scheduled Rest")
	main.wallet.try_spend(10000, 1)
	main.wallet.add_gold(1200)
	main.guild_mastery.purchase("scheduled_rest", main.wallet)
	main.wallet.add_gold(10000)
	check(main.guild_mastery.node_state("mission_queue") == "AVAILABLE"
		and main.guild_mastery.purchase_reason("mission_queue", main.wallet) == "Not enough Guild Tokens"
		and not main.guild_mastery.purchase("mission_queue", main.wallet) and main.wallet.balance == 10000,
		"D: 10,000 Gold without a Guild Token cannot buy Mission Queue")
	main.wallet.try_spend(1, 0)
	main.wallet.add_guild_tokens(1)
	check(not main.guild_mastery.purchase("mission_queue", main.wallet) and main.wallet.balance == 9999,
		"D: 9,999 Gold + 1 Token cannot buy Mission Queue")
	main.wallet.add_gold(1)
	check(main.guild_mastery.purchase("mission_queue", main.wallet) and main.wallet.balance == 0
		and main.wallet.guild_tokens == 0 and queue.unlocked, "D: Purchase spends exactly 10,000 Gold + 1 Guild Token")
	check(main.mastery_ui.node_buttons["mission_queue"].text.contains("OWNED") and ui.queue_box.visible
		and ui.add_queue_buttons[FOREST.id].visible and ui.send_button.visible, "Queue UI appears; SEND ARTHUR remains")

	# E-J: capacity and eligibility.
	await press(ui.add_queue_buttons[FOREST.id])
	await press(ui.add_queue_buttons[FOREST.id])
	await press(ui.add_queue_buttons[TRAIL.id])
	check(queue.capacity() == 3 and queue.entries.size() == 3 and not queue.add(NEST)
		and ui.add_queue_buttons[NEST.id].disabled, "E: Queue capacity is 3")
	check(queue.entries.map(func(e): return e.mission_id) == [FOREST.id, FOREST.id, TRAIL.id]
		and queue.entries[0] != queue.entries[1], "F/G: Persistent missions queue in order, duplicates kept separate")
	check(ui.queue_list.get_item_text(0).contains("Forest Patrol") and ui.queue_list.get_item_text(2).contains("Treasure Trail"),
		"Queue list shows configured orders")
	queue.clear()
	for special in [ELITE, BOSS, SUPPLY]:
		check(queue.add_reason(special) == "Special missions cannot be queued" and not queue.add(special),
			"H/I/J: %s cannot be queued" % special.display_name)
	check(queue.entries.is_empty(), "Rejected special missions leave the queue empty")
	fill([FOREST, NEST, TRAIL])
	pick(2)
	await press(ui.queue_buttons.up)
	check(queue.entries.map(func(e): return e.mission_id) == [FOREST.id, TRAIL.id, NEST.id], "Move up reorders entries")
	pick(0)
	await press(ui.queue_buttons.down)
	check(queue.entries.map(func(e): return e.mission_id) == [TRAIL.id, FOREST.id, NEST.id], "Move down reorders entries")
	pick(2)
	await press(ui.queue_buttons.remove)
	check(queue.entries.map(func(e): return e.mission_id) == [TRAIL.id, FOREST.id], "Remove deletes the selected entry")
	await press(ui.queue_buttons.clear)
	check(queue.entries.is_empty(), "Clear empties the queue")

	# Y (part): a Repeat Orders session is replaced when the queue starts.
	ui.select_mission(FOREST)
	ui.repeat_toggle.button_pressed = true
	check(main.repeat_orders.repeat_enabled, "Repeat Orders armed before the queue starts")
	fill([FOREST, FOREST, FOREST])
	debug_key(KEY_7) # Recovery x10 keeps the test short; rate itself is covered in Milestone 12.
	var inventory_before: Dictionary = {}
	for item_id in [GEL.id]:
		inventory_before[item_id] = main.inventory.quantity(item_id)
	var gold_before: int = main.gold

	# K: START QUEUE dispatches the first entry.
	await press(ui.queue_buttons.start)
	check(in_progress() and main.mission_run.mission_id == FOREST.id and queue.running
		and queue.entries[0].entry_status == STATUS.ACTIVE and queue.session_run_count == 1 and not ui.visible,
		"K: START QUEUE dispatches the first entry")
	check(not main.repeat_orders.repeat_enabled and main.repeat_orders.repeat_run_count == 0,
		"Y: Starting the queue ends the Repeat Orders session")
	ui.select_mission(FOREST)
	check(ui.repeat_toggle.disabled and ui.repeat_reason.text == "Repeat Orders unavailable while Expedition Orders are active.",
		"Y: Repeat Mission control disabled while the queue is active")
	check(not main.start_mission(FOREST, null, true) and not main.start_mission(NEST), "Y: Neither Repeat nor manual dispatch can take over")

	# Z: Boss spawn does not interrupt.
	debug_key(KEY_4)
	check(main.board_rotation.slot != null and main.board_rotation.slot.special_type == "BOSS"
		and main.notification_label.text == "BOSS PORTAL OPENED" and main.mission_run.mission_id == FOREST.id
		and queue.running, "Z: Boss Portal notifies without interrupting the queue")
	var boss_slot: MissionInstance = main.board_rotation.slot

	if not await play_run():
		return fail_out()
	check(not ui.continue_button.visible and ui.summary.text.contains("Expedition Orders"),
		"Brief individual result shows without requiring CONTINUE")
	check(queue.entries[0].entry_status == STATUS.COMPLETED and queue.entries[1].entry_status == STATUS.ACTIVE
		and queue.current_index == 1, "O/L: First entry COMPLETED and queue advances to the second")
	check(queue.progress_text() == "1 / 3" and main.queue_status_label.text.contains("Queue: 1 / 3"), "P: Progress shows 1 / 3")
	if not await wait_for(func(): return main.energy_recovery.recovery_enabled, "rest between orders", 6.0):
		return fail_out()
	check(main.arthur.guild_status == "RESTING" and not in_progress() and main.arthur.current_energy < 100,
		"M: Arthur rests between queued missions")
	check(main.queue_status_label.text.contains("Next Mission: Forest Patrol") and ui.queue_status.text.contains("Next Mission"),
		"Queue UI shows the next mission while resting")
	if not await wait_for(in_progress, "second order dispatch", 10.0):
		return fail_out()
	check(main.arthur.current_energy == 100 and queue.session_run_count == 2 and main.mission_run.mission_id == FOREST.id,
		"N/L: Second entry starts only after READY")
	check(not main.start_opportunity(boss_slot) and boss_slot.active == false and not boss_slot.claimed,
		"Z: Queue never dispatches to the Boss Portal")
	if not await play_run():
		return fail_out()
	if not await wait_for(func(): return in_progress() and queue.session_run_count == 3, "third order dispatch", 12.0):
		return fail_out()
	check(queue.progress_text() == "2 / 3", "P: Progress shows 2 / 3")
	if not await play_run():
		return fail_out()

	# U-X: completion and aggregate summary.
	check(queue.finished and not queue.enabled and queue.completed_entries == 3, "U: All entries complete; queue inactive")
	check(ui.title.text == "EXPEDITION ORDERS COMPLETE" and ui.summary.text.contains("3 / 3 missions completed")
		and ui.continue_button.visible, "U: Final EXPEDITION ORDERS COMPLETE summary")
	var summary: QueueSessionSummary = queue.summary
	check(summary.gold == run_gold and summary.gold == main.gold - gold_before and summary.gold == 180
		and ui.summary.text.contains("Gold earned: %d" % summary.gold), "V: Aggregate Gold equals all three runs (180)")
	check(summary.xp == run_xp and summary.xp == 225 and ui.summary.text.contains("XP earned: 225"), "W: Aggregate XP equals all three runs (225)")
	check(summary.loot == run_loot and summary.loot.get(GEL.id, 0) == 9
		and main.inventory.quantity(GEL.id) - inventory_before[GEL.id] == 9, "X: Aggregate loot matches runs and Inventory")
	check(summary.missions_completed == 3 and summary.retreats == 0 and summary.total_encounters == 9, "Session counts are tracked")
	await create_timer(4.0).timeout
	check(not in_progress() and main.mission_run.summary_pending, "U: The whole queue does not repeat automatically")
	await press(ui.continue_button)
	check(ui.board.visible and queue.entries.size() == 3, "Continue returns to the board with orders preserved")

	# Q-S: retreat pauses; resume retries the same entry.
	debug_key(KEY_8)
	fill([FOREST, NEST, TRAIL])
	await press(ui.queue_buttons.start)
	if not await play_run():
		return fail_out()
	if not await wait_for(func(): return in_progress() and main.mission_run.mission_id == NEST.id, "Slime Nest order", 12.0):
		return fail_out()
	if not await play_run():
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.RETREATED and queue.paused and queue.enabled
		and queue.pause_reason == "Arthur retreated from Slime Nest due to Low Energy.", "Q: Retreat pauses the queue with reason")
	check(queue.entries[1].entry_status == STATUS.BLOCKED and queue.entries[1].completed_count == 0
		and queue.entries[2].entry_status == STATUS.PENDING and queue.current_index == 1, "Q: Retreated entry stays incomplete")
	check(ui.summary.text.contains("QUEUE PAUSED") and ui.continue_button.visible
		and main.queue_status_label.text.contains("QUEUE PAUSED"), "Q: QUEUE PAUSED is shown")
	await create_timer(4.0).timeout
	check(not in_progress() and not main.energy_recovery.recovery_enabled and main.arthur.current_energy == 28,
		"R: Queue does not advance or auto-rest after retreat")
	await press(ui.continue_button)
	check(queue.can_edit(2) and not queue.can_edit(1) and not queue.can_edit(0), "Only future PENDING entries are editable while paused")
	check(ui.queue_buttons.resume.visible and not ui.queue_buttons.resume.disabled, "RESUME QUEUE available after pause")
	await press(ui.rest_button)
	if not await wait_for(func(): return main.arthur.guild_status == "READY", "manual rest before resume", 5.0):
		return fail_out()
	await create_timer(2.5).timeout
	check(not in_progress(), "Paused queue does not auto-resume after READY")
	await press(ui.queue_buttons.resume)
	check(in_progress() and main.mission_run.mission_id == NEST.id and main.mission_run.current_encounter == 1
		and queue.entries[1].entry_status == STATUS.ACTIVE and not queue.paused, "S: Resume retries Slime Nest from encounter 1")
	if not await play_run():
		return fail_out()
	check(queue.paused and queue.summary.retreats == 2, "Second retreat pauses again")
	await press(ui.continue_button)
	await press(ui.queue_buttons.stop)
	check(not queue.enabled and queue.entries.size() == 3, "STOP at the Guild ends the session but keeps orders")

	# T: STOP QUEUE during a mission.
	debug_key(KEY_8)
	fill([FOREST, FOREST])
	await press(ui.queue_buttons.start)
	await press(main.stop_queue_button)
	check(in_progress() and queue.stop_requested and queue.enabled, "T: STOP QUEUE does not cancel current combat")
	if not await play_run():
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and not queue.enabled
		and queue.entries.size() == 2 and queue.entries[0].entry_status == STATUS.COMPLETED, "T: Current mission finishes; session ends")
	await create_timer(4.0).timeout
	check(not in_progress() and not main.energy_recovery.recovery_enabled, "T: No next queued mission starts")
	await press(ui.continue_button)

	# One-off dispatch still works when the queue is not active.
	debug_key(KEY_8)
	ui.select_mission(FOREST)
	await press(ui.send_button)
	check(in_progress() and main.mission_queue.session_run_count == 1 and not queue.awaiting_result, "Manual SEND works when queue inactive")
	if not await play_run():
		return fail_out()
	check(not queue.enabled and main.expedition_ui.continue_button.visible, "One-off mission never touches queue state")

	# Future Boss-override hook: pause after current mission.
	var hook := MissionQueueState.new()
	hook.setup(main.guild_mastery)
	hook.add(FOREST)
	hook.add(FOREST)
	hook.start()
	hook.record_dispatch(FOREST)
	hook.request_pause_after_current()
	var fake := MissionRun.new()
	fake.result_status = MissionRun.Result.COMPLETED
	check(hook.record_result(fake) == MissionQueueState.Outcome.PAUSED and hook.current_index == 1
		and hook.entries[0].entry_status == STATUS.COMPLETED, "PAUSE AFTER CURRENT hook pauses at the next entry")
	fake.free()
	hook.free()

	print("Milestone 13 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
