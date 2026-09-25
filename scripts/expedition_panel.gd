extends PanelContainer

signal dispatch_requested(mission: MissionData)
signal continue_requested
signal opportunity_requested(instance: MissionInstance)
signal queue_start_requested
signal queue_resume_requested
signal queue_stop_requested

const MISSIONS: Array[MissionData] = [
	preload("res://data/missions/forest_patrol.tres"),
	preload("res://data/missions/slime_nest.tres"),
	preload("res://data/missions/treasure_trail.tres")]
var selected: MissionData = MISSIONS[0]
var run: MissionRun
var party: PartyState
var party_checks: Dictionary[String, CheckBox] = {}
var party_label: Label
var close_button: Button
var mission_buttons: Dictionary[String, Button] = {}
var prediction: String = ""
var board_rotation: MissionBoardRotation
var mastery: GuildMasteryState
var repeat_orders: RepeatOrderState
var queue: MissionQueueState
var queue_box: VBoxContainer
var queue_title: Label
var queue_list: ItemList
var queue_status: Label
var queue_buttons: Dictionary[String, Button] = {}
var add_queue_buttons: Dictionary[String, Button] = {}
var selected_instance: MissionInstance
var opportunity_button: Button
var rotation_status: Label
@onready var title: Label = $Scroll/Margin/Column/Title
@onready var board: HBoxContainer = $Scroll/Margin/Column/Board
@onready var entries: VBoxContainer = $Scroll/Margin/Column/Board/Scroll/Entries
@onready var details: RichTextLabel = $Scroll/Margin/Column/Board/Selection/Details
@onready var warning: Label = $Scroll/Margin/Column/Board/Selection/Warning
@onready var repeat_toggle: CheckButton = $Scroll/Margin/Column/Board/Selection/RepeatMission
@onready var repeat_reason: Label = $Scroll/Margin/Column/Board/Selection/RepeatReason
@onready var send_button: Button = $Scroll/Margin/Column/Board/Selection/Send
@onready var summary: RichTextLabel = $Scroll/Margin/Column/Summary
@onready var continue_button: Button = $Scroll/Margin/Column/Continue
@onready var rest_status: Label = $Scroll/Margin/Column/RestControls/RestStatus
@onready var rest_button: Button = $Scroll/Margin/Column/RestControls/Rest
@onready var stop_rest_button: Button = $Scroll/Margin/Column/RestControls/StopRest

func setup(mission_run: MissionRun, party_state: PartyState, opportunity_board: MissionBoardRotation = null,
		mastery_state: GuildMasteryState = null, automation_state: RepeatOrderState = null,
		queue_state: MissionQueueState = null) -> void:
	$Scroll/Margin/Column/DebugControls.visible = OS.is_debug_build()
	run = mission_run
	party = party_state
	board_rotation = opportunity_board
	mastery = mastery_state
	repeat_orders = automation_state
	queue = queue_state
	send_button.text = "SEND PARTY"
	_build_close_button()
	_build_party_selection()
	party.changed.connect(refresh)
	for member in party.roster:
		member.stats_changed.connect(refresh)
		party.recoveries[member.hero_id].changed.connect(refresh)
	# REST / STOP REST act on every hero at the Guild; each recovers independently.
	rest_button.pressed.connect(func():
		for recovery in party.recoveries.values():
			recovery.start())
	stop_rest_button.pressed.connect(func():
		for recovery in party.recoveries.values():
			recovery.stop())
	if queue != null:
		_build_queue_section()
		queue.changed.connect(refresh)
	if repeat_orders != null:
		repeat_orders.changed.connect(refresh)
	repeat_toggle.toggled.connect(_on_repeat_toggled)
	if board_rotation != null:
		opportunity_button = Button.new()
		opportunity_button.custom_minimum_size = Vector2(350, 94)
		opportunity_button.add_theme_font_size_override("font_size", 15)
		opportunity_button.pressed.connect(select_opportunity)
		entries.add_child(opportunity_button)
		rotation_status = Label.new()
		rotation_status.add_theme_font_size_override("font_size", 14)
		entries.add_child(rotation_status)
		board_rotation.changed.connect(_on_rotation_changed)
		board_rotation.countdown_changed.connect(_update_countdown)
		_on_rotation_changed()
	for data in MISSIONS:
		var button := Button.new()
		button.text = "%s | %s | Lv. %d\n%d encounters | %s\nCompletion: %d Gold / %d XP\n%s" % [
			data.display_name, data.difficulty, data.recommended_level, data.encounter_count,
			data.estimated_duration_text, data.base_gold_reward, data.base_xp_reward, data.loot_identity]
		button.text += "\nEnergy: " + data.energy_description()
		button.custom_minimum_size = Vector2(350, 138)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(select_mission.bind(data))
		entries.add_child(button)
		if queue != null:
			var add_button := Button.new()
			add_button.text = "ADD TO QUEUE"
			add_button.add_theme_font_size_override("font_size", 13)
			add_button.pressed.connect(func(): queue.add(data))
			entries.add_child(add_button)
			add_queue_buttons[data.id] = add_button
		var description := Label.new()
		description.text = data.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 14)
		entries.add_child(description)
		mission_buttons[data.id] = button
	send_button.pressed.connect(_on_send)
	continue_button.pressed.connect(func(): continue_requested.emit())
	run.changed.connect(refresh)
	show_board()

# The board is an overlay on the Guild's physical Expedition Board; closing it
# reveals the Guild interior. Reopen via the EXPEDITION BOARD button.
func _build_close_button() -> void:
	var header := HBoxContainer.new()
	var column: VBoxContainer = title.get_parent()
	column.add_child(header)
	column.move_child(header, title.get_index())
	title.reparent(header)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_button = Button.new()
	close_button.text = "CLOSE BOARD"
	close_button.pressed.connect(hide)
	header.add_child(close_button)

func _build_party_selection() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = "SELECT PARTY:"
	row.add_child(heading)
	for member in party.roster:
		var check := CheckBox.new()
		check.text = member.display_name
		check.toggled.connect(func(on: bool):
			party.set_selected(member.hero_id, on)
			refresh())
		row.add_child(check)
		party_checks[member.hero_id] = check
	party_label = Label.new()
	party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(party_label)
	var selection: VBoxContainer = send_button.get_parent()
	selection.add_child(row)
	selection.move_child(row, send_button.get_index())

func select_mission(data: MissionData) -> void:
	selected_instance = null
	if repeat_orders != null:
		repeat_orders.select_mission(data)
	selected = data
	refresh()

func refresh() -> void:
	if run == null or party == null or selected == null:
		return
	var ids: Array[String] = party.hero_ids
	var members: Array[HeroController] = party.selected_heroes()
	# Every member pays each encounter's cost, so the weakest member decides the risk.
	var max_energy: int = members[0].max_energy if not members.is_empty() else 100
	prediction = StopConditionEvaluator.predict(selected, party.min_energy(ids), max_energy, run.stop_config) \
		if not members.is_empty() else "NO PARTY SELECTED"
	var energy_lines: Array[String] = []
	for member in members:
		energy_lines.append("%s Energy: %d / %d" % [member.display_name, member.current_energy, member.max_energy])
	details.text = "[b]%s[/b]\n%s | Recommended Level %d\nEncounters: %d | Duration: %s\n\nEnergy: %s (each hero)\n%s\nReturn below: %d%%\n\nBase completion reward: %d Gold / %d XP\n(Additional to encounter rewards)\n\nLoot: %s\n\n%s" % [
		selected.display_name, selected.difficulty, selected.recommended_level,
		selected.encounter_count, selected.estimated_duration_text, selected.energy_description(),
		"\n".join(energy_lines) if not energy_lines.is_empty() else "No heroes selected", roundi(run.stop_config.min_energy_percent * 100),
		selected.base_gold_reward, selected.base_xp_reward, selected.loot_description(), selected.description]
	if selected.completion_loot != null:
		var names: Array[String] = []
		for item in selected.completion_loot.items:
			names.append(item.display_name)
		details.text += "\n\nPossible Unique Loot:\n" + "\n".join(names)
	if selected_instance != null:
		details.text = "[b]%s[/b]\n" % ("BOSS PORTAL" if selected.special_type == "BOSS" else selected.special_type) + details.text
	warning.text = prediction
	if selected.special_type == "BOSS":
		warning.text += " | BOSS THREAT"
	for member in members:
		if member.progression.level < selected.recommended_level:
			warning.text += "\n%s is below the recommended level." % member.display_name
	var unavailable: String = "Unlock Repeat Orders in Guild Mastery" if repeat_orders == null else repeat_orders.availability_reason(selected)
	if unavailable.is_empty() and queue != null and queue.enabled:
		unavailable = "Repeat Orders unavailable while Expedition Orders are active."
	repeat_toggle.visible = repeat_orders != null and repeat_orders.repeat_unlocked
	repeat_toggle.disabled = not unavailable.is_empty() or not run.can_start()
	repeat_toggle.set_pressed_no_signal(repeat_orders != null and repeat_orders.repeat_enabled and repeat_orders.mission_id == selected.id)
	repeat_reason.text = unavailable
	repeat_reason.visible = not unavailable.is_empty()
	_refresh_rest()
	for member in members:
		if party.recoveries[member.hero_id].recovery_enabled:
			warning.text += "\n%s is resting." % member.display_name
	var dispatch_reason: String = party.dispatch_reason(ids)
	if members.is_empty():
		warning.text += "\n" + dispatch_reason
	var queue_running: bool = queue != null and queue.running
	if queue_running:
		warning.text += "\nExpedition Orders running."
	send_button.disabled = not run.can_start() or queue_running or not dispatch_reason.is_empty() or (selected_instance != null and not board_rotation.can_claim(selected_instance))
	_refresh_party_selection()
	_refresh_queue()

func _refresh_party_selection() -> void:
	for member in party.roster:
		var check: CheckBox = party_checks[member.hero_id]
		check.set_pressed_no_signal(party.is_selected(member.hero_id))
		var busy: String = party.unavailable_reason(member)
		# Busy heroes cannot be added; an already-selected one can still be removed.
		check.disabled = not run.can_start() or (not busy.is_empty() and not party.is_selected(member.hero_id))
		check.tooltip_text = busy
	# Formation is automatic by role; shown so the player knows who holds the front.
	var names: Dictionary = {}
	for member in party.roster:
		names[member.hero_id] = member.display_name
	var formation: PartyFormation = party.formation_for(party.hero_ids)
	party_label.text = formation.describe(names) if not formation.slots.is_empty() else "Party: None"

func _refresh_rest() -> void:
	var lines: Array[String] = []
	var can_rest: bool = false
	var anyone_resting: bool = false
	var all_full: bool = true
	for member in party.roster:
		var recovery: EnergyRecovery = party.recoveries[member.hero_id]
		var rate: String = str(snappedf(recovery.recovery_rate(), 0.1)).trim_suffix(".0")
		lines.append("%s | Status: %s | Energy: %d / %d | Recovery: +%s / sec" % [member.display_name,
			member.guild_status.replace("_", " ").capitalize(), member.current_energy, member.max_energy, rate])
		can_rest = can_rest or recovery.can_start()
		anyone_resting = anyone_resting or recovery.recovery_enabled
		all_full = all_full and member.current_energy >= member.max_energy
	rest_status.text = "\n".join(lines)
	rest_button.disabled = not can_rest or not run.can_start()
	rest_button.text = "Party is fully rested." if all_full else "REST"
	stop_rest_button.disabled = not anyone_resting

func _build_queue_section() -> void:
	# Orders sit under the mission list so the selection column keeps its space.
	var scroll: ScrollContainer = entries.get_parent()
	var left := VBoxContainer.new()
	left.name = "LeftColumn"
	left.add_theme_constant_override("separation", 6)
	board.add_child(left)
	board.move_child(left, 0)
	scroll.reparent(left)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	queue_box = VBoxContainer.new()
	queue_box.add_theme_constant_override("separation", 4)
	left.add_child(queue_box)
	queue_title = Label.new()
	queue_title.add_theme_font_size_override("font_size", 16)
	queue_box.add_child(queue_title)
	queue_list = ItemList.new()
	queue_list.custom_minimum_size = Vector2(0, 74)
	queue_list.add_theme_font_size_override("font_size", 14)
	queue_list.item_selected.connect(func(_index): _refresh_queue())
	queue_box.add_child(queue_list)
	var edit_row := HBoxContainer.new()
	var control_row := HBoxContainer.new()
	queue_box.add_child(edit_row)
	queue_box.add_child(control_row)
	for spec in [["up", "UP", edit_row], ["down", "DOWN", edit_row], ["remove", "REMOVE", edit_row], ["clear", "CLEAR", edit_row],
			["start", "START QUEUE", control_row], ["resume", "RESUME QUEUE", control_row], ["stop", "STOP QUEUE", control_row]]:
		var button := Button.new()
		button.text = spec[1]
		button.add_theme_font_size_override("font_size", 13)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spec[2].add_child(button)
		queue_buttons[spec[0]] = button
	queue_buttons.up.pressed.connect(_move_selected.bind(-1))
	queue_buttons.down.pressed.connect(_move_selected.bind(1))
	queue_buttons.remove.pressed.connect(func(): queue.remove(_selected_queue_index()))
	queue_buttons.clear.pressed.connect(func(): queue.clear())
	queue_buttons.start.pressed.connect(func(): queue_start_requested.emit())
	queue_buttons.resume.pressed.connect(func(): queue_resume_requested.emit())
	queue_buttons.stop.pressed.connect(func(): queue_stop_requested.emit())
	queue_status = Label.new()
	queue_status.add_theme_font_size_override("font_size", 13)
	queue_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	queue_status.add_theme_color_override("font_color", Color(0.75, 0.9, 0.55))
	queue_box.add_child(queue_status)

func _selected_queue_index() -> int:
	var picked: PackedInt32Array = queue_list.get_selected_items()
	return picked[0] if not picked.is_empty() else -1

func _move_selected(offset: int) -> void:
	var index: int = _selected_queue_index()
	if queue.move(index, offset):
		queue_list.select(index + offset)
		_refresh_queue()

func _refresh_queue() -> void:
	if queue == null or queue_box == null:
		return
	queue_box.visible = queue.unlocked
	for mission_id in add_queue_buttons:
		var reason: String = queue.add_reason(MISSIONS.filter(func(m): return m.id == mission_id)[0])
		add_queue_buttons[mission_id].visible = queue.unlocked
		add_queue_buttons[mission_id].disabled = not reason.is_empty()
		add_queue_buttons[mission_id].tooltip_text = reason
	if not queue.unlocked:
		return
	var picked: int = _selected_queue_index()
	queue_list.clear()
	for index in queue.capacity():
		if index < queue.entries.size():
			var entry: MissionQueueEntry = queue.entries[index]
			queue_list.add_item("%d. %s %s" % [index + 1, entry.marker(), entry.display_name])
		else:
			queue_list.add_item("%d. Empty" % (index + 1))
			queue_list.set_item_selectable(index, false)
	if picked >= 0 and picked < queue.entries.size():
		queue_list.select(picked)
	queue_title.text = "EXPEDITION ORDERS  %s" % (("Queue: " + queue.progress_text()) if queue.enabled else "(%d / %d)" % [queue.entries.size(), queue.capacity()])
	var at_guild: bool = run.can_start()
	# A running session uses its own remembered party; otherwise the current selection.
	var queue_ids: Array[String] = queue.party_hero_ids if queue.enabled else party.hero_ids
	var resting: bool = party.any_resting(queue_ids)
	queue_buttons.up.disabled = not queue.can_edit(picked) or not queue.can_edit(picked - 1)
	queue_buttons.down.disabled = not queue.can_edit(picked) or not queue.can_edit(picked + 1)
	queue_buttons.remove.disabled = not queue.can_edit(picked)
	queue_buttons.clear.disabled = queue.enabled or queue.entries.is_empty()
	queue_buttons.start.visible = not queue.enabled
	queue_buttons.start.disabled = not queue.can_start() or not at_guild or not party.dispatch_reason(party.hero_ids).is_empty()
	queue_buttons.resume.visible = queue.paused
	queue_buttons.resume.disabled = not at_guild
	queue_buttons.stop.visible = queue.enabled
	queue_buttons.stop.disabled = queue.stop_requested
	if queue.paused:
		queue_status.text = "QUEUE PAUSED\nReason: " + queue.pause_reason
	elif queue.enabled and resting and queue.next_mission() != null:
		queue_status.text = "%s: Resting | Next Mission: %s" % [party.names(queue_ids), queue.next_mission().display_name]
	elif queue.enabled:
		queue_status.text = "Party: %s" % party.names(queue_ids)
	elif queue.entries.is_empty():
		queue_status.text = "Add persistent missions with ADD TO QUEUE."
	elif resting:
		queue_status.text = "The selected party is resting. Stop rest to start the queue."
	else:
		queue_status.text = queue.stop_reason

func show_board() -> void:
	title.text = "EXPEDITION BOARD"
	close_button.visible = true
	board.show()
	summary.hide()
	continue_button.hide()
	show()
	refresh()

func show_summary(automatic: bool = false) -> void:
	title.text = "MISSION COMPLETE" if run.result_status == MissionRun.Result.COMPLETED else "EXPEDITION ENDED"
	# Summaries must be acknowledged with CONTINUE, not closed.
	close_button.visible = false
	board.hide()
	summary.show()
	continue_button.visible = not automatic
	var loot_lines: Array[String] = []
	for item_id in run.collected_loot:
		loot_lines.append("%s x%d" % [run.loot_items[item_id].display_name, run.collected_loot[item_id]])
	var completion: String = "+%d Gold / +%d XP" % [run.completion_gold, run.completion_xp] if run.completion_reward_eligible else "NOT EARNED"
	summary.text = "[b]%s[/b]\nResult: %s | Reason: %s\nEncounters: %d / %d | Ending Energy: %d\n\nCompletion Reward: %s\nCombat Rewards: +%d Gold / +%d XP\n\nLoot:\n%s\n\n[b]Total: Gold +%d / XP +%d[/b]" % [
		run.mission.display_name, MissionRun.Result.keys()[run.result_status], StopConditionEvaluator.reason_text(run.stop_reason),
		run.defeated_encounters, run.total_encounters, run.ending_energy, completion, run.accumulated_gold,
		run.accumulated_xp, "\n".join(loot_lines) if not loot_lines.is_empty() else "No loot collected",
		run.total_gold(), run.total_xp()]
	# Participants: XP is awarded in full to each hero; Gold and loot are shared, paid once.
	if not run.participants.is_empty():
		var party_lines: Array[String] = []
		for hero_id in run.participants:
			var info: Dictionary = run.participants[hero_id]
			party_lines.append("%s Lv %d | XP +%d | Energy %d" % [info.name, info.level, run.hero_xp.get(hero_id, 0),
				run.party_ending_energy.get(hero_id, run.ending_energy)])
		summary.text += "\n\n[b]Party[/b]\n" + "\n".join(party_lines)
	var run_ids: Array[String] = run.party_hero_ids
	var party_name: String = party.names(run_ids)
	var run_ready: bool = party.all_ready(run_ids)
	if queue != null and queue.paused:
		summary.text += "\n\n[b]QUEUE PAUSED[/b]\nReason: %s\nRest or adjust the party, then RESUME QUEUE." % queue.pause_reason
	if automatic and queue != null and queue.running:
		summary.text += "\n\n[b]Expedition Orders:[/b] %s done. Next: %s%s" % [queue.progress_text(),
			queue.next_mission().display_name, "" if run_ready else " after rest."]
	elif automatic:
		if run_ready:
			summary.text += "\n\n[b]Repeat Orders:[/b] Preparing the next run automatically..."
		elif repeat_orders != null and repeat_orders.scheduled_rest_owned:
			summary.text += "\n\n[b]Scheduled Rest:[/b] %s will rest, then resume automatically." % party_name
		else:
			summary.text += "\n\n[b]Repeat Orders paused:[/b] %s needs to recover." % party_name
	show()

func show_queue_summary() -> void:
	var totals: QueueSessionSummary = queue.summary
	title.text = "EXPEDITION ORDERS COMPLETE"
	close_button.visible = false
	board.hide()
	summary.show()
	continue_button.visible = true
	var loot_lines: Array[String] = totals.loot_lines()
	summary.text = "[b]EXPEDITION ORDERS COMPLETE[/b]\n%d / %d missions completed | Retreats: %d | Encounters: %d\n\nGold earned: %d\nXP earned: %d\n\nLoot:\n%s" % [
		totals.missions_completed, queue.entries.size(), totals.retreats, totals.total_encounters,
		totals.gold, totals.xp, "\n".join(loot_lines) if not loot_lines.is_empty() else "No loot collected"]
	show()

func select_opportunity() -> void:
	if board_rotation.slot == null:
		return
	selected_instance = board_rotation.slot
	if repeat_orders != null:
		repeat_orders.select_mission(selected_instance.definition)
	selected = selected_instance.definition
	refresh()

func _on_repeat_toggled(enabled: bool) -> void:
	if repeat_orders != null:
		repeat_orders.set_enabled(selected, enabled)
	refresh()

func _on_send() -> void:
	if selected_instance != null:
		opportunity_requested.emit(selected_instance)
	else:
		dispatch_requested.emit(selected)

func _on_rotation_changed() -> void:
	if selected_instance != null and selected_instance != board_rotation.slot:
		selected_instance = null
		selected = MISSIONS[0]
	if board_rotation.slot == null:
		opportunity_button.text = "ROTATING OPPORTUNITY\nEmpty - waiting for refresh"
		opportunity_button.disabled = true
		opportunity_button.modulate = Color.WHITE
	else:
		var instance: MissionInstance = board_rotation.slot
		var data: MissionData = instance.definition
		opportunity_button.text = "%s\n%s\nLv. %d | %d encounters | %d Gold / %d XP" % [
			"BOSS PORTAL" if instance.special_type == "BOSS" else instance.special_type,
			data.display_name, data.recommended_level, data.encounter_count, data.base_gold_reward, data.base_xp_reward]
		opportunity_button.custom_minimum_size.y = 94
		if data.completion_loot != null:
			opportunity_button.custom_minimum_size.y = 160
			opportunity_button.text += "\nPossible Unique Loot:"
			for item in data.completion_loot.items:
				opportunity_button.text += "\n" + item.display_name
		opportunity_button.disabled = false
		opportunity_button.modulate = Color(1, 0.8, 0.3) if instance.special_type == "BOSS" else (Color(0.8, 0.65, 1) if instance.special_type == "ELITE" else Color.WHITE)
	_update_countdown()
	refresh()

func _update_countdown() -> void:
	if board_rotation.slot != null:
		rotation_status.text = "Expires in: " + board_rotation.slot.countdown_text(board_rotation.now())
	else:
		var seconds: int = maxi(ceili(board_rotation.next_refresh_at - board_rotation.now()), 0)
		rotation_status.text = "Next refresh: %02d:%02d" % [floori(seconds / 60.0), seconds % 60]
	refresh()