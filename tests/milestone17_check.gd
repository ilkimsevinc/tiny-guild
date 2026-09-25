extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const PC = preload("res://scripts/presentation_controller.gd")

var main: Node2D
var ui
var guild: GuildController
var presentation: PresentationController
var arthur: HeroController
var mimi: HeroController
var failures: int = 0
var headless: bool = false

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

func press(button: BaseButton) -> void:
	if not button.disabled and button.is_visible_in_tree():
		button.pressed.emit()
	await process_frame

func debug_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	main._unhandled_key_input(event)

func in_progress() -> bool:
	return main.mission_run.mission_state == MissionRun.State.IN_PROGRESS

func returned() -> bool:
	return main.mission_run.summary_pending and main.mission_run.mission_state == MissionRun.State.IDLE

func select_party(ids: Array[String]) -> void:
	for member in [arthur, mimi]:
		var box: CheckBox = ui.party_checks[member.hero_id]
		if box.button_pressed != (member.hero_id in ids):
			box.toggled.emit(member.hero_id in ids)
	await process_frame

func play_run() -> bool:
	while in_progress():
		if not await wait_for(func(): return is_instance_valid(main.slime) or not in_progress(), "next encounter", 8.0):
			return false
		if not in_progress():
			break
		debug_key(KEY_F8)
		await process_frame
	return await wait_for(returned, "return to Guild", 10.0)

func gameplay_snapshot() -> Dictionary:
	return {"arthur_level": arthur.progression.level, "arthur_xp": arthur.progression.xp,
		"mimi_level": mimi.progression.level, "gold": main.gold,
		"arthur_energy": arthur.current_energy, "mimi_energy": mimi.current_energy,
		"guild_tokens": main.wallet.guild_tokens, "inventory_count": main.inventory.get_items().size(),
		"mastery_owned": main.guild_mastery.unlocked_ids.duplicate(),
		"mission_id": main.mission_run.mission_id}

func fail_out() -> void:
	print("Milestone 17 check aborted: %d failures" % failures)
	quit(1)

func run_check() -> void:
	headless = DisplayServer.get_name() == "headless"
	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	ui = main.expedition_ui
	guild = main.guild
	presentation = main.presentation
	arthur = main.arthur
	mimi = main.mimi

	# --- Pure geometry math: headless-safe, no real display needed -----------
	var screen := Rect2i(0, 0, 1920, 1040) # excludes a hypothetical 40px taskbar
	check(PC.clamp_window_size(Vector2i(1280, 320), screen) == Vector2i(1280, 320),
		"Pure math: desired size fits the screen unchanged")
	check(PC.clamp_window_size(Vector2i(3000, 40), screen) == Vector2i(1920, 120),
		"Pure math: oversized/undersized requests are clamped to the screen and a sane minimum")
	var bottom: Vector2i = PC.bottom_centered_position(Vector2i(1280, 320), screen, 8)
	check(bottom == Vector2i(320, 712), "J: Reset position computes bottom-centered placement (%s)" % str(bottom))
	check(PC.clamp_to_screen(Vector2i(-5000, 500), Vector2i(1280, 320), screen, 160) ==
		Vector2i(-1120, 500), "I: A drag far off-screen still keeps 160px reachable")
	check(PC.clamp_to_screen(Vector2i(900, 500), Vector2i(1280, 320), screen, 160).y <= screen.position.y + screen.size.y - 320,
		"I: Vertical placement always stays fully inside the screen")

	# --- A/B: defaults ----------------------------------------------------------
	check(presentation.current == PC.Mode.DEVELOPMENT, "A: Default mode is DEVELOPMENT")
	if not headless:
		check(main.get_viewport().get_visible_rect().size == Vector2(1280, 720), "B: Development viewport is 1280x720")
	check(not presentation.is_desktop() and main.dev_hud.visible and not main.desktop_hud.visible,
		"Development mode shows the full HUD, not the compact one")

	# --- C/D: mode switch preserves state, no reload ---------------------------
	main.wallet.add_gold(1234)
	main.wallet.add_guild_tokens(3)
	arthur.progression.add_xp(20)
	var before: Dictionary = gameplay_snapshot()
	var same_instance: Node2D = main
	presentation.set_mode(PC.Mode.DESKTOP)
	await process_frame
	check(main == same_instance and is_instance_valid(main) and main.is_inside_tree(),
		"C: Desktop mode is entered without a scene reload")
	check(gameplay_snapshot() == before, "D: Gameplay state (Gold, XP, Tokens, Energy) survives the mode switch")
	check(presentation.is_desktop() and not main.dev_hud.visible and main.desktop_hud.visible,
		"Desktop mode shows the compact HUD, not the full one")

	# --- E/F/G/H: real OS window state (meaningful only with a real window) ----
	if not headless:
		var expected_size: Vector2i = presentation.target_window_size()
		check(DisplayServer.window_get_size() == expected_size, "E: Desktop window size is applied (%s)" % str(expected_size))
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "F: Desktop window is borderless")
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP), "G: Desktop window is always-on-top")
		var screen_rect: Rect2i = presentation.usable_screen_rect()
		var pos: Vector2i = DisplayServer.window_get_position()
		check(pos.x + expected_size.x > screen_rect.position.x and pos.x < screen_rect.position.x + screen_rect.size.x,
			"I: Desktop window placement stays reachable within the screen")
		presentation.set_mode(PC.Mode.DEVELOPMENT)
		await process_frame
		check(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS)
			and not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP),
			"H: Returning to Development restores a decorated, non-topmost window")
		check(DisplayServer.window_get_size() == PC.DEV_SIZE, "Development window size is restored to 1280x720")
		presentation.set_mode(PC.Mode.DESKTOP)
		await process_frame

	# --- K/L/M/N/O: Guild fits and stays usable in the Desktop window ----------
	var win_size: Vector2i = presentation.target_window_size()
	check(guild.layout.bounds.position.x >= 0.0 and guild.layout.bounds.end.x <= win_size.x,
		"K: Guild layout fits inside the Desktop window width")
	for member in [arthur, mimi]:
		var body: GuildHeroAvatar = guild.avatar(member)
		var zone_data: GuildZoneData = guild.zone(body.zone_id)
		check(zone_data != null and zone_data.contains_x(body.position.x, GuildController.ZONE_MARGIN)
			and body.global_position.y < win_size.y, "L: %s stays inside a visible Guild zone in Desktop mode" % member.display_name)
	check(absf(guild.avatar(arthur).position.x - guild.avatar(mimi).position.x) >= GuildController.MIN_SPACING,
		"O: Arthur and Mimi do not overlap in the Desktop Guild")
	var rest_zone: GuildZoneData = guild.zone(guild.rest_zone_id())
	check(rest_zone != null and rest_zone.right <= win_size.x, "M: Rest Area remains reachable inside the Desktop window")
	var board_zone: GuildZoneData = guild.zone(guild.board_zone_id())
	check(board_zone != null and board_zone.right <= win_size.x, "N: Expedition Board remains reachable inside the Desktop window")

	# K (narrow-screen rescale): the same six zones adapt to a narrower width.
	var narrow: GuildLayout = main.base_guild_layout.scaled_for(640.0, 300.0)
	check(narrow.zones.size() == main.base_guild_layout.zones.size() and narrow.bounds.size.x <= 640.0
		and narrow.find_zone("expedition_board") != null, "K: A narrower width rescales the same zone data, not a duplicate layout")

	# --- S/T/U: overlays open, close, and respond to ESC ------------------------
	check(not ui.visible, "Board overlay starts closed in Desktop mode")
	var missions_button: Button = main.desktop_hud.find_children("*", "Button", true, false).filter(func(b): return b.text == "MISSIONS")[0]
	await press(missions_button)
	check(ui.visible and ui.offset_bottom <= float(win_size.y), "S: MISSIONS opens the board overlay sized to fit the Desktop window")
	await press(ui.close_button)
	check(not ui.visible, "T: CLOSE hides the board overlay")
	await press(missions_button)
	check(ui.visible, "Reopened the board overlay for the ESC check")
	debug_key(KEY_ESCAPE)
	check(not ui.visible, "U: ESC closes the active Desktop overlay")
	var heroes_button: Button = main.desktop_hud.find_children("*", "Button", true, false).filter(func(b): return b.text == "HEROES")[0]
	await press(heroes_button)
	check(main.sidebar.visible and main.sidebar.current_tab == 1 and main.sidebar_close_button.visible,
		"HEROES opens the Sidebar overlay on the Skills tab")
	debug_key(KEY_ESCAPE)
	check(not main.sidebar.visible, "U: ESC also closes the Sidebar overlay")

	# --- P/Q/R: Desktop combat formation, Boss included -------------------------
	await select_party(["arthur", "mimi"])
	await press(missions_button) # The board was left closed by the ESC check above.
	ui.select_mission(FOREST)
	await press(ui.send_button)
	if not await wait_for(func(): return in_progress() and arthur.visible, "Desktop dispatch", 6.0):
		return fail_out()
	check(main.party.formation.slots == ["arthur", "mimi"], "P: Desktop combat formation is still FRONT Arthur / BACK Mimi")
	if not await wait_for(func(): return is_instance_valid(main.slime), "Desktop encounter", 6.0):
		return fail_out()
	check(arthur.global_position.y > 0.0 and arthur.global_position.y < float(win_size.y)
		and main.slime.global_position.y > 0.0 and main.slime.global_position.y < float(win_size.y),
		"Combat stays on-screen (Stage offset applied) in Desktop mode")
	check(mimi.global_position.distance_to(arthur.global_position) >= PartyFormation.MIN_HERO_SPACING - 0.5,
		"Q: Mimi keeps her distance behind Arthur in Desktop combat")
	if not await play_run():
		return fail_out()
	check(ui.summary.text.contains("Party") and ui.offset_bottom <= float(win_size.y) + 0.5,
		"V: Mission Summary uses the same compact, in-bounds overlay")
	await press(ui.continue_button)
	debug_key(KEY_8)

	# --- Y: special mission notification stays visible and in-bounds -----------
	debug_key(KEY_4)
	check(main.notification_label.text == "BOSS PORTAL OPENED"
		and main.notification_label.offset_right <= float(win_size.x), "Y: Boss notification is compact and fits the Desktop window")
	ui.select_opportunity()
	await press(ui.send_button)
	if not await wait_for(func(): return in_progress() and is_instance_valid(main.slime), "Boss encounter", 6.0):
		return fail_out()
	check(main.mission_run.mission.special_type == "BOSS" and is_finite(main.slime.global_position.x)
		and is_finite(main.slime.global_position.y), "R: Ancient Treant renders at a valid position in Desktop mode")
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)
	debug_key(KEY_8)

	# --- W: Repeat Orders still works in Desktop mode ---------------------------
	main.wallet.add_gold(1450)
	main.guild_mastery.purchase("repeat_orders", main.wallet)
	main.guild_mastery.purchase("scheduled_rest", main.wallet)
	debug_key(KEY_7)
	await select_party(["arthur"])
	ui.select_mission(FOREST)
	ui.repeat_toggle.button_pressed = true
	await press(ui.send_button)
	if not await play_run():
		return fail_out()
	if not await wait_for(func(): return in_progress() and main.repeat_orders.repeat_run_count == 2, "Desktop repeat redispatch", 15.0):
		return fail_out()
	check(true, "W: Repeat Orders redispatches correctly while in Desktop mode")
	main._stop_repeat_after_current()
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)

	# --- X: Mission Queue still works in Desktop mode ---------------------------
	main.wallet.add_gold(10000)
	main.wallet.add_guild_tokens(1)
	main.guild_mastery.purchase("mission_queue", main.wallet)
	debug_key(KEY_8)
	await select_party(["arthur"])
	main.mission_queue.clear()
	main.mission_queue.add(FOREST)
	main.mission_queue.add(FOREST)
	await press(ui.queue_buttons.start)
	if not await play_run():
		return fail_out()
	if not await wait_for(func(): return in_progress() and main.mission_queue.session_run_count == 2, "Desktop queue redispatch", 15.0):
		return fail_out()
	check(true, "X: Mission Queue redispatches correctly while in Desktop mode")
	if not await play_run():
		return fail_out()
	check(main.mission_queue.finished, "Mission Queue completes normally in Desktop mode")
	await press(ui.continue_button)

	# --- Z: switching back to Development preserves everything -----------------
	var before_switch_back: Dictionary = gameplay_snapshot()
	presentation.set_mode(PC.Mode.DEVELOPMENT)
	await process_frame
	check(not presentation.is_desktop() and main.dev_hud.visible and not main.desktop_hud.visible,
		"Z: Development HUD is restored")
	check(gameplay_snapshot() == before_switch_back, "Z: Switching Desktop -> Development preserves heroes and progression")
	check(main.stage.position == Vector2.ZERO, "Z: Stage offset resets to zero in Development mode")

	print("Milestone 17 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
