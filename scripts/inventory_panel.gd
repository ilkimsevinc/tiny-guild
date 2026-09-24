extends PanelContainer

var inventory: Inventory
var equipment: Equipment
var selected_item_id: String = ""
var selected_slot: int = -1

@onready var inventory_list: ItemList = $Margin/Column/InventoryList
@onready var equipment_list: ItemList = $Margin/Column/EquipmentList
@onready var details: RichTextLabel = $Margin/Column/Details
@onready var equip_button: Button = $Margin/Column/EquipButton
@onready var unequip_button: Button = $Margin/Column/UnequipButton


func setup(item_inventory: Inventory, hero_equipment: Equipment) -> void:
	inventory = item_inventory
	equipment = hero_equipment
	inventory.changed.connect(refresh)
	equipment.changed.connect(refresh)
	inventory_list.item_selected.connect(_on_inventory_selected)
	equipment_list.item_selected.connect(_on_equipment_selected)
	equip_button.pressed.connect(_on_equip_pressed)
	unequip_button.pressed.connect(_on_unequip_pressed)
	refresh()


# Inventory stays account-wide; only the equipment view follows the selected hero.
func set_equipment(hero_equipment: Equipment, hero_name: String = "") -> void:
	if equipment != null and equipment.changed.is_connected(refresh):
		equipment.changed.disconnect(refresh)
	equipment = hero_equipment
	equipment.changed.connect(refresh)
	if not hero_name.is_empty():
		$Margin/Column/EquipmentTitle.text = hero_name.to_upper() + " EQUIPMENT"
	selected_slot = -1
	equipment_list.deselect_all()
	refresh()


func refresh() -> void:
	inventory_list.clear()
	for item in inventory.get_items():
		var index: int = inventory_list.add_item("%s x%d" % [item.display_name, inventory.quantity(item.id)])
		inventory_list.set_item_metadata(index, item.id)
		inventory_list.set_item_custom_fg_color(index, item.rarity_color())
		if item.id == selected_item_id:
			inventory_list.select(index)
	equipment_list.clear()
	for slot in range(4):
		var item: ItemData = equipment.get_item(slot)
		var item_name: String = item.display_name if item != null else "Empty"
		var index: int = equipment_list.add_item("%s: %s" % [Equipment.SLOT_NAMES[slot], item_name])
		if item != null:
			equipment_list.set_item_custom_fg_color(index, item.rarity_color())
		if slot == selected_slot:
			equipment_list.select(index)
	_update_details()


func _on_inventory_selected(index: int) -> void:
	selected_item_id = inventory_list.get_item_metadata(index)
	selected_slot = -1
	equipment_list.deselect_all()
	_update_details()


func _on_equipment_selected(index: int) -> void:
	selected_slot = index
	selected_item_id = ""
	inventory_list.deselect_all()
	_update_details()


func _update_details() -> void:
	var item: ItemData
	if selected_slot >= 0:
		item = equipment.get_item(selected_slot)
	else:
		item = inventory.get_item(selected_item_id)
	equip_button.disabled = item == null or selected_slot >= 0 or not item.is_equippable()
	unequip_button.disabled = item == null or selected_slot < 0
	if item == null:
		details.text = "Select an item to see its details."
		return
	details.text = "[color=#%s][b]%s[/b][/color]\n%s | %s\n\n%s\n\n%s" % [
		item.rarity_color().to_html(false), item.display_name, item.rarity_name(),
		ItemData.ItemType.keys()[item.item_type].capitalize(), item.description, item.bonus_description()
	]


func _on_equip_pressed() -> void:
	equipment.equip(inventory, selected_item_id)


func _on_unequip_pressed() -> void:
	equipment.unequip(inventory, selected_slot)