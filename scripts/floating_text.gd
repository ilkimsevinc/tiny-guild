extends Node2D


# Presentation only; callers may request larger, longer-lived rare-loot messages.
func play(message: String, text_color: Color, font_size: int = 24, duration: float = 0.8) -> void:
	$Label.text = message
	$Label.modulate = text_color
	$Label.add_theme_font_size_override("font_size", font_size)
	$Label.offset_left = -180.0
	$Label.offset_right = 180.0
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 45.0, duration)
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.chain().tween_callback(queue_free)