class_name SkillTree
extends Node

signal changed

var class_data: ClassData
var tree: SkillTreeData
var unlocked_ids: Array[String] = []


func load_class(class_id: String) -> bool:
	var class_path: String = "res://data/classes/%s.tres" % class_id
	if not ResourceLoader.exists(class_path):
		return false
	var definition = load(class_path)
	if not definition is ClassData or definition.class_id != class_id:
		return false
	var tree_path: String = "res://data/skill_trees/%s.tres" % definition.skill_tree_id
	if not ResourceLoader.exists(tree_path):
		return false
	var data = load(tree_path)
	if not data is SkillTreeData or data.class_id != class_id or data.tree_id != definition.skill_tree_id:
		return false
	class_data = definition
	tree = data
	unlocked_ids.clear()
	changed.emit()
	return true


func owns(node_id: String) -> bool:
	return node_id in unlocked_ids


func prerequisites_met(node_id: String) -> bool:
	var node: SkillNodeData = tree.find_node(node_id) if tree != null else null
	if node == null:
		return false
	for prerequisite in node.prerequisite_ids:
		if not owns(prerequisite):
			return false
	return true


func node_state(node_id: String) -> String:
	if owns(node_id):
		return "OWNED"
	return "AVAILABLE" if prerequisites_met(node_id) else "LOCKED"


func purchase_reason(node_id: String, gold: int) -> String:
	var node: SkillNodeData = tree.find_node(node_id) if tree != null else null
	if node == null or node.class_id != tree.class_id:
		return "Unknown skill for this class"
	if owns(node_id):
		return "Already learned"
	if node.gold_cost < 0 or node.max_rank != 1 or node.effect_type != "stat_bonus":
		return "Unsupported skill data"
	var missing: Array[String] = []
	for prerequisite in node.prerequisite_ids:
		if not owns(prerequisite):
			var required: SkillNodeData = tree.find_node(prerequisite)
			missing.append(required.display_name if required != null else prerequisite)
	if not missing.is_empty():
		return "Requires " + " and ".join(missing)
	if gold < node.gold_cost:
		return "Not enough Gold"
	return ""


func can_purchase(node_id: String, gold: int) -> bool:
	return purchase_reason(node_id, gold).is_empty()


func purchase(node_id: String, wallet: GoldWallet) -> bool:
	if not can_purchase(node_id, wallet.balance):
		return false
	var node: SkillNodeData = tree.find_node(node_id)
	if not wallet.try_spend(node.gold_cost):
		return false
	unlocked_ids.append(node_id)
	changed.emit()
	return true


func stat_bonus(stat_id: String) -> float:
	var total: float = 0.0
	for node_id in unlocked_ids:
		total += tree.find_node(node_id).effect_value.get(stat_id, 0.0)
	return total


func attack_bonus() -> int:
	return int(stat_bonus("attack"))


func max_hp_bonus() -> int:
	return int(stat_bonus("max_hp"))


func attack_speed_percent() -> float:
	return stat_bonus("attack_speed_percent")