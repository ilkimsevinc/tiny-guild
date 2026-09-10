class_name ExpeditionStopConfig
extends Resource

# A separate config per MissionRun; future Mastery can adjust these values.
@export_range(0.0, 1.0) var min_hp_percent: float = 0.45
@export_range(0.0, 1.0) var min_energy_percent: float = 0.35
@export var inventory_capacity: int = 10
@export_range(0.0, 1.0) var inventory_return_percent: float = 0.80
@export var encounter_cap: int = 8
@export var return_on_hero_downed: bool = true
# Random loot should not determine normal retreat timing in this milestone.
@export var inventory_stop_enabled: bool = false
