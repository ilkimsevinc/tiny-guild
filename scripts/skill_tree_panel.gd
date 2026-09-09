extends PanelContainer

var skills: SkillTree
var wallet: GoldWallet
var hero_display_name: String = ""
var shown_tree: SkillTreeData
var selected_id: String = ""
var node_buttons: Dictionary[String, Button] = {}

@onready var title: Label = $Margin/Column/Title
@onready var rows: VBoxContainer = $Margin/Column/Rows
@onready var details: RichTextLabel = $Margin/Column/Details
@onready var reason_label: Label = $Margin/Column/Reason
@onready var buy_button: Button = $Margin/Column/Buy


func setup(class_skills: SkillTree, gold_wallet: GoldWallet, hero_name: String = "") -> void:
	# The same panel can be rebound to a different class without stale connections.
	if is_instance_valid(skills) and skills.changed.is_connected(refresh):
		skills.changed.disconnect(refresh)
	if is_instance_valid(wallet) and wallet.changed.is_connected(refresh):
		wallet.changed.disconnect(refresh)
	skills = class_skills
	wallet = gold_wallet
	hero_display_name = hero_name
	shown_tree = null
	skills.changed.connect(refresh)
	wallet.changed.connect(refresh)
	if not buy_button.pressed.is_connected(_on_buy_pressed):
		buy_button.pressed.connect(_on_buy_pressed)
	refresh()


func _build_rows() -> void:
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	node_buttons.clear()
	shown_tree = skills.tree
	selected_id = ""
	var row_nodes: Array[HBoxContainer] = []
	# Tier data determines layout; Resource array order does not determine placement.
	for node in shown_tree.nodes:
		var depth: int = maxi(node.tier - 1, 0)
		while row_nodes.size() <= depth:
			if not row_nodes.is_empty():
				var arrow := Label.new()
				arrow.text = "↓"
				arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				rows.add_child(arrow)
			var row := HBoxContainer.new()
			rows.add_child(row)
			row_nodes.append(row)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(select_node.bind(node.id))
		row_nodes[depth].add_child(button)
		node_buttons[node.id] = button
	if not shown_tree.nodes.is_empty():
		selected_id = shown_tree.nodes[0].id


func select_node(node_id: String) -> void:
	selected_id = node_id
	refresh()


func refresh() -> void:
	if skills.tree != shown_tree:
		_build_rows()
	var class_name_text: String = skills.class_data.display_name
	title.text = "%s%s\n%s" % [
		hero_display_name + " - " if not hero_display_name.is_empty() else "",
		class_name_text, skills.tree.display_name.to_upper()
	]
	for node in skills.tree.nodes:
		var state: String = skills.node_state(node.id)
		var button: Button = node_buttons[node.id]
		button.text = "%s\n%s\n%d Gold\n%s" % [
			node.display_name, node.effect_description(), node.gold_cost, state
		]
		match state:
			"LOCKED": button.modulate = Color(0.6, 0.6, 0.65)
			"OWNED": button.modulate = Color(0.6, 1.0, 0.7)
			_: button.modulate = Color.WHITE
	var selected: SkillNodeData = skills.tree.find_node(selected_id)
	if selected == null:
		buy_button.disabled = true
		details.text = "No skills available for this class yet."
		reason_label.text = "Tree definition only"
		return
	var prerequisites: Array[String] = []
	for prerequisite in selected.prerequisite_ids:
		var required: SkillNodeData = skills.tree.find_node(prerequisite)
		prerequisites.append(required.display_name if required != null else prerequisite)
	details.text = "[b]%s[/b]\n%s\n\nBranch: %s | Tier %d\nCost: %d Gold\nEffect: %s\nRequires: %s\nState: %s" % [
		selected.display_name, selected.description, skills.tree.branch_name(selected.branch_id),
		selected.tier, selected.gold_cost, selected.effect_description(),
		", ".join(prerequisites) if not prerequisites.is_empty() else "None", skills.node_state(selected_id)
	]
	var reason: String = skills.purchase_reason(selected_id, wallet.balance)
	buy_button.disabled = not reason.is_empty()
	reason_label.text = reason if not reason.is_empty() else "Ready to learn"


func _on_buy_pressed() -> void:
	skills.purchase(selected_id, wallet)