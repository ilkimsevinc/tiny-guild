class_name ViewStateController
extends Node

# Explicit high-level presentation state. Future taskbar mode can add views
# (e.g. a compact strip) without inferring them from combat details.

signal changed(view: View)

enum View { GUILD_VIEW, EXPEDITION_VIEW }

var current: View = View.GUILD_VIEW

func set_view(view: View) -> void:
	if view == current:
		return
	current = view
	changed.emit(view)

func is_guild() -> bool:
	return current == View.GUILD_VIEW

func view_name() -> String:
	return View.keys()[current]
