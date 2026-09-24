class_name GuildLayout
extends Resource

# Wide, horizontal side-view Guild layout (future taskbar strip friendly).

@export var zones: Array[GuildZoneData] = []
# Where heroes leave for expeditions and come back in (the Guild door).
@export var departure_anchor: Vector2 = Vector2(660, 350)
@export var return_anchor: Vector2 = Vector2(660, 350)
# Backdrop rectangle drawn behind all zones.
@export var bounds: Rect2 = Rect2(40, 200, 880, 162)

func find_zone(zone_id: String) -> GuildZoneData:
	for zone in zones:
		if zone.zone_id == zone_id:
			return zone
	return null

func first_of_type(zone_type: String) -> GuildZoneData:
	for zone in zones:
		if zone.zone_type == zone_type:
			return zone
	return null
