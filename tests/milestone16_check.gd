extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const LAYOUT = preload("res://data/guild/guild_layout.tres")
const VIEW = ViewStateController.View
const REQUIRED_ZONES: Dictionary = {"tavern": "TAVERN", "rest": "REST", "social": "GENERAL",
	"expedition_board": "EXPEDITION_BOARD", "training": "TRAINING", "blacksmith": "BLACKSMITH"}

var main: Node2D
var ui
var guild: GuildController
var arthur: HeroController
var mimi: HeroController
var failures: int = 0
# hero_id -> ordered list of distinct Guild zones visited ("AWAY" when departed).
var zone_history: Dictionary = {"arthur": [], "mimi": []}
var view_history: Array = []
var return_entry_x: Dictionary = {}

func _initialize() -> void:
	run_check.call_deferred()

func _physics_process(_delta: float) -> bool:
	if guild == null:
		return false
	for member in [arthur, mimi]:
		var body: GuildHeroAvatar = guild.avatar(member)
		var zone_now: String = "AWAY" if body.away else body.zone_id
		var history: Array = zone_history[member.hero_id]
		if history.is_empty() or history[-1] != zone_now:
			history.append(zone_now)
	return false

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
	if not button.disabled:
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

func settled(member: HeroController) -> bool:
	return not guild.avatar(member).moving

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

func on_view(view: VIEW) -> void:
	view_history.append(view)
	if view == VIEW.GUILD_VIEW:
		for member in main.party.active_heroes():
			return_entry_x[member.hero_id] = guild.avatar(member).position.x

func zone_bounds_ok(member: HeroController) -> bool:
	var data: GuildZoneData = guild.zone(guild.zone_of(member))
	return data != null and data.contains_x(guild.avatar(member).position.x, GuildController.ZONE_MARGIN)

func fail_out() -> void:
	print("Milestone 16 check aborted: %d failures" % failures)
	quit(1)

func run_check() -> void:
	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	ui = main.expedition_ui
	guild = main.guild
	arthur = main.arthur
	mimi = main.mimi
	main.view_state.changed.connect(on_view)

	# A/B/F: interior, zones, data-driven anchors.
	check(guild is GuildController and guild.visible and main.view_state.current == VIEW.GUILD_VIEW
		and not arthur.visible and not mimi.visible, "A: Guild interior loads in GUILD_VIEW (combat heroes hidden)")
	var zones_ok: bool = true
	for zone_id in REQUIRED_ZONES:
		var data: GuildZoneData = guild.zone(zone_id)
		zones_ok = zones_ok and data != null and data.zone_type == REQUIRED_ZONES[zone_id] and data.right > data.left
	check(zones_ok and guild.layout == LAYOUT, "B: Tavern, Rest, Social, Board, Training, Blacksmith zones exist")
	var ordered: bool = true
	for index in range(1, LAYOUT.zones.size()):
		ordered = ordered and LAYOUT.zones[index].left >= LAYOUT.zones[index - 1].right - 0.01
	check(ordered and LAYOUT.bounds.size.x > LAYOUT.bounds.size.y * 4.0, "Layout is wide, horizontal, side-by-side")
	var custom: GuildLayout = LAYOUT.duplicate(true)
	custom.find_zone("training").anchor_position = Vector2(300, 350)
	custom.find_zone("training").left = 250.0
	custom.find_zone("training").right = 350.0
	var probe := GuildController.new()
	probe.layout = custom
	root.add_child(probe)
	var probe_heroes: Array[HeroController] = [arthur]
	probe.setup(probe_heroes, {})
	check(is_equal_approx(probe.avatar(arthur).position.x, 300.0), "F: Hero spot comes from the zone anchor data")
	probe.queue_free()

	# C/D/E: starting presence.
	var arthur_body: GuildHeroAvatar = guild.avatar(arthur)
	var mimi_body: GuildHeroAvatar = guild.avatar(mimi)
	check(guild.is_in_guild(arthur) and arthur_body.visible and guild.zone_of(arthur) == "training"
		and is_equal_approx(arthur_body.position.x, guild.zone("training").anchor_position.x), "C: Arthur starts in the Guild (Training side)")
	check(guild.is_in_guild(mimi) and mimi_body.visible and guild.zone_of(mimi) == "social"
		and is_equal_approx(mimi_body.position.x, guild.zone("social").anchor_position.x), "D: Mimi starts in the Guild (Social side)")
	check(absf(arthur_body.position.x - mimi_body.position.x) >= GuildController.MIN_SPACING
		and arthur_body.position != arthur.position, "E: Different positions, not combat coordinates")
	check(arthur_body.state_name() == "GUILD_READY" and "arthur" in guild.assigned_heroes("training"), "Guild state and zone assignment tracked")

	# G/H: movement and idle wandering inside the zone.
	guild.idle_frozen = true
	var start_x: float = arthur_body.position.x
	var inside: bool = true
	var moved: bool = false
	for step in 8:
		guild.wander(arthur)
		if not await wait_for(func(): return settled(arthur), "wander step", 3.0):
			return fail_out()
		inside = inside and zone_bounds_ok(arthur) and guild.zone_of(arthur) == "training"
		moved = moved or not is_equal_approx(arthur_body.position.x, start_x)
	check(moved, "G: Hero moves inside a Guild zone")
	check(inside, "H: Idle wandering stays inside the current zone")
	guild.idle_frozen = false
	mimi_body.idle_timer = 0.01
	await physics_frame
	await physics_frame
	check(mimi_body.moving or not is_equal_approx(mimi_body.position.x, guild.zone("social").anchor_position.x) or mimi_body.idle_timer > 1.0,
		"Idle timer triggers a wander step")
	guild.idle_frozen = true

	# I: spacing when sharing a zone.
	guild.place_in_zone(arthur, "rest")
	guild.place_in_zone(mimi, "rest")
	if not await wait_for(func(): return settled(arthur) and settled(mimi), "both at rest zone", 6.0):
		return fail_out()
	var spacing_ok: bool = absf(arthur_body.position.x - mimi_body.position.x) >= GuildController.MIN_SPACING
	for step in 6:
		guild.wander(arthur)
		guild.wander(mimi)
		if not await wait_for(func(): return settled(arthur) and settled(mimi), "shared wander", 3.0):
			return fail_out()
		spacing_ok = spacing_ok and absf(arthur_body.position.x - mimi_body.position.x) >= GuildController.MIN_SPACING - 0.5
	check(spacing_ok, "I: Heroes keep minimum spacing in the same zone")
	debug_key(KEY_C)
	if not await wait_for(func(): return settled(arthur) and settled(mimi), "debug send home", 8.0):
		return fail_out()
	check(guild.zone_of(arthur) == "training" and guild.zone_of(mimi) == "social", "Debug C returns heroes to home zones")

	# J/K/V/N/O: Arthur alone.
	await select_party(["arthur"])
	ui.select_mission(FOREST)
	await press(ui.send_button)
	check(in_progress() and main.view_state.current == VIEW.GUILD_VIEW and arthur_body.moving and guild.zone_of(arthur) == "",
		"J/V: SEND leaves the zone and walks to the door while still in GUILD_VIEW")
	check(is_instance_valid(main.slime) and arthur.target == null, "Encounter exists but the party engages only after departure")
	if not await wait_for(func(): return arthur_body.away, "Arthur departs", 3.0):
		return fail_out()
	check(is_equal_approx(arthur_body.position.x, LAYOUT.departure_anchor.x) and not arthur_body.visible
		and main.view_state.current == VIEW.EXPEDITION_VIEW and arthur.visible and not mimi.visible, "J/V: Arthur leaves via the door; EXPEDITION_VIEW")
	check(guild.is_in_guild(mimi) and mimi_body.visible and mimi_body.state_name() != "AWAY" and mimi.guild_status == "READY",
		"K: Mimi stays in the Guild")
	check(arthur.target == main.active_target, "Party engages once departed")
	if not await play_run():
		return fail_out()
	check(main.view_state.current == VIEW.GUILD_VIEW and guild.is_in_guild(arthur) and guild.visible, "N: Mission end switches to GUILD_VIEW")
	check(is_equal_approx(return_entry_x.get("arthur", -1.0), LAYOUT.return_anchor.x), "O: Arthur re-enters at the return anchor")
	if not await wait_for(func(): return settled(arthur), "walk home", 6.0):
		return fail_out()
	check(guild.zone_of(arthur) == "training" and zone_bounds_ok(arthur), "Returned hero walks back to Training")
	await press(ui.continue_button)

	# P/Q: manual rest uses the Rest Area and EnergyRecovery.
	await press(ui.rest_button)
	check(guild.zone_of(arthur) == "rest" and arthur.guild_status == "RESTING" and guild.zone_of(mimi) == "social",
		"P: REST sends Arthur (not the full-Energy Mimi) to the Rest Area")
	if not await wait_for(func(): return settled(arthur), "walk to rest", 6.0):
		return fail_out()
	check(zone_bounds_ok(arthur) and arthur_body.state_name() == "GUILD_RESTING", "P: Arthur rests inside the Rest Area")
	var before: int = arthur.current_energy
	main.energy_recovery.recover(2.0)
	check(arthur.current_energy == before + 10, "Q: EnergyRecovery still recovers there (+5/sec)")
	await press(ui.stop_rest_button)
	check(guild.zone_of(arthur) == "training", "STOP REST: hero walks back to his home zone")
	debug_key(KEY_8)

	# L/M: Mimi alone, then both.
	await select_party(["mimi"])
	await press(ui.send_button)
	if not await wait_for(func(): return mimi_body.away, "Mimi departs", 3.0):
		return fail_out()
	check(guild.is_in_guild(arthur) and arthur_body.visible and not guild.is_in_guild(mimi), "L: Sending Mimi alone leaves Arthur in the Guild")
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)
	debug_key(KEY_8)
	await select_party(["arthur", "mimi"])
	await press(ui.send_button)
	if not await wait_for(func(): return arthur_body.away and mimi_body.away, "both depart", 3.0):
		return fail_out()
	check(not guild.is_in_guild(arthur) and not guild.is_in_guild(mimi) and guild.assigned_heroes("training").is_empty()
		and guild.assigned_heroes("social").is_empty(), "M: Both leave the Guild's active state")
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)

	# R/S/T: Repeat Orders + Scheduled Rest through the Guild.
	main.wallet.add_gold(1450)
	main.guild_mastery.purchase("repeat_orders", main.wallet)
	main.guild_mastery.purchase("scheduled_rest", main.wallet)
	debug_key(KEY_8)
	await select_party(["arthur"])
	ui.select_mission(FOREST)
	ui.repeat_toggle.button_pressed = true
	await press(ui.send_button)
	if not await play_run():
		return fail_out()
	zone_history.arthur.clear()
	if not await wait_for(func(): return main.repeat_orders.paused_for_recovery and main.energy_recovery.recovery_enabled, "scheduled rest", 6.0):
		return fail_out()
	check(guild.zone_of(arthur) == "rest" and not ui.visible, "R: Scheduled Rest walks Arthur to the Rest Area (Guild visible)")
	debug_key(KEY_7)
	if not await wait_for(func(): return in_progress() and main.repeat_orders.repeat_run_count == 2 and arthur_body.away, "repeat redispatch", 20.0):
		return fail_out()
	var history: Array = zone_history.arthur
	var rest_at: int = history.find("rest")
	var board_at: int = history.find("expedition_board")
	var left_board: bool = history.find("AWAY", board_at) > board_at or history.find("", board_at) > board_at
	check(rest_at >= 0 and board_at > rest_at and left_board,
		"S: READY automation leaves the Rest Area for the Board, then the door (%s)" % str(history))
	check(main.repeat_orders.repeat_run_count == 2 and main.mission_run.mission_id == FOREST.id, "T: Repeat Orders still redispatches")
	main._stop_repeat_after_current()
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)

	# U: Mission Queue through the Guild.
	main.wallet.add_gold(10000)
	main.wallet.add_guild_tokens(1)
	main.guild_mastery.purchase("mission_queue", main.wallet)
	debug_key(KEY_8)
	await select_party(["arthur", "mimi"])
	main.mission_queue.clear()
	main.mission_queue.add(FOREST)
	main.mission_queue.add(FOREST)
	await press(ui.queue_buttons.start)
	if not await play_run():
		return fail_out()
	zone_history.arthur.clear()
	zone_history.mimi.clear()
	if not await wait_for(func(): return in_progress() and main.mission_queue.session_run_count == 2, "second queue entry", 20.0):
		return fail_out()
	check(zone_history.arthur.has("rest") and zone_history.arthur.has("expedition_board")
		and zone_history.mimi.has("rest") and zone_history.mimi.has("expedition_board"), "U: Queue entries pass through Rest Area and Board")
	if not await play_run():
		return fail_out()
	check(main.mission_queue.finished, "U: Mission Queue still completes")

	# V: view state sequence stayed explicit.
	check(view_history.count(VIEW.EXPEDITION_VIEW) >= 6 and view_history.count(VIEW.GUILD_VIEW) >= 6
		and main.view_state.current == VIEW.GUILD_VIEW, "V: GUILD_VIEW <-> EXPEDITION_VIEW for every mission")

	print("Milestone 16 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
