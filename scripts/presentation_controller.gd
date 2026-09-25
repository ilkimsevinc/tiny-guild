class_name PresentationController
extends Node

# Owns everything about HOW the game is shown: window size/position/borders,
# and which of the two coarse UI layouts (full dev HUD vs compact desktop HUD)
# is active. Never touches gameplay state. All real OS window calls are
# guarded so this remains safe to use headless (tests only assert the
# computed state and the pure geometry math below).

signal mode_changed(mode: Mode)

enum Mode { DEVELOPMENT, DESKTOP }

const DEV_SIZE: Vector2i = Vector2i(1280, 720)
# Suggested Milestone 17 desktop prototype size: a short, wide strip.
const DEFAULT_DESKTOP_SIZE: Vector2i = Vector2i(1280, 320)
const MIN_WINDOW_SIZE: Vector2i = Vector2i(320, 120)
# How much of the window must stay reachable on screen while dragging.
const MIN_DRAG_OVERLAP: int = 160
# Fallback screen rect used only when no real display exists (headless tests).
const HEADLESS_SCREEN_FALLBACK: Rect2i = Rect2i(0, 0, 1920, 1080)

@export var desktop_size: Vector2i = DEFAULT_DESKTOP_SIZE
@export var bottom_margin: int = 8
@export var desktop_borderless: bool = true
@export var desktop_always_on_top: bool = true
@export var dev_borderless: bool = false
@export var dev_always_on_top: bool = false
# Height reserved for the compact HUD strip at the top of Desktop mode; the
# Guild/combat stage is shifted up to fit beneath it, above a small floor margin.
@export var desktop_hud_height: float = 96.0
@export var desktop_floor_margin: float = 20.0
# Future taskbar-pet hooks (Milestone 18/19): a see-through window with only
# the Guild/heroes opaque, and clicks passing through empty pixels to
# whatever is behind the window. Both need per-platform window setup this
# milestone deliberately skips, so they stay declared but inert.
@export var transparent_background: bool = false
@export var click_through_background: bool = false

var current: Mode = Mode.DEVELOPMENT
# Last applied (or dragged-to) Desktop window position; Vector2i.MIN means "unset".
var desktop_position: Vector2i = Vector2i(-999999, -999999)

func is_desktop() -> bool:
	return current == Mode.DESKTOP

func mode_name() -> String:
	return Mode.keys()[current]

# --- Stage geometry (pure, presentation-only; never touches gameplay data) ---

# World floor sits at y=350 in Development coordinates; this is how far the
# Stage (Guild + combat) should be shifted so the floor stays visible and
# clear of the compact HUD in the current mode.
func stage_offset() -> Vector2:
	if not is_desktop():
		return Vector2.ZERO
	var target_floor_y: float = clamp_window_size(desktop_size, usable_screen_rect()).y - desktop_floor_margin
	return Vector2(0.0, target_floor_y - 350.0)

func desktop_floor_y() -> float:
	return clamp_window_size(desktop_size, usable_screen_rect()).y - desktop_floor_margin

# --- Pure geometry math: unit-testable without any real display -------------

static func clamp_window_size(desired: Vector2i, screen: Rect2i) -> Vector2i:
	var w: int = clampi(desired.x, MIN_WINDOW_SIZE.x, maxi(screen.size.x, MIN_WINDOW_SIZE.x))
	var h: int = clampi(desired.y, MIN_WINDOW_SIZE.y, maxi(screen.size.y, MIN_WINDOW_SIZE.y))
	return Vector2i(w, h)

# Centered horizontally, resting bottom_margin px above the bottom of the screen.
static func bottom_centered_position(window_size: Vector2i, screen: Rect2i, margin: int) -> Vector2i:
	var x: int = screen.position.x + (screen.size.x - window_size.x) / 2
	var y: int = screen.position.y + screen.size.y - window_size.y - margin
	return Vector2i(x, y)

# Keeps at least min_overlap px of the window horizontally reachable, and the
# whole window within the screen vertically (never pushed fully off the top/bottom).
static func clamp_to_screen(position: Vector2i, window_size: Vector2i, screen: Rect2i, min_overlap: int = MIN_DRAG_OVERLAP) -> Vector2i:
	var overlap: int = mini(min_overlap, window_size.x)
	var min_x: int = screen.position.x - window_size.x + overlap
	var max_x: int = screen.position.x + screen.size.x - overlap
	var min_y: int = screen.position.y
	var max_y: int = maxi(screen.position.y, screen.position.y + screen.size.y - window_size.y)
	return Vector2i(clampi(position.x, min_x, max_x), clampi(position.y, min_y, max_y))

# --- Real display access (no-ops headless) -----------------------------------

func _is_real_window() -> bool:
	return DisplayServer.get_name() != "headless"

func usable_screen_rect() -> Rect2i:
	if not _is_real_window():
		return HEADLESS_SCREEN_FALLBACK
	return DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())

func target_window_size() -> Vector2i:
	var desired: Vector2i = desktop_size if is_desktop() else DEV_SIZE
	return clamp_window_size(desired, usable_screen_rect())

# --- Mode switching -----------------------------------------------------------

func set_mode(mode: Mode) -> void:
	if mode == current:
		return
	current = mode
	if is_desktop() and desktop_position.x <= -999999:
		reset_desktop_position()
	_apply_window_state()
	mode_changed.emit(mode)

func toggle_mode() -> void:
	set_mode(Mode.DESKTOP if current == Mode.DEVELOPMENT else Mode.DEVELOPMENT)

func reset_desktop_position() -> void:
	var size: Vector2i = clamp_window_size(desktop_size, usable_screen_rect())
	desktop_position = bottom_centered_position(size, usable_screen_rect(), bottom_margin)
	if is_desktop():
		_apply_window_state()

# Drags the Desktop window by a pixel delta (e.g. mouse motion), clamped so
# the drag handle always stays reachable.
func drag_by(delta: Vector2i) -> void:
	if not is_desktop():
		return
	var size: Vector2i = clamp_window_size(desktop_size, usable_screen_rect())
	desktop_position = clamp_to_screen(desktop_position + delta, size, usable_screen_rect())
	if _is_real_window():
		DisplayServer.window_set_position(desktop_position)

func minimize() -> void:
	if _is_real_window():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)

func quit() -> void:
	get_tree().quit()

func _apply_window_state() -> void:
	if not _is_real_window():
		return
	var size: Vector2i = target_window_size()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, desktop_borderless if is_desktop() else dev_borderless)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, desktop_always_on_top if is_desktop() else dev_always_on_top)
	DisplayServer.window_set_size(size)
	if is_desktop():
		DisplayServer.window_set_position(clamp_to_screen(desktop_position, size, usable_screen_rect()))

func snapshot() -> Dictionary:
	return {"mode": mode_name(), "desktop_size": desktop_size, "desktop_position": desktop_position,
		"stage_offset": stage_offset(), "window_size": target_window_size() if _is_real_window() else Vector2i.ZERO}
