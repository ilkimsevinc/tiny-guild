extends Node2D


# Presentation only: callers supply text, color, and a spawn position.
func play(message: String, text_color: Color) -> void:
	$Label.text = message
	$Label.modulate = text_color
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 45.0, 0.8)
	tween.tween_property(self, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(queue_free)