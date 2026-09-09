extends PanelContainer

var mastery: GuildMasteryState
var wallet: GoldWallet
var selected_id: String = ""
var node_buttons: Dictionary[String, Button] = {}

@onready var currencies: Label = $Margin/Column/Currencies
@onready var modifiers: Label = $Margin/Column/Modifiers
@onready var scroll: ScrollContainer = $Margin/Column/Scroll
@onready var branches: VBoxContainer = $Margin/Column/Scroll/Branches
@onready var details: RichTextLabel = $Margin/Column/Details
@onready var reason: Label = $Margin/Column/Reason
@onready var buy_button: Button = $Margin/Column/Buy


func setup(account_mastery: GuildMasteryState, account_wallet: GoldWallet) -> void:
	mastery = account_mastery
	wallet = account_wallet
	mastery.changed.connect(refresh)
	wallet.changed.connect(refresh)
	buy_button.pressed.connect(_on_buy_pressed)
	for branch_id in mastery.tree.branches:
		var label := Label.new()
		label.text = mastery.tree.branches[branch_id].to_upper()
		branches.add_child(label)
		for node in mastery.tree.nodes:
			if node.branch_id != branch_id:
				continue
			var button := Button.new()
			button.add_theme_font_size_override("font_size", 14)
			button.pressed.connect(select_node.bind(node.id))
			branches.add_child(button)
			node_buttons[node.id] = button
	if not mastery.tree.nodes.is_empty():
		selected_id = mastery.tree.nodes[0].id
	refresh()


func select_node(node_id: String) -> void:
	selected_id = node_id
	refresh()


func refresh() -> void:
	currencies.text = "Gold: %d | Guild Tokens: %d" % [wallet.balance, wallet.guild_tokens]
	modifiers.text = "Guild bonuses: +%d%% Gold / +%d%% XP" % [
		roundi((mastery.global_gold_multiplier - 1.0) * 100),
		roundi((mastery.global_xp_multiplier - 1.0) * 100)
	]
	for node in mastery.tree.nodes:
		var state: String = mastery.node_state(node.id)
		var button: Button = node_buttons[node.id]
		button.text = "%s\n%s" % [node.display_name, state]
		match state:
			"OWNED": button.modulate = Color(0.6, 1.0, 0.7)
			"LOCKED", "NOT YET IMPLEMENTED": button.modulate = Color(0.6, 0.6, 0.65)
			_: button.modulate = Color.WHITE
	var selected: MasteryNodeData = mastery.tree.find_node(selected_id)
	if selected == null:
		buy_button.disabled = true
		return
	var required_names: Array[String] = []
	for prerequisite in selected.prerequisite_ids:
		var required: MasteryNodeData = mastery.tree.find_node(prerequisite)
		required_names.append(required.display_name if required != null else prerequisite)
	details.text = "[b]%s[/b]\nBranch: %s\n%s\n\nCost: %d Gold + %d Guild Tokens\n%s\nRequires: %s\nState: %s" % [
		selected.display_name, mastery.tree.branches.get(selected.branch_id, selected.branch_id),
		selected.description, selected.gold_cost, selected.guild_token_cost, selected.effect_description(),
		", ".join(required_names) if not required_names.is_empty() else "None", mastery.node_state(selected_id)
	]
	var message: String = mastery.purchase_reason(selected_id, wallet)
	buy_button.disabled = not mastery.can_purchase(selected_id, wallet)
	reason.text = message if not message.is_empty() else "Ready to learn"


func _on_buy_pressed() -> void:
	mastery.purchase(selected_id, wallet)