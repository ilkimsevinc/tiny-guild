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

# Returns a copy of this single layout rescaled to a different window width
# and floor height, so a narrower Desktop window still shows the same six
# zones (no duplicate layout data) rather than clipping or overflowing.
func scaled_for(target_width: float, floor_y: float, side_margin: float = 20.0) -> GuildLayout:
	var scaled: GuildLayout = duplicate(true)
	var usable: float = maxf(target_width - side_margin * 2.0, 1.0)
	var factor: float = usable / bounds.size.x
	var dx: Callable = func(x: float) -> float: return side_margin + (x - bounds.position.x) * factor
	for zone in scaled.zones:
		zone.left = dx.call(zone.left)
		zone.right = dx.call(zone.right)
		zone.anchor_position = Vector2(dx.call(zone.anchor_position.x), floor_y)
	scaled.departure_anchor = Vector2(dx.call(departure_anchor.x), floor_y)
	scaled.return_anchor = Vector2(dx.call(return_anchor.x), floor_y)
	scaled.bounds = Rect2(side_margin, floor_y - bounds.size.y, usable, bounds.size.y)
	return scaled
