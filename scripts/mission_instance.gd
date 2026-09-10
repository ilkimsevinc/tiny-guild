class_name MissionInstance
extends RefCounted

var instance_id: String = ""
var mission_data_id: String = ""
var definition: MissionData
var spawned_at: float = 0.0
var expires_at: float = 0.0
var clock: Callable = func() -> float: return Time.get_ticks_msec() / 1000.0
var remaining_time: float:
	get:
		return maxf(expires_at - clock.call(), 0.0)
var mission_modifiers: Dictionary[String, float] = {}
var special_type: String = "NORMAL"
var seed: int = 0
var claimed: bool = false
var active: bool = false
var requires_manual_attention: bool = true

func can_dispatch(now: float) -> bool:
	return not claimed and not active and now < expires_at

func countdown_text(now: float) -> String:
	var seconds: int = maxi(ceili(expires_at - now), 0)
	return "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
