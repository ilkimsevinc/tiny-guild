extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const GEL = preload("res://data/items/slime_gel.tres")

var main: Node2D
var ui
var arthur: HeroController
var mimi: HeroController
var failures: int = 0
# Per-frame formation sampling while both heroes fight.
var sampling: bool = false
var samples: int = 0
var min_spacing: float = INF
var overtakes: int = 0
var behind_violations: int = 0
var split_targets: int = 0
var attack_distances: Dictionary = {"arthur": [], "mimi": []}
var orb_offsets: Array[float] = []
var orb_behind: Array[bool] = []

func _initialize() -> void:
	run_check.call_deferred()

func _physics_process(_delta: float) -> bool:
	if sampling and main != null and main.mission_run.mission_state == MissionRun.State.IN_PROGRESS:
		samples += 1
		min_spacing = minf(min_spacing, absf(arthur.global_position.x - mimi.global_position.x))
		var target: Node2D = main.active_target
		if is_instance_valid(target) and arthur.target == target:
			if mimi.target != target:
				split_targets += 1
			var arthur_gap: float = absf(target.global_position.x - arthur.global_position.x)
			var mimi_gap: float = absf(target.global_position.x - mimi.global_position.x)
			if mimi_gap < arthur_gap:
				behind_violations += 1
			if mimi_gap < arthur_gap + PartyFormation.MIN_HERO_SPACING - 0.5:
				overtakes += 1
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

func select_party(ids: Array[String]) -> void:
	for member in [arthur, mimi]:
		var box: CheckBox = ui.party_checks[member.hero_id]
		if box.button_pressed != (member.hero_id in ids):
			box.toggled.emit(member.hero_id in ids)
	await process_frame

# natural_kills encounters play out for real, the rest are finished with F8.
func play_run(natural_kills: int = 0) -> bool:
	while in_progress():
		if not await wait_for(func(): return is_instance_valid(main.slime) or not in_progress(), "next encounter", 8.0):
			return false
		if not in_progress():
			break
		main.debug_next_drop = GEL
		if main.mission_run.defeated_encounters < natural_kills:
			var kills: int = main.mission_run.defeated_encounters
			if not await wait_for(func(): return main.mission_run.defeated_encounters > kills or not in_progress(), "natural kill", 25.0):
				return false
			continue
		debug_key(KEY_F8)
		await process_frame
	return await wait_for(returned, "return to Guild", 10.0)

func on_attack(target: Node2D, _damage: int, member: HeroController) -> void:
	if is_instance_valid(target):
		attack_distances[member.hero_id].append(member.global_position.distance_to(target.global_position))

func on_orb(origin: Vector2, _target: Node2D) -> void:
	orb_offsets.append(origin.distance_to(mimi.global_position + Vector2(0, -60)))
	orb_behind.append(origin.x < arthur.global_position.x or main.mission_run.party_hero_ids == ["mimi"])

func reset_samples() -> void:
	samples = 0
	min_spacing = INF
	overtakes = 0
	behind_violations = 0
	split_targets = 0
	attack_distances = {"arthur": [], "mimi": []}
	orb_offsets.clear()
	orb_behind.clear()

func fail_out() -> void:
	print("Milestone 15 check aborted: %d failures" % failures)
	quit(1)

func run_check() -> void:
	main = MAIN.instantiate()
	root.add_child(main)
	await process_frame
	ui = main.expedition_ui
	arthur = main.arthur
	mimi = main.mimi
	arthur.attacked.connect(on_attack.bind(arthur))
	mimi.attacked.connect(on_attack.bind(mimi))
	mimi.orb_launched.connect(on_orb)

	# A-D: roles and role-based formation.
	check(arthur.hero_data.combat_role == HeroData.FRONTLINE and arthur.hero_data.prefers_front(), "A: Arthur role is FRONTLINE")
	check(mimi.hero_data.combat_role == HeroData.MAGE and not mimi.hero_data.prefers_front(), "B: Mimi role is MAGE")
	var both: PartyFormation = PartyFormation.auto([mimi, arthur])
	check(both.slots == ["arthur", "mimi"] and both.row_of("arthur") == "FRONT", "C: Auto formation puts Arthur FRONT (any input order)")
	check(both.row_of("mimi") == "BACK" and both.leader_of("mimi") == "arthur"
		and is_equal_approx(both.spacing_of("mimi"), PartyFormation.BACKLINE_SPACING), "D: Mimi is BACK, following Arthur")
	check(PartyFormation.auto([mimi]).slots == ["mimi"] and PartyFormation.auto([mimi]).leader_of("mimi") == ""
		and PartyFormation.auto([arthur]).slots == ["arthur"], "Formation handles a party of one")
	await select_party(["arthur", "mimi"])
	check(ui.party_label.text == "FRONT Arthur | BACK Mimi", "Formation UI shows FRONT Arthur | BACK Mimi")
	main.set_hero_context(mimi)
	check(main.party.formation_for(main.party.hero_ids).slots == ["arthur", "mimi"], "Hero context switch does not alter formation")
	main.set_hero_context(arthur)

	# G-L, Q: Arthur + Mimi, natural combat for two encounters.
	reset_samples()
	sampling = true
	ui.select_mission(FOREST)
	await press(ui.send_button)
	check(main.party.formation.slots == ["arthur", "mimi"] and main.party.active_hero_ids == ["arthur", "mimi"]
		and mimi.formation_leader == arthur and arthur.formation_leader == null, "Dispatch applies FRONT Arthur / BACK Mimi")
	check(main.mission_label.text.contains("Arthur - FRONTLINE [FRONT] | Mimi - MAGE [BACK]"), "Mission status shows roles and rows")
	if not await play_run(2):
		return fail_out()
	sampling = false
	check(samples > 60, "Formation sampled across the approach and fights (%d frames)" % samples)
	check(not attack_distances.arthur.is_empty() and attack_distances.arthur.max() <= HeroController.MELEE_RANGE + 0.5, "G: Arthur attacks from melee range")
	check(behind_violations == 0, "H: Mimi stays behind Arthur relative to the enemy")
	check(not attack_distances.mimi.is_empty() and attack_distances.mimi.max() <= mimi.attack_range + 0.5
		and attack_distances.mimi.min() > HeroController.MELEE_RANGE + PartyFormation.MIN_HERO_SPACING, "I: Mimi casts from the backline within spell range")
	check(overtakes == 0, "J: Mimi never closes within minimum spacing of Arthur's front position")
	check(min_spacing >= PartyFormation.MIN_HERO_SPACING - 0.5, "K: Minimum hero spacing kept (%.1f px)" % min_spacing)
	check(split_targets == 0, "L: Both heroes always share the active target")
	check(not orb_offsets.is_empty() and orb_offsets.max() < 0.5 and not false in orb_behind, "Q: Orbs spawn at Mimi's backline position")
	check(arthur.current_energy == 55 and mimi.current_energy == 55 and main.mission_run.result_status == MissionRun.Result.COMPLETED,
		"U: Energy costs unchanged by formation")
	await press(ui.continue_button)
	debug_key(KEY_8)

	# M-P: near-simultaneous hits resolve the death once.
	await select_party(["arthur", "mimi"])
	await press(ui.send_button)
	if not await wait_for(func(): return is_instance_valid(main.slime), "first enemy", 5.0):
		return fail_out()
	var enemy: Node2D = main.slime
	var gold_before: int = main.gold
	var loot_before: int = main.ground_loot.get_child_count()
	enemy.hp = 1
	main.debug_next_drop = GEL
	arthur.attacked.emit(enemy, arthur.total_attack())
	mimi.attacked.emit(enemy, mimi.total_attack())
	main._on_slime_died()
	check(main.mission_run.defeated_encounters == 1, "M/P: Simultaneous hits advance the encounter once")
	check(main.gold - gold_before == 10, "N: Gold awarded once")
	check(main.ground_loot.get_child_count() - loot_before == 1, "O: Loot rolled once")
	check(not main.targeting.release_enemy(enemy) and main.active_target == null, "Targeting rejects a second release")
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)
	debug_key(KEY_8)

	# E/F: single heroes.
	await select_party(["arthur"])
	reset_samples()
	await press(ui.send_button)
	check(main.party.formation.slots == ["arthur"] and arthur.formation_leader == null, "E: Arthur alone anchors the front")
	if not await play_run(1):
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and attack_distances.arthur.max() <= HeroController.MELEE_RANGE + 0.5,
		"E: Arthur alone completes with melee attacks")
	await press(ui.continue_button)
	debug_key(KEY_8)
	await select_party(["mimi"])
	reset_samples()
	await press(ui.send_button)
	check(main.party.formation.slots == ["mimi"] and mimi.formation_leader == null, "F: Mimi alone uses her own range")
	if not await play_run(1):
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and attack_distances.mimi.min() > mimi.attack_range - 5.0
		and attack_distances.mimi.max() <= mimi.attack_range + 0.5, "F: Mimi alone casts from the edge of her spell range")
	check(not orb_offsets.is_empty() and orb_offsets.max() < 0.5, "Q: Solo orbs also start at Mimi")
	await press(ui.continue_button)
	debug_key(KEY_8)

	# R: Boss formation.
	debug_key(KEY_4)
	ui.select_opportunity()
	await select_party(["arthur", "mimi"])
	reset_samples()
	sampling = true
	await press(ui.send_button)
	check(main.mission_run.mission.special_type == "BOSS" and main.party.formation.slots == ["arthur", "mimi"], "R: Boss dispatch uses the formation")
	if not await wait_for(func(): return not attack_distances.arthur.is_empty() and not attack_distances.mimi.is_empty(), "boss attacks", 15.0):
		return fail_out()
	sampling = false
	check(behind_violations == 0 and split_targets == 0 and attack_distances.arthur.max() <= HeroController.MELEE_RANGE + 0.5
		and attack_distances.mimi.min() > HeroController.MELEE_RANGE, "R: Arthur front, Mimi back, same target vs Ancient Treant")
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)

	# S: Repeat Orders keeps party and formation.
	main.wallet.add_gold(1450)
	main.guild_mastery.purchase("repeat_orders", main.wallet)
	main.guild_mastery.purchase("scheduled_rest", main.wallet)
	debug_key(KEY_8)
	debug_key(KEY_7)
	await select_party(["arthur", "mimi"])
	ui.select_mission(FOREST)
	ui.repeat_toggle.button_pressed = true
	await press(ui.send_button)
	check(main.repeat_orders.formation_slots == ["arthur", "mimi"], "S: Repeat Orders records the formation")
	if not await play_run():
		return fail_out()
	await select_party(["mimi"]) # Must not affect the remembered formation.
	if not await wait_for(func(): return in_progress() and main.repeat_orders.repeat_run_count == 2, "repeat redispatch", 15.0):
		return fail_out()
	check(main.party.formation.slots == ["arthur", "mimi"] and mimi.formation_leader == arthur, "S: Repeat run 2 keeps FRONT Arthur / BACK Mimi")
	main._stop_repeat_after_current()
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)

	# T: Mission Queue keeps party and formation.
	main.wallet.add_gold(10000)
	main.wallet.add_guild_tokens(1)
	main.guild_mastery.purchase("mission_queue", main.wallet)
	debug_key(KEY_8)
	await select_party(["arthur", "mimi"])
	main.mission_queue.clear()
	main.mission_queue.add(FOREST)
	main.mission_queue.add(FOREST)
	await press(ui.queue_buttons.start)
	check(main.mission_queue.formation_slots == ["arthur", "mimi"] and main.party.formation.slots == ["arthur", "mimi"], "T: Queue records the formation")
	await select_party(["mimi"])
	if not await play_run():
		return fail_out()
	if not await wait_for(in_progress, "second queue entry", 12.0):
		return fail_out()
	check(main.party.formation.slots == ["arthur", "mimi"] and mimi.formation_leader == arthur, "T: Second entry keeps the queue formation")
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)
	debug_key(KEY_7)

	# U: retreat rules unchanged.
	debug_key(KEY_8)
	debug_key(KEY_F2)
	await select_party(["arthur", "mimi"])
	ui.select_mission(FOREST)
	await press(ui.send_button)
	if not await play_run():
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.RETREATED and main.mission_run.defeated_encounters == 1
		and mimi.current_energy == 25 and arthur.current_energy == 85, "U: Party retreat threshold unchanged")

	print("Milestone 15 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
