class_name GuildMasteryTreeData
extends Resource

@export var tree_id: String = "guild_mastery"
@export var display_name: String = "Guild Mastery"
@export var branches: Dictionary[String, String] = {}
@export var nodes: Array[MasteryNodeData] = []


func find_node(node_id: String) -> MasteryNodeData:
	for node in nodes:
		if node.id == node_id:
			return node
	return null