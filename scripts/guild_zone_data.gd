class_name GuildZoneData
extends Resource

# One area of the side-view Guild. Visuals are generated from this data today
# and can later be replaced by pixel-art props without changing Guild logic.

const GENERAL: String = "GENERAL"
const REST: String = "REST"
const EXPEDITION_BOARD: String = "EXPEDITION_BOARD"
const TRAINING: String = "TRAINING"
const TAVERN: String = "TAVERN"
const BLACKSMITH: String = "BLACKSMITH"

@export var zone_id: String = ""
@export var display_name: String = ""
@export_enum("GENERAL", "REST", "EXPEDITION_BOARD", "TRAINING", "TAVERN", "BLACKSMITH") var zone_type: String = GENERAL
# Floor point heroes gather around (world space; the Guild root sits at the origin).
@export var anchor_position: Vector2 = Vector2.ZERO
# Horizontal extent; heroes stand within [left, right] minus a margin.
@export var left: float = 0.0
@export var right: float = 0.0
@export var capacity: int = 2
@export var color: Color = Color(0.2, 0.22, 0.26, 1)
# Placeholder zones are reserved for future NPCs/services.
@export var placeholder_note: String = ""

func contains_x(x: float, margin: float = 0.0) -> bool:
	return x >= left + margin - 0.01 and x <= right - margin + 0.01
