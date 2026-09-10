extends PanelContainer

signal dispatch_requested(mission: MissionData)
signal continue_requested
signal opportunity_requested(instance: MissionInstance)

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
var selected_instance: MissionInstance
var opportunity_button: Button
var rotation_status: Label
@onready var title: Label = $Margin/Column/Title
@onready var board: HBoxContainer = $Margin/Column/Board
@onready var entries: VBoxContainer = $Margin/Column/Board/Scroll/Entries
@onready var details: RichTextLabel = $Margin/Column/Board/Selection/Details
@onready var warning: Label = $Margin/Column/Board/Selection/Warning
@onready var send_button: Button = $Margin/Column/Board/Selection/Send
@onready var summary: RichTextLabel = $Margin/Column/Summary
@onready var continue_button: Button = $Margin/Column/Continue

func setup(mission_run: MissionRun, arthur: Node2D, opportunity_board: MissionBoardRotation = null) -> void:
	$Margin/Column/DebugControls.visible = OS.is_debug_build()
	run = mission_run
	hero = arthur
	board_rotation = opportunity_board
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
	selected = data
	refresh()

func refresh() -> void:
	prediction = StopConditionEvaluator.predict(selected, hero.current_energy, hero.max_energy, run.stop_config)
	details.text = "[b]%s[/b]\n%s | Recommended Level %d\nEncounters: %d | Duration: %s\n\nEnergy: %s\nArthur Energy: %d / %d\nReturn below: %d%%\n\nBase completion reward: %d Gold / %d XP\n(Additional to encounter rewards)\n\nLoot: %s\n\n%s" % [
		selected.display_name, selected.difficulty, selected.recommended_level,
		selected.encounter_count, selected.estimated_duration_text,
		selected.energy_description(),
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
	send_button.disabled = not run.can_start() or (selected_instance != null and not board_rotation.can_claim(selected_instance))

func show_board() -> void:
	title.text = "EXPEDITION BOARD"
	board.show()
	summary.hide()
	continue_button.hide()
	show()
	refresh()

func show_summary() -> void:
	title.text = "MISSION COMPLETE" if run.result_status == MissionRun.Result.COMPLETED else "EXPEDITION ENDED"
	board.hide()
	summary.show()
	continue_button.show()
	var loot_lines: Array[String] = []
	for item_id in run.collected_loot:
		loot_lines.append("%s x%d" % [run.loot_items[item_id].display_name, run.collected_loot[item_id]])
	var completion: String = "+%d Gold / +%d XP" % [run.completion_gold, run.completion_xp] if run.completion_reward_eligible else "NOT EARNED"
	summary.text = "[b]%s[/b]\nResult: %s | Reason: %s\nEncounters: %d / %d | Ending Energy: %d\n\nCompletion Reward: %s\nCombat Rewards: +%d Gold / +%d XP\n\nLoot:\n%s\n\n[b]Total: Gold +%d / XP +%d[/b]" % [
		run.mission.display_name, MissionRun.Result.keys()[run.result_status],
		StopConditionEvaluator.reason_text(run.stop_reason), run.defeated_encounters, run.total_encounters,
		run.ending_energy, completion, run.accumulated_gold, run.accumulated_xp,
		"\n".join(loot_lines) if not loot_lines.is_empty() else "No loot collected",
		run.total_gold(), run.total_xp()]
	show()

func select_opportunity() -> void:
	if board_rotation.slot == null:
		return
	selected_instance = board_rotation.slot
	selected = selected_instance.definition
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
	send_button.disabled = not run.can_start() or (selected_instance != null and not board_rotation.can_claim(selected_instance))