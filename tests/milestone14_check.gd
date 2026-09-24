extends SceneTree

const MAIN = preload("res://scenes/main.tscn")
const FOREST = preload("res://data/missions/forest_patrol.tres")
const GEL = preload("res://data/items/slime_gel.tres")
const RING = preload("res://data/items/slime_ring.tres")

var main: Node2D
var ui
var arthur: HeroController
var mimi: HeroController
var failures: int = 0
# hero_id -> distances to the target at each attack
var attack_distances: Dictionary = {"arthur": [], "mimi": []}
var loot_spawns: int = 0

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
		var check_box: CheckBox = ui.party_checks[member.hero_id]
		if check_box.button_pressed != (member.hero_id in ids):
			check_box.toggled.emit(member.hero_id in ids)
	await process_frame

# Optionally lets the first encounter play out naturally, then F8s the rest.
func play_run(natural_first: bool = false) -> bool:
	var first: bool = natural_first
	while in_progress():
		if not await wait_for(func(): return is_instance_valid(main.slime) or not in_progress(), "next encounter", 8.0):
			return false
		if not in_progress():
			break
		main.debug_next_drop = GEL
		if first:
			var kills: int = main.mission_run.defeated_encounters
			if not await wait_for(func(): return main.mission_run.defeated_encounters > kills or not in_progress(), "natural kill", 20.0):
				return false
			first = false
			continue
		debug_key(KEY_F8)
		await process_frame
	return await wait_for(returned, "return to Guild", 10.0)

func on_attack(target: Node2D, _damage: int, member: HeroController) -> void:
	if is_instance_valid(target):
		attack_distances[member.hero_id].append(member.global_position.distance_to(target.global_position))

func fail_out() -> void:
	print("Milestone 14 check aborted: %d failures" % failures)
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
	main.ground_loot.child_entered_tree.connect(func(_node): loot_spawns += 1)

	# A/B/C: reusable hero model.
	check(arthur is HeroController and arthur.hero_id == "arthur" and arthur.class_id == "knight"
		and arthur.hero_data.combat_style == HeroData.MELEE and arthur.progression.damage == 10
		and arthur.total_max_hp() == 100 and arthur.max_energy == 100 and arthur.skills.tree.tree_id == "knight",
		"A: Arthur loads through HeroData/HeroController with unchanged stats")
	check(mimi is HeroController and mimi.hero_id == "mimi" and mimi.display_name == "Mimi" and mimi.class_id == "mage"
		and mimi.hero_data.combat_style == HeroData.RANGED_MAGIC and mimi.skills.class_data.class_id == "mage"
		and mimi.skills.tree.tree_id == "mage", "B: Mimi exists with class_id mage and the Mage tree")
	check(mimi.progression.level == 1 and mimi.total_max_hp() == 70 and mimi.progression.current_hp == 70
		and mimi.total_attack() == 8 and is_equal_approx(mimi.attack_interval(), 1.2) and is_equal_approx(mimi.attack_range, 220.0)
		and mimi.max_energy == 100 and mimi.move_speed < arthur.move_speed, "B: Mimi starting stats match the spec")
	mimi.current_energy = 60
	check(arthur.current_energy == 100 and mimi.progression != arthur.progression and mimi.equipment != arthur.equipment,
		"C: Mimi has independent Energy, progression and equipment")
	mimi.restore_energy()
	check(main.roster_buttons["arthur"].text.contains("Arthur - Knight Lv 1") and main.roster_buttons["mimi"].text.contains("Mimi - Mage Lv 1")
		and main.roster_buttons["mimi"].text.contains("READY"), "Guild status shows both heroes")

	# D/E: party selection.
	check(main.party.max_party_size() == 2 and main.party.hero_ids == ["arthur"], "D: Party size 2, default party Arthur")
	await select_party(["arthur", "mimi"])
	check(main.party.hero_ids == ["arthur", "mimi"] and ui.party_label.text == "Party: Arthur + Mimi", "D: Party supports two heroes")
	await select_party([])
	check(main.party.hero_ids.is_empty() and ui.send_button.disabled and not main.start_mission(FOREST)
		and main.party.dispatch_reason(main.party.hero_ids) == "Select at least one hero.", "E: Empty party cannot dispatch")
	check(ui.send_button.text == "SEND PARTY", "SEND PARTY replaces SEND ARTHUR")

	# F/I: Arthur only.
	await select_party(["arthur"])
	ui.select_mission(FOREST)
	await press(ui.send_button)
	check(in_progress() and main.mission_run.party_hero_ids == ["arthur"] and mimi.guild_status == "READY",
		"F: Arthur-only mission dispatches; Mimi stays at the Guild")
	if not await play_run(true):
		return fail_out()
	check(not attack_distances.arthur.is_empty() and attack_distances.arthur.max() <= HeroController.MELEE_RANGE + 0.5,
		"I: Arthur attacks from melee range")
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and arthur.progression.level == 3
		and mimi.progression.level == 1 and mimi.progression.xp == 0 and mimi.current_energy == 100, "F: Arthur-only run leaves Mimi untouched")
	check(arthur.progression.damage == 14 and arthur.progression.max_hp == 120, "Q: Arthur level growth unchanged (+2 dmg / +10 HP)")
	await press(ui.continue_button)

	# G/J/O: Mimi only.
	await select_party(["mimi"])
	var arthur_xp_before: int = arthur.progression.xp
	await press(ui.send_button)
	check(in_progress() and main.mission_run.party_hero_ids == ["mimi"] and arthur.guild_status != "ON_EXPEDITION",
		"G: Mimi-only mission dispatches")
	if not await play_run(true):
		return fail_out()
	check(not attack_distances.mimi.is_empty() and attack_distances.mimi.min() > HeroController.MELEE_RANGE + 20
		and attack_distances.mimi.max() <= 220.5, "J: Mimi casts from ranged distance, never melee")
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and main.mission_run.hero_xp == {"mimi": 75}
		and mimi.progression.level == 3 and arthur.progression.xp == arthur_xp_before and arthur.progression.level == 3,
		"O/P: Mimi receives full XP and levels independently")
	check(mimi.progression.damage == 12 and mimi.progression.max_hp == 84, "P: Mimi uses her own level growth")
	debug_key(KEY_F3)
	check(mimi.progression.xp == 30 and arthur.progression.xp == arthur_xp_before, "P: Debug Mimi XP does not touch Arthur")
	await press(ui.continue_button)
	await press(ui.rest_button)
	main.energy_recovery.recover(20.0)
	main.party.recoveries["mimi"].recover(20.0)

	# H/I/J/K/L/M/N/O/R/T: Arthur + Mimi together.
	await select_party(["arthur", "mimi"])
	attack_distances = {"arthur": [], "mimi": []}
	loot_spawns = 0
	var gold_before: int = main.gold
	var gel_before: int = main.inventory.quantity(GEL.id)
	var levels: Dictionary = {"arthur": arthur.progression.level, "mimi": mimi.progression.level}
	await press(ui.send_button)
	check(in_progress() and main.mission_run.party_hero_ids == ["arthur", "mimi"]
		and arthur.guild_status == "ON_EXPEDITION" and mimi.guild_status == "ON_EXPEDITION", "H: Arthur + Mimi mission dispatches")
	if not await wait_for(func(): return main.mission_run.defeated_encounters == 1, "first shared kill", 20.0):
		return fail_out()
	check(main.gold - gold_before == 10 and main.mission_run.defeated_encounters == 1, "K/L: One enemy death = one encounter, 10 Gold once")
	check(not attack_distances.arthur.is_empty() and not attack_distances.mimi.is_empty()
		and attack_distances.arthur.max() <= HeroController.MELEE_RANGE + 0.5 and attack_distances.mimi.min() > HeroController.MELEE_RANGE + 20,
		"I/J: Together, Arthur fights in melee while Mimi stays ranged")
	if not await play_run():
		return fail_out()
	check(main.gold - gold_before == 60, "L: Party earns 60 Gold total, not doubled")
	check(loot_spawns == 3 and main.inventory.quantity(GEL.id) - gel_before == 3 and main.mission_run.collected_loot[GEL.id] == 3,
		"M: Loot rolls once per enemy")
	check(main.mission_run.hero_xp == {"arthur": 75, "mimi": 75} and main.mission_run.total_xp() == 75,
		"N/O: Arthur and Mimi each receive full XP (75)")
	check(arthur.current_energy == 55 and mimi.current_energy == 55 and main.mission_run.party_ending_energy == {"arthur": 55, "mimi": 55},
		"R: Energy cost applies to both party members")
	check(arthur.guild_status == "IDLE_AT_GUILD" and mimi.guild_status == "IDLE_AT_GUILD"
		and arthur.position == arthur.home_position and mimi.position == mimi.home_position, "T: Both heroes return to the Guild")
	check(ui.summary.text.contains("Arthur Lv %d | XP +75" % arthur.progression.level) and ui.summary.text.contains("Mimi Lv %d | XP +75" % mimi.progression.level)
		and ui.summary.text.contains("Total: Gold +60"), "Summary lists participants with XP and single Gold")
	check(arthur.progression.level >= levels.arthur and mimi.progression.level >= levels.mimi, "Both progressions advanced")
	await press(ui.continue_button)

	# U: independent recovery.
	arthur.current_energy = 85
	mimi.current_energy = 25
	await press(ui.rest_button)
	check(arthur.guild_status == "RESTING" and mimi.guild_status == "RESTING", "U: REST starts both heroes resting")
	main.energy_recovery.recover(3.0)
	main.party.recoveries["mimi"].recover(3.0)
	check(arthur.current_energy == 100 and arthur.guild_status == "READY" and mimi.current_energy == 40 and mimi.guild_status == "RESTING",
		"U: Each hero recovers independently (Arthur READY, Mimi still resting)")
	await select_party(["arthur", "mimi"])
	check(ui.send_button.disabled and ui.warning.text.contains("Mimi is resting."), "Resting member blocks party dispatch")
	await press(ui.stop_rest_button)

	# S: either hero crossing the threshold retreats the party.
	arthur.restore_energy()
	debug_key(KEY_F2)
	await press(ui.send_button)
	if not await play_run():
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.RETREATED and main.mission_run.stop_reason == StopConditionEvaluator.Reason.ENERGY_LOW
		and main.mission_run.defeated_encounters == 1 and arthur.current_energy == 85 and mimi.current_energy == 25,
		"S: Mimi below threshold retreats the whole party while Arthur is fine")
	await press(ui.continue_button)

	# V/W: Repeat Orders + Scheduled Rest with the party.
	main.wallet.add_gold(1450)
	main.guild_mastery.purchase("repeat_orders", main.wallet)
	main.guild_mastery.purchase("scheduled_rest", main.wallet)
	debug_key(KEY_8)
	debug_key(KEY_7)
	ui.select_mission(FOREST)
	ui.repeat_toggle.button_pressed = true
	await press(ui.send_button)
	check(main.repeat_orders.party_hero_ids == ["arthur", "mimi"], "W: Repeat Orders remembers Arthur + Mimi")
	if not await play_run():
		return fail_out()
	if not await wait_for(func(): return main.repeat_orders.paused_for_recovery and main.party.any_resting(main.repeat_orders.party_hero_ids),
			"scheduled party rest", 8.0):
		return fail_out()
	mimi.current_energy = 5 # Mimi now needs longer than Arthur.
	await select_party(["arthur"]) # Automation must ignore the current selection.
	if not await wait_for(func(): return arthur.guild_status == "READY", "Arthur READY", 6.0):
		return fail_out()
	check(mimi.guild_status == "RESTING" and not in_progress(), "V: Arthur READY alone does not redispatch")
	if not await wait_for(func(): return mimi.guild_status == "READY", "Mimi READY", 6.0):
		return fail_out()
	check(not in_progress(), "V: Preparation delay follows the last hero reaching READY")
	if not await wait_for(in_progress, "repeat redispatch", 6.0):
		return fail_out()
	check(main.mission_run.party_hero_ids == ["arthur", "mimi"] and mimi.guild_status == "ON_EXPEDITION"
		and main.repeat_orders.repeat_run_count == 2, "V/W: Both READY -> same two-hero party repeats")
	main._stop_repeat_after_current()
	if not await play_run():
		return fail_out()
	await press(ui.continue_button)

	# X: Mission Queue keeps the party chosen at START.
	main.wallet.add_gold(10000)
	main.wallet.add_guild_tokens(1)
	main.guild_mastery.purchase("mission_queue", main.wallet)
	debug_key(KEY_8)
	await select_party(["arthur", "mimi"])
	main.mission_queue.clear()
	main.mission_queue.add(FOREST)
	main.mission_queue.add(FOREST)
	await press(ui.queue_buttons.start)
	check(in_progress() and main.mission_queue.party_hero_ids == ["arthur", "mimi"] and main.mission_run.party_hero_ids == ["arthur", "mimi"],
		"X: Queue starts with the selected party")
	await select_party(["mimi"])
	if not await play_run():
		return fail_out()
	if not await wait_for(in_progress, "second queued entry", 12.0):
		return fail_out()
	check(main.mission_run.party_hero_ids == ["arthur", "mimi"], "X: Second entry uses the queue's party, not the new selection")
	if not await play_run():
		return fail_out()
	check(main.mission_queue.finished and ui.title.text == "EXPEDITION ORDERS COMPLETE", "Queue with a party completes")
	await press(ui.continue_button)
	debug_key(KEY_7)

	# Y/Z: per-hero equipment and skill tree context.
	main.inventory.add_item(RING)
	main.set_hero_context(mimi)
	check(main.inventory_ui.equipment == mimi.equipment and main.inventory_ui.get_node("Margin/Column/EquipmentTitle").text == "MIMI EQUIPMENT",
		"Y: Equipment panel follows the selected hero")
	check(mimi.equipment.equip(main.inventory, RING.id) and mimi.equipment.get_item(Equipment.Slot.ACCESSORY) == RING
		and arthur.equipment.get_item(Equipment.Slot.ACCESSORY) == null, "Y: Equipping on Mimi leaves Arthur's slots untouched")
	check(main.skill_ui.skills == mimi.skills and main.skill_ui.title.text.contains("Mimi") and main.skill_ui.title.text.contains("Mage")
		and main.skill_ui.details.text.contains("No skills available"), "Z: Skill panel shows Mimi's Mage tree safely")
	check(main.arthur_label.text.begins_with("Mimi - Mage"), "Stats panel follows the selected hero")
	main.set_hero_context(arthur)
	check(main.skill_ui.skills == arthur.skills and main.skill_ui.skills.tree.tree_id == "knight"
		and main.inventory_ui.equipment == arthur.equipment, "Z: Switching back shows Arthur's Knight tree and equipment")

	# AA: Boss with both heroes.
	debug_key(KEY_8)
	debug_key(KEY_4)
	ui.select_opportunity()
	await select_party(["arthur", "mimi"])
	await press(ui.send_button)
	check(in_progress() and main.mission_run.mission.special_type == "BOSS" and main.mission_run.party_hero_ids == ["arthur", "mimi"],
		"AA: Boss portal dispatches Arthur + Mimi")
	if not await play_run():
		return fail_out()
	check(main.mission_run.result_status == MissionRun.Result.COMPLETED and main.mission_run.hero_xp.has("arthur")
		and main.mission_run.hero_xp.has("mimi") and main.mission_run.hero_xp.arthur == main.mission_run.hero_xp.mimi,
		"AA: Ancient Treant completes with full XP to both heroes")

	print("Milestone 14 check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)
