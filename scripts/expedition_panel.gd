extends PanelContainer

signal dispatch_requested(mission: MissionData)
signal continue_requested

const MISSIONS: Array[MissionData] = [
	preload("res://data/missions/forest_patrol.tres"),
	preload("res://data/missions/slime_nest.tres"),
	preload("res://data/missions/treasure_trail.tres")]
var selected: MissionData = MISSIONS[0]
var run: MissionRun
var hero: Node2D
var mission_buttons: Dictionary[String, Button] = {}
@onready var title: Label = $Margin/Column/Title
@onready var board: HBoxContainer = $Margin/Column/Board
@onready var entries: VBoxContainer = $Margin/Column/Board/Scroll/Entries
@onready var details: RichTextLabel = $Margin/Column/Board/Selection/Details
@onready var warning: Label = $Margin/Column/Board/Selection/Warning
@onready var send_button: Button = $Margin/Column/Board/Selection/Send
@onready var summary: RichTextLabel = $Margin/Column/Summary
@onready var continue_button: Button = $Margin/Column/Continue

func setup(mission_run: MissionRun, arthur: Node2D) -> void:
	run = mission_run
	hero = arthur
	for data in MISSIONS:
		var button := Button.new()
		button.text = "%s | %s | Lv. %d\n%d encounters | %s\nCompletion: %d Gold / %d XP\n%s" % [
			data.display_name, data.difficulty, data.recommended_level, data.encounter_count,
			data.estimated_duration_text, data.base_gold_reward, data.base_xp_reward, data.loot_identity]
		button.custom_minimum_size = Vector2(350, 116)
		button.add_theme_font_size_override("font_size", 15)
		button.pressed.connect(select_mission.bind(data))
		entries.add_child(button)
		var description := Label.new()
		description.text = data.description
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 14)
		entries.add_child(description)
		mission_buttons[data.id] = button
	send_button.pressed.connect(func(): dispatch_requested.emit(selected))
	continue_button.pressed.connect(func(): continue_requested.emit())
	run.changed.connect(refresh)
	hero.stats_changed.connect(refresh)
	show_board()

func select_mission(data: MissionData) -> void:
	selected = data
	refresh()

func refresh() -> void:
	details.text = "[b]%s[/b]\n%s | Recommended Level %d\nEncounters: %d | Duration: %s\n\nBase completion reward:\n%d Gold / %d XP\n(Additional to encounter rewards)\n\nLoot: %s\n\n%s" % [
		selected.display_name, selected.difficulty, selected.recommended_level,
		selected.encounter_count, selected.estimated_duration_text,
		selected.base_gold_reward, selected.base_xp_reward, selected.loot_description(), selected.description]
	warning.text = "Arthur is below the recommended level." if hero.progression.level < selected.recommended_level else ""
	send_button.disabled = not run.can_start()

func show_board() -> void:
	title.text = "EXPEDITION BOARD"
	board.show()
	summary.hide()
	continue_button.hide()
	show()
	refresh()

func show_summary() -> void:
	title.text = "MISSION COMPLETE"
	board.hide()
	summary.show()
	continue_button.show()
	var loot_lines: Array[String] = []
	for item_id in run.collected_loot:
		loot_lines.append("%s x%d" % [run.loot_items[item_id].display_name, run.collected_loot[item_id]])
	summary.text = "[b]%s[/b]\nEncounters: %d / %d\n\nMission Reward: +%d Gold / +%d XP\nCombat Rewards: +%d Gold / +%d XP\n\nLoot:\n%s\n\n[b]Total: Gold +%d / XP +%d[/b]" % [
		run.mission.display_name, run.defeated_encounters, run.total_encounters,
		run.completion_gold, run.completion_xp, run.accumulated_gold, run.accumulated_xp,
		"\n".join(loot_lines) if not loot_lines.is_empty() else "No loot collected",
		run.total_gold(), run.total_xp()]
	show()
