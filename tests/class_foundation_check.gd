# Run: godot --headless --path . --script res://tests/class_foundation_check.gd
extends SceneTree

const EXPECTED_BRANCHES: Dictionary = {
	"knight": ["Guardian", "Vanguard", "Crusader"],
	"mage": ["Fire", "Frost", "Arcane"],
	"ranger": ["Sniper", "Hunter", "Poison"],
	"rogue": ["Assassin", "Duelist", "Shadowstep"],
	"kitsune_samurai": ["Iaijutsu", "Counterblade", "Foxfire"],
	"fighter": ["Brawler", "Juggernaut", "Gym Rat"],
	"artificer": ["Engineer", "Bombardier", "Gadgeteer"],
	"blacksmith": ["Forgeguard", "Battlesmith", "Runeforge"],
	"legendary_dark_mage": ["Shadow Sovereign", "Void", "Eclipse"],
	"legendary_fighter_mage": ["Flame Fist", "Inferno Guard", "Solar Wrath"],
}
const PANEL_SCENE = preload("res://scenes/skill_tree_panel.tscn")
var failures: int = 0


func _initialize() -> void:
	run_check.call_deferred()


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)


func run_check() -> void:
	var wallet := GoldWallet.new()
	wallet.add_gold(500)
	var controller := SkillTree.new()
	var panel = PANEL_SCENE.instantiate()
	root.add_child(panel)
	for class_id in EXPECTED_BRANCHES:
		check(controller.load_class(class_id), "Class loads: " + class_id)
		var definition: ClassData = controller.class_data
		check(definition.class_id == class_id and not definition.display_name.is_empty()
			and not definition.description.is_empty() and definition.skill_tree_id == controller.tree.tree_id,
			"Class definition resolves its tree: " + class_id)
		check(controller.tree.class_id == class_id, "Tree class matches definition")
		for branch_name in EXPECTED_BRANCHES[class_id]:
			check(branch_name in controller.tree.branches.values(), "Branch defined: " + branch_name)
		panel.setup(controller, wallet, "Test Hero")
		check(panel.title.text.contains("Test Hero") and panel.title.text.contains(definition.display_name),
			"Reusable header reads supplied hero and class")
		if class_id != "knight":
			check(controller.tree.nodes.is_empty() and controller.attack_bonus() == 0
				and controller.max_hp_bonus() == 0 and controller.attack_speed_percent() == 0,
				"Future class remains data-only: " + class_id)
			check(panel.node_buttons.is_empty() and panel.buy_button.disabled
				and panel.details.text.contains("No skills available"), "Empty tree has safe UI state")
			check(not controller.purchase("battle_training", wallet) and wallet.balance == 500,
				"Future class cannot buy Knight skills or spend Gold")
		wallet.add_gold(1)
		wallet.try_spend(1)
	controller.load_class("knight")
	panel.setup(controller, wallet, "Arthur")
	check(panel.node_buttons.size() == 4 and panel.rows.get_child_count() == 5,
		"Rebinding panel restores four nodes without duplicates")
	var expected_tiers: Dictionary = {"battle_training": 1, "iron_body": 2, "quick_strikes": 2, "veteran": 3}
	for node in controller.tree.nodes:
		check(node.class_id == "knight" and node.max_rank == 1
			and node.tier == expected_tiers[node.id] and controller.tree.branches.has(node.branch_id),
			"Knight node has class, branch, tier, and rank: " + node.id)
	panel.select_node("iron_body")
	check(panel.details.text.contains("Branch: Foundation | Tier 2"), "Details include branch and tier")
	var shared := SkillTree.new()
	shared.load_class("knight")
	check(controller.tree == shared.tree and controller.class_data == shared.class_data,
		"Class/tree Resources are shared, not bound to character names")
	check(controller.purchase("battle_training", wallet) and not shared.owns("battle_training"),
		"Controller state stays independent from shared class data")
	check(not controller.load_class("not_a_class") and controller.owns("battle_training"),
		"Unknown class leaves current valid state intact")
	# Effect data can hold several future stats without introducing their gameplay.
	var effect := SkillNodeData.new()
	effect.id = "effect_model_test"
	effect.class_id = "test"
	effect.effect_value = {"attack": 2.0, "crit_chance_percent": 5.0, "gold_find_percent": 10.0}
	check(effect.effect_description().contains("+5% Crit Chance")
		and effect.effect_description().contains("+10% Gold Find"), "Generic descriptions support crit and hero Gold Find")
	var effect_tree := SkillTree.new()
	effect_tree.tree = SkillTreeData.new()
	effect_tree.tree.class_id = "test"
	effect_tree.tree.nodes.append(effect)
	check(effect_tree.purchase(effect.id, wallet) and effect_tree.stat_bonus("crit_chance_percent") == 5.0
		and effect_tree.stat_bonus("gold_find_percent") == 10.0 and effect_tree.attack_bonus() == 2,
		"Multiple stat effects aggregate generically")
	# Tier layout must work even when data is no longer prerequisite-first.
	var reordered: SkillTreeData = controller.tree.duplicate()
	reordered.nodes.reverse()
	controller.tree = reordered
	controller.changed.emit()
	check(panel.node_buttons["battle_training"].get_parent() == panel.rows.get_child(0)
		and panel.node_buttons["veteran"].get_parent() == panel.rows.get_child(4),
		"Explicit tiers determine rows independently of array order")
	panel.queue_free()
	await process_frame
	controller.free()
	shared.free()
	effect_tree.free()
	wallet.free()
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	check(main.arthur.class_id == "knight" and main.arthur.skills.class_data.skill_tree_id == "knight"
		and main.arthur.skills.tree.tree_id == "knight", "Arthur retrieves Knight tree through ClassData")
	check(main.skill_ui.title.text.contains("Arthur") and main.skill_ui.title.text.contains("Knight"),
		"Gameplay panel header shows Arthur and Knight")
	check(main.get_node("UI/Sidebar").get_tab_count() == 2, "No extra future-class UI tabs or characters")
	print("Class foundation check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)