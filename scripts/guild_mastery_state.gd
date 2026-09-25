class_name GuildMasteryState
extends Node

signal changed

@export var tree: GuildMasteryTreeData = preload("res://data/guild_mastery/guild_mastery.tres")
var unlocked_ids: Array[String] = []
var _purchasing: bool = false

var global_gold_multiplier: float:
	get:
		return 1.0 + bonus_percent("global_gold_percent") / 100.0

var global_xp_multiplier: float:
	get:
		return 1.0 + bonus_percent("global_xp_percent") / 100.0


func owns(node_id: String) -> bool:
	return node_id in unlocked_ids


func prerequisites_met(node_id: String) -> bool:
	var node: MasteryNodeData = tree.find_node(node_id)
	if node == null:
		return false
	for prerequisite in node.prerequisite_ids:
		if not owns(prerequisite):
			return false
	return true


func node_state(node_id: String) -> String:
	var node: MasteryNodeData = tree.find_node(node_id)
	if node == null or not node.implemented:
		return "NOT YET IMPLEMENTED"
	if owns(node_id):
		return "OWNED"
	return "AVAILABLE" if prerequisites_met(node_id) else "LOCKED"


func purchase_reason(node_id: String, wallet: GoldWallet) -> String:
	var node: MasteryNodeData = tree.find_node(node_id)
	if node == null:
		return "Unknown mastery"
	if not node.implemented:
		return "System not available"
	if owns(node_id):
		return "Already learned"
	if node.gold_cost < 0 or node.guild_token_cost < 0 or node.max_rank != 1:
		return "Unsupported mastery data"
	var missing: Array[String] = []
	for prerequisite in node.prerequisite_ids:
		if not owns(prerequisite):
			var required: MasteryNodeData = tree.find_node(prerequisite)
			missing.append(required.display_name if required != null else prerequisite)
	if not missing.is_empty():
		return "Requires " + " and ".join(missing)
	if wallet.balance < node.gold_cost:
		return "Not enough Gold"
	if wallet.guild_tokens < node.guild_token_cost:
		return "Not enough Guild Tokens"
	return ""


func can_purchase(node_id: String, wallet: GoldWallet) -> bool:
	return not _purchasing and purchase_reason(node_id, wallet).is_empty()


func purchase(node_id: String, wallet: GoldWallet) -> bool:
	if not can_purchase(node_id, wallet):
		return false
	var node: MasteryNodeData = tree.find_node(node_id)
	_purchasing = true
	if not wallet.try_spend(node.gold_cost, node.guild_token_cost):
		_purchasing = false
		return false
	unlocked_ids.append(node_id)
	_purchasing = false
	changed.emit()
	return true


func bonus_percent(stat_id: String) -> float:
	var total: float = 0.0
	for node_id in unlocked_ids:
		var node: MasteryNodeData = tree.find_node(node_id)
		if node != null and node.implemented:
			total += node.effect_value.get(stat_id, 0.0)
	return total


func has_unlock_tag(tag: String) -> bool:
	for node_id in unlocked_ids:
		var node: MasteryNodeData = tree.find_node(node_id)
		if node != null and node.implemented and tag in node.unlock_tags:
			return true
	return false