class_name GuildHeroAvatar
extends Node2D

# A hero's physical presence inside the Guild. Separate from the combat
# HeroController so Guild presentation never touches combat movement.
# Visuals are a copy of the hero's placeholder and can be swapped for sprites.

signal arrived(avatar: GuildHeroAvatar)

enum GuildState { GUILD_IDLE, GUILD_MOVING, GUILD_RESTING, GUILD_READY, AWAY }

var hero: HeroController
var zone_id: String = ""
var target_x: float = 0.0
var moving: bool = false
# Hidden while the hero is on an expedition.
var away: bool = false
# Held in place for automation (e.g. waiting at the Expedition Board).
var pinned: bool = false
var walk_speed: float = 120.0
var idle_timer: float = 0.0
var visuals: Node2D
var travel_tween: Tween

var guild_state: GuildState:
	get:
		if away:
			return GuildState.AWAY
		if moving:
			return GuildState.GUILD_MOVING
		match hero.guild_status:
			"RESTING": return GuildState.GUILD_RESTING
			"READY": return GuildState.GUILD_READY
		return GuildState.GUILD_IDLE

func setup(member: HeroController, speed_factor: float) -> void:
	hero = member
	name = member.hero_id.capitalize() + "Avatar"
	walk_speed = member.move_speed * speed_factor
	visuals = member.get_node("Visuals").duplicate()
	visuals.position = Vector2.ZERO
	visuals.modulate = Color.WHITE
	visuals.scale = Vector2.ONE
	add_child(visuals)
	var label := Label.new()
	label.text = member.display_name
	label.position = Vector2(-30, 4)
	label.add_theme_font_size_override("font_size", 12)
	add_child(label)

func state_name() -> String:
	return GuildState.keys()[guild_state]

func walk_to(x: float) -> void:
	_kill_tween()
	target_x = x
	moving = absf(position.x - x) > 0.5
	if not moving:
		position.x = x

func teleport(point: Vector2) -> void:
	_kill_tween()
	position = point
	target_x = point.x
	moving = false

# Fixed-duration walk (used for brisk departures) that ends hidden.
func leave_via(point: Vector2, seconds: float) -> void:
	_kill_tween()
	moving = true
	_face(point.x)
	travel_tween = create_tween()
	travel_tween.tween_property(self, "position", point, seconds)
	travel_tween.tween_callback(func():
		moving = false
		away = true
		visible = false)

func enter_at(point: Vector2) -> void:
	away = false
	visible = true
	teleport(point)

func _physics_process(delta: float) -> void:
	if not moving or (travel_tween != null and travel_tween.is_running()):
		return
	_face(target_x)
	position.x = move_toward(position.x, target_x, walk_speed * delta)
	if absf(position.x - target_x) <= 0.5:
		position.x = target_x
		moving = false
		visuals.scale.x = 1.0
		arrived.emit(self)

func _face(x: float) -> void:
	if not is_zero_approx(x - position.x):
		visuals.scale.x = signf(x - position.x)

func _kill_tween() -> void:
	if travel_tween != null:
		travel_tween.kill()
		travel_tween = null
