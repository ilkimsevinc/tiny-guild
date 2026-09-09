class_name SkillTreeData
extends Resource

@export var tree_id: String = ""
@export var class_id: String = ""
@export var display_name: String = ""
# Branch definitions can exist before their nodes are designed.
@export var branches: Dictionary[String, String] = {}
@export var nodes: Array[SkillNodeData] = []


func find_node(node_id: String) -> SkillNodeData:
	for node in nodes:
		if node.id == node_id:
			return node
	return null


func branch_name(branch_id: String) -> String:
	return branches.get(branch_id, branch_id.replace("_", " ").capitalize())