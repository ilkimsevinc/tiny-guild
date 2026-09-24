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
var hero: Node2D
var mission_buttons: Dictionary[String, Button] = {}
var prediction: String = ""
var board_rotation: MissionBoardRotation
var mastery: GuildMasteryState
var repeat_orders: RepeatOrderState
var recovery: EnergyRecovery
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
@onready var title: Label = $Margin/Column/Title
@onready var board: HBoxContainer = $Margin/Column/Board
@onready var entries: VBoxContainer = $Margin/Column/Board/Scroll/Entries
@onready var details: RichTextLabel = $Margin/Column/Board/Selection/Details
@onready var warning: Label = $Margin/Column/Board/Selection/Warning
@onready var repeat_toggle: CheckButton = $Margin/Column/Board/Selection/RepeatMission
@onready var repeat_reason: Label = $Margin/Column/Board/Selection/RepeatReason
@onready var send_button: Button = $Margin/Column/Board/Selection/Send
@onready var summary: RichTextLabel = $Margin/Column/Summary
@onready var continue_button: Button = $Margin/Column/Continue
@onready var rest_status: Label = $Margin/Column/RestControls/RestStatus
@onready var rest_button: Button = $Margin/Column/RestControls/Rest
@onready var stop_rest_button: Button = $Margin/Column/RestControls/StopRest

func setup(mission_run: MissionRun, arthur: Node2D, opportunity_board: MissionBoardRotation = null,
		mastery_state: GuildMasteryState = null, automation_state: RepeatOrderState = null,
		recovery_state: EnergyRecovery = null, queue_state: MissionQueueState = null) -> void:
	$Margin/Column/DebugControls.visible = OS.is_debug_build()
	run = mission_run
	hero = arthur
	board_rotation = opportunity_board
	mastery = mastery_state
	repeat_orders = automation_state
	recovery = recovery_state
	queue = queue_state
	if queue != null:
		_build_queue_section()
		queue.changed.connect(refresh)
	if recovery != null:
		recovery.changed.connect(refresh)
		rest_button.pressed.connect(recovery.start)
		stop_rest_button.pressed.connect(recovery.stop)
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
	hero.stats_changed.connect(refresh)
	show_board()

func select_mission(data: MissionData) -> void:
	selected_instance = null
	if repeat_orders != null:
		repeat_orders.select_mission(data)
	selected = data
	refresh()

func refresh() -> void:
	if run == null or hero == null or selected == null:
		return
	prediction = StopConditionEvaluator.predict(selected, hero.current_energy, hero.max_energy, run.stop_config)
	details.text = "[b]%s[/b]\n%s | Recommended Level %d\nEncounters: %d | Duration: %s\n\nEnergy: %s\nArthur Energy: %d / %d\nReturn below: %d%%\n\nBase completion reward: %d Gold / %d XP\n(Additional to encounter rewards)\n\nLoot: %s\n\n%s" % [
		selected.display_name, selected.difficulty, selected.recommended_level,
		selected.encounter_count, selected.estimated_duration_text, selected.energy_description(),
		hero.current_energy, hero.max_energy, roundi(run.stop_config.min_energy_percent * 100),
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
	if hero.progression.level < selected.recommended_level:
		warning.text += "\nArthur is below the recommended level."
	var unavailable: String = "Unlock Repeat Orders in Guild Mastery" if repeat_orders == null else repeat_orders.availability_reason(selected)
	if unavailable.is_empty() and queue != null and queue.enabled:
		unavailable = "Repeat Orders unavailable while Expedition Orders are active."
	repeat_toggle.visible = repeat_orders != null and repeat_orders.repeat_unlocked
	repeat_toggle.disabled = not unavailable.is_empty() or not run.can_start()
	repeat_toggle.set_pressed_no_signal(repeat_orders != null and repeat_orders.repeat_enabled and repeat_orders.mission_id == selected.id)
	repeat_reason.text = unavailable
	repeat_reason.visible = not unavailable.is_empty()
	if recovery != null:
		var rate: String = str(snappedf(recovery.recovery_rate(), 0.1)).trim_suffix(".0")
		rest_status.text = "Arthur | Status: %s | Energy: %d / %d | Recovery: +%s / sec" % [
			hero.guild_status.replace("_", " ").capitalize(), hero.current_energy, hero.max_energy, rate]
		var fully_rested: bool = hero.current_energy >= hero.max_energy
		rest_button.disabled = not recovery.can_start() or not run.can_start()
		rest_button.text = "Arthur is fully rested." if fully_rested else "REST"
		stop_rest_button.disabled = not recovery.recovery_enabled
		if recovery.recovery_enabled:
			warning.text += "\nArthur is resting."
	var queue_running: bool = queue != null and queue.running
	if queue_running:
		warning.text += "\nExpedition Orders running."
	send_button.disabled = not run.can_start() or queue_running or (recovery != null and recovery.recovery_enabled) or (selected_instance != null and not board_rotation.can_claim(selected_instance))
	_refresh_queue()

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
	var resting: bool = recovery != null and recovery.recovery_enabled
	queue_buttons.up.disabled = not queue.can_edit(picked) or not queue.can_edit(picked - 1)
	queue_buttons.down.disabled = not queue.can_edit(picked) or not queue.can_edit(picked + 1)
	queue_buttons.remove.disabled = not queue.can_edit(picked)
	queue_buttons.clear.disabled = queue.enabled or queue.entries.is_empty()
	queue_buttons.start.visible = not queue.enabled
	queue_buttons.start.disabled = not queue.can_start() or not at_guild or resting
	queue_buttons.resume.visible = queue.paused
	queue_buttons.resume.disabled = not at_guild
	queue_buttons.stop.visible = queue.enabled
	queue_buttons.stop.disabled = queue.stop_requested
	if queue.paused:
		queue_status.text = "QUEUE PAUSED\nReason: " + queue.pause_reason
	elif queue.enabled and resting and queue.next_mission() != null:
		queue_status.text = "Arthur: Resting | Next Mission: " + queue.next_mission().display_name
	elif queue.enabled:
		queue_status.text = "Arthur: " + hero.guild_status.replace("_", " ").capitalize()
	elif queue.entries.is_empty():
		queue_status.text = "Add persistent missions with ADD TO QUEUE."
	elif resting:
		queue_status.text = "Arthur is resting. Stop rest to start the queue."
	else:
		queue_status.text = queue.stop_reason

func show_board() -> void:
	title.text = "EXPEDITION BOARD"
	board.show()
	summary.hide()
	continue_button.hide()
	show()
	refresh()

func show_summary(automatic: bool = false) -> void:
	title.text = "MISSION COMPLETE" if run.result_status == MissionRun.Result.COMPLETED else "EXPEDITION ENDED"
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
	if queue != null and queue.paused:
		summary.text += "\n\n[b]QUEUE PAUSED[/b]\nReason: %s\nRest or adjust Arthur, then RESUME QUEUE." % queue.pause_reason
	if automatic and queue != null and queue.running:
		summary.text += "\n\n[b]Expedition Orders:[/b] %s done. Next: %s%s" % [queue.progress_text(),
			queue.next_mission().display_name, "" if recovery == null or recovery.is_ready() else " after rest."]
	elif automatic:
		if recovery == null or recovery.is_ready():
			summary.text += "\n\n[b]Repeat Orders:[/b] Preparing the next run automatically..."
		elif repeat_orders != null and repeat_orders.scheduled_rest_owned:
			summary.text += "\n\n[b]Scheduled Rest:[/b] Arthur will rest, then resume automatically."
		else:
			summary.text += "\n\n[b]Repeat Orders paused:[/b] Arthur needs to recover."
	show()

func show_queue_summary() -> void:
	var totals: QueueSessionSummary = queue.summary
	title.text = "EXPEDITION ORDERS COMPLETE"
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