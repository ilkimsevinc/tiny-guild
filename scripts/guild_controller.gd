class_name GuildController
extends Node2D

# Greybox Guild interior: builds zone placeholders from GuildLayout data and
# manages each hero's physical Guild presence (GuildHeroAvatar). Gameplay state
# (Energy, rest, missions) stays in the existing systems; this layer only
# reflects it spatially.

signal open_expedition_board
signal party_departed

const MIN_SPACING: float = 48.0
const ZONE_MARGIN: float = 12.0
const IDLE_MIN_SECONDS: float = 5.0
const IDLE_MAX_SECONDS: float = 12.0
# Idle steps stay near the current spot rather than crossing the zone.
const IDLE_STEP: float = 45.0
const DEPARTURE_SECONDS: float = 0.8
const WALK_SPEED_FACTOR: float = 1.0
const REST_ZONE_TYPE: String = GuildZoneData.REST
const BOARD_ZONE_TYPE: String = GuildZoneData.EXPEDITION_BOARD

@export var layout: GuildLayout = preload("res://data/guild/guild_layout.tres")
@export var idle_seed: int = 1606

var avatars: Dictionary[String, GuildHeroAvatar] = {}
# zone_id -> hero_ids currently assigned there.
var zone_assignments: Dictionary[String, Array] = {}
var idle_frozen: bool = false
var rng := RandomNumberGenerator.new()
var _was_resting: Dictionary[String, bool] = {}
var _avatar_layer: Node2D

func _ready() -> void:
	rng.seed = idle_seed
	z_index = 5
	_build_greybox()

func setup(heroes: Array[HeroController], recoveries: Dictionary) -> void:
	for member in heroes:
		var avatar := GuildHeroAvatar.new()
		avatar.setup(member, WALK_SPEED_FACTOR)
		_avatar_layer.add_child(avatar)
		avatars[member.hero_id] = avatar
		avatar.idle_timer = _next_idle_delay()
		place_in_zone(member, home_zone_id(member), true)
		var recovery: EnergyRecovery = recoveries.get(member.hero_id)
		if recovery != null:
			_was_resting[member.hero_id] = false
			recovery.changed.connect(_on_recovery_changed.bind(member, recovery))

# --- Zone queries -------------------------------------------------------------

func zone(zone_id: String) -> GuildZoneData:
	return layout.find_zone(zone_id)

func zone_ids() -> Array[String]:
	var ids: Array[String] = []
	for data in layout.zones:
		ids.append(data.zone_id)
	return ids

func rest_zone_id() -> String:
	return layout.first_of_type(REST_ZONE_TYPE).zone_id

func board_zone_id() -> String:
	return layout.first_of_type(BOARD_ZONE_TYPE).zone_id

func home_zone_id(member: HeroController) -> String:
	var wanted: String = member.hero_data.guild_home_zone
	return wanted if zone(wanted) != null else layout.first_of_type(GuildZoneData.GENERAL).zone_id

func assigned_heroes(zone_id: String) -> Array:
	return zone_assignments.get(zone_id, [])

func avatar(member: HeroController) -> GuildHeroAvatar:
	return avatars.get(member.hero_id)

func zone_of(member: HeroController) -> String:
	var body: GuildHeroAvatar = avatar(member)
	return body.zone_id if body != null else ""

func is_in_guild(member: HeroController) -> bool:
	var body: GuildHeroAvatar = avatar(member)
	return body != null and not body.away

# --- Movement -----------------------------------------------------------------

# Assigns the hero to a zone and walks (or teleports) to a free spot in it.
func place_in_zone(member: HeroController, zone_id: String, instant: bool = false) -> void:
	var body: GuildHeroAvatar = avatar(member)
	var data: GuildZoneData = zone(zone_id)
	if body == null or data == null:
		return
	_assign(member.hero_id, zone_id)
	body.zone_id = zone_id
	var x: float = _free_spot(data, member.hero_id, data.anchor_position.x)
	if instant:
		body.teleport(Vector2(x, data.anchor_position.y))
	else:
		body.walk_to(x)

func send_home(member: HeroController) -> void:
	place_in_zone(member, home_zone_id(member))

# Walk every hero to the Guild door, then hide them. Emits party_departed.
func depart(members: Array[HeroController]) -> float:
	for member in members:
		var body: GuildHeroAvatar = avatar(member)
		if body == null:
			continue
		_unassign(member.hero_id)
		body.zone_id = ""
		body.pinned = false
		body.leave_via(layout.departure_anchor, DEPARTURE_SECONDS)
	var timer := get_tree().create_timer(DEPARTURE_SECONDS)
	timer.timeout.connect(func(): party_departed.emit())
	return DEPARTURE_SECONDS

# Returning heroes appear at the door and walk to their Guild spot.
func return_heroes(members: Array[HeroController]) -> void:
	for member in members:
		var body: GuildHeroAvatar = avatar(member)
		if body == null:
			continue
		body.enter_at(layout.return_anchor)
		body.pinned = false
		place_in_zone(member, home_zone_id(member))

# Automation: gather at the Expedition Board before the next departure.
func gather_at_board(members: Array[HeroController]) -> void:
	for member in members:
		if is_in_guild(member):
			place_in_zone(member, board_zone_id())
			avatar(member).pinned = true

func request_open_board() -> void:
	open_expedition_board.emit()

# --- Idle wandering -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if idle_frozen:
		return
	for hero_id in avatars:
		var body: GuildHeroAvatar = avatars[hero_id]
		if not _can_wander(body):
			continue
		body.idle_timer -= delta
		if body.idle_timer <= 0.0:
			wander(body.hero)

func _can_wander(body: GuildHeroAvatar) -> bool:
	return not body.away and not body.moving and not body.pinned \
		and body.hero.guild_status in ["IDLE_AT_GUILD", "READY"] and not body.zone_id.is_empty()

# Picks a nearby free point inside the current zone (seeded, so tests repeat).
func wander(member: HeroController) -> void:
	var body: GuildHeroAvatar = avatar(member)
	var data: GuildZoneData = zone(body.zone_id)
	body.idle_timer = _next_idle_delay()
	if data == null:
		return
	var wish: float = body.position.x + rng.randf_range(-IDLE_STEP, IDLE_STEP)
	body.walk_to(_free_spot(data, member.hero_id, wish))

func _next_idle_delay() -> float:
	return rng.randf_range(IDLE_MIN_SECONDS, IDLE_MAX_SECONDS)

# --- Rest integration ---------------------------------------------------------

# Resting heroes walk to the Rest Area; when rest ends (READY or STOP REST)
# they walk back to their home zone. Recovery itself stays in EnergyRecovery.
func _on_recovery_changed(member: HeroController, recovery: EnergyRecovery) -> void:
	var resting: bool = recovery.recovery_enabled
	if resting == _was_resting.get(member.hero_id, false):
		return
	_was_resting[member.hero_id] = resting
	if not is_in_guild(member):
		return
	if resting:
		avatar(member).pinned = false
		place_in_zone(member, rest_zone_id())
	elif not avatar(member).pinned:
		send_home(member)

# --- Spacing helpers ----------------------------------------------------------

func _free_spot(data: GuildZoneData, hero_id: String, wish: float) -> float:
	var low: float = data.left + ZONE_MARGIN
	var high: float = data.right - ZONE_MARGIN
	# Scan the zone: nearest spacing-safe spot to the wish, else the roomiest spot.
	var best_free: float = NAN
	var roomiest: float = clampf(wish, low, high)
	var roomiest_gap: float = -1.0
	var x: float = low
	while x <= high + 0.01:
		var gap: float = _nearest_other(x, hero_id)
		if gap >= MIN_SPACING and (is_nan(best_free) or absf(x - wish) < absf(best_free - wish)):
			best_free = x
		if gap > roomiest_gap:
			roomiest_gap = gap
			roomiest = x
		x += 2.0
	var preferred: float = clampf(wish, low, high)
	if _nearest_other(preferred, hero_id) >= MIN_SPACING:
		return preferred
	return best_free if not is_nan(best_free) else roomiest

# Distance to the closest other hero in the Guild (using where they are heading).
func _nearest_other(x: float, hero_id: String) -> float:
	var nearest: float = INF
	for other_id in avatars:
		if other_id == hero_id:
			continue
		var other: GuildHeroAvatar = avatars[other_id]
		if other.away:
			continue
		var other_x: float = other.target_x if other.moving else other.position.x
		nearest = minf(nearest, absf(other_x - x))
	return nearest

func _assign(hero_id: String, zone_id: String) -> void:
	_unassign(hero_id)
	if not zone_assignments.has(zone_id):
		zone_assignments[zone_id] = []
	zone_assignments[zone_id].append(hero_id)

func _unassign(hero_id: String) -> void:
	for zone_id in zone_assignments:
		zone_assignments[zone_id].erase(hero_id)

# --- Debug --------------------------------------------------------------------

func debug_teleport(member: HeroController, zone_id: String) -> void:
	if is_in_guild(member):
		place_in_zone(member, zone_id, true)

func describe_positions() -> Dictionary:
	var info: Dictionary = {}
	for hero_id in avatars:
		var body: GuildHeroAvatar = avatars[hero_id]
		info[hero_id] = {"zone": body.zone_id, "x": roundi(body.position.x), "state": body.state_name()}
	return info

# --- Greybox visuals (replaceable by art later) -------------------------------

func _build_greybox() -> void:
	var backdrop := ColorRect.new()
	backdrop.position = layout.bounds.position
	backdrop.size = layout.bounds.size
	backdrop.color = Color(0.1, 0.11, 0.14, 1)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var top: float = layout.bounds.position.y
	var floor_y: float = layout.zones[0].anchor_position.y if not layout.zones.is_empty() else 350.0
	for data in layout.zones:
		var area := ColorRect.new()
		area.position = Vector2(data.left + 2, top + 4)
		area.size = Vector2(data.right - data.left - 4, floor_y - top - 4)
		area.color = data.color
		area.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(area)
		var label := Label.new()
		label.text = data.display_name + ("\n(" + data.placeholder_note + ")" if not data.placeholder_note.is_empty() else "")
		label.position = Vector2(data.left + 6, top + 6)
		# Keep text inside its zone rectangle.
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9, 0.9))
		add_child(label)
		# Width is set last (after theme overrides) so the text wraps inside its zone.
		label.custom_minimum_size = Vector2(data.right - data.left - 12, 0)
		label.size = label.custom_minimum_size
		if data.zone_type == BOARD_ZONE_TYPE:
			var board := ColorRect.new()
			board.position = Vector2(data.anchor_position.x - 34, top + 44)
			board.size = Vector2(68, 50)
			board.color = Color(0.45, 0.33, 0.2, 1)
			board.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(board)
	var door := ColorRect.new()
	door.position = Vector2(layout.departure_anchor.x - 16, floor_y - 78)
	door.size = Vector2(32, 78)
	door.color = Color(0.33, 0.26, 0.2, 1)
	door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(door)
	var floor_line := Line2D.new()
	floor_line.points = PackedVector2Array([Vector2(layout.bounds.position.x, floor_y), Vector2(layout.bounds.end.x, floor_y)])
	floor_line.width = 4.0
	floor_line.default_color = Color(0.4, 0.42, 0.48, 1)
	add_child(floor_line)
	_avatar_layer = Node2D.new()
	_avatar_layer.name = "Avatars"
	add_child(_avatar_layer)
