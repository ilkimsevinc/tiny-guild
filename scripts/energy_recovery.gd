class_name EnergyRecovery
extends Node

# Guild-side Energy recovery. Owns the RESTING/READY/IDLE_AT_GUILD transitions;
# expedition states (ON_EXPEDITION/RETURNING) are set by the mission flow.

signal changed
signal ready_reached

const AT_GUILD_STATUSES: Array[String] = ["IDLE_AT_GUILD", "READY"]

@export var base_energy_recovery_per_second: float = 5.0
# Fraction of max Energy that counts as READY for automation.
@export_range(0.01, 1.0, 0.01) var ready_threshold: float = 1.0
# Energy is granted in whole ticks so the bar visibly steps (28 -> 33 -> 38).
@export var tick_seconds: float = 1.0

var hero: Node
var recovery_enabled: bool = false
# Permanent modifiers (future Guild Mastery / facilities / traits).
var rate_multiplier: float = 1.0
var bonus_rate: float = 0.0
# Development-only speed-up; kept apart so it never mixes with real modifiers.
var debug_multiplier: float = 1.0
# Future Tavern drink hook: added to Energy on the next dispatch, then cleared.
var pending_dispatch_energy_bonus: int = 0
var _tick_elapsed: float = 0.0
var _fractional_energy: float = 0.0
# id -> {"value": float, "remaining": float}; remaining <= 0 means permanent.
var _rate_buffs: Dictionary = {}
var _flat_buffs: Dictionary = {}

func setup(energy_owner: Node) -> void:
	hero = energy_owner
	sync_guild_status()
	changed.emit()

func _process(delta: float) -> void:
	_expire_buffs(delta)
	recover(delta)

func can_start() -> bool:
	return hero != null and not recovery_enabled and hero.guild_status in AT_GUILD_STATUSES \
		and hero.current_energy < hero.max_energy

func start() -> bool:
	if not can_start():
		return false
	recovery_enabled = true
	_tick_elapsed = 0.0
	_fractional_energy = 0.0
	hero.guild_status = "RESTING"
	changed.emit()
	return true

func stop() -> void:
	if not recovery_enabled:
		return
	_finish_rest()
	changed.emit()

func recover(delta: float) -> void:
	if not recovery_enabled or hero == null or delta <= 0.0:
		return
	_tick_elapsed += delta
	var ticks: int = floori(_tick_elapsed / tick_seconds)
	if ticks <= 0:
		return
	_tick_elapsed -= ticks * tick_seconds
	_fractional_energy += recovery_rate() * tick_seconds * ticks
	var recovered: int = floori(_fractional_energy)
	_fractional_energy -= recovered
	if recovered > 0:
		hero.current_energy = mini(hero.current_energy + recovered, hero.max_energy)
	# Rest continues past READY only when the threshold is below max (future mastery).
	if hero.current_energy >= hero.max_energy:
		_finish_rest()
		changed.emit()
		ready_reached.emit()
		return
	var crossed: bool = is_ready() and hero.current_energy - recovered < ready_energy()
	changed.emit()
	if crossed:
		ready_reached.emit()

func ready_energy() -> int:
	return ceili(hero.max_energy * ready_threshold) if hero != null else 0

func is_ready() -> bool:
	return hero != null and hero.current_energy >= ready_energy()

func recovery_rate() -> float:
	var flat: float = base_energy_recovery_per_second + bonus_rate
	for buff in _flat_buffs.values():
		flat += buff.value
	var mult: float = rate_multiplier * debug_multiplier
	for buff in _rate_buffs.values():
		mult *= buff.value
	return maxf(flat * mult, 0.0)

# Keeps IDLE_AT_GUILD/READY accurate when Energy changes outside of rest.
func sync_guild_status() -> void:
	if hero == null or hero.guild_status not in AT_GUILD_STATUSES:
		return
	var status: String = "READY" if is_ready() else "IDLE_AT_GUILD"
	if hero.guild_status != status:
		hero.guild_status = status
		changed.emit()

func arrive_at_guild() -> void:
	if hero == null:
		return
	hero.guild_status = "IDLE_AT_GUILD"
	sync_guild_status()
	changed.emit()

func apply_dispatch_bonus() -> void:
	if hero != null and pending_dispatch_energy_bonus > 0:
		hero.current_energy += pending_dispatch_energy_bonus
	pending_dispatch_energy_bonus = 0

func set_ready_threshold(value: float) -> void:
	ready_threshold = clampf(value, 0.01, 1.0)
	sync_guild_status()
	changed.emit()

func debug_set_multiplier(value: float) -> void:
	debug_multiplier = maxf(value, 0.0)
	changed.emit()

# Future hooks: Tavern meals (+20% for 10 min), Faster Recovery, Comfortable Quarters.
func add_rate_buff(id: String, multiplier: float, duration_seconds: float = 0.0) -> void:
	_rate_buffs[id] = {"value": multiplier, "remaining": duration_seconds}
	changed.emit()

func remove_rate_buff(id: String) -> void:
	if _rate_buffs.erase(id):
		changed.emit()

func add_flat_recovery_buff(id: String, per_second: float, duration_seconds: float = 0.0) -> void:
	_flat_buffs[id] = {"value": per_second, "remaining": duration_seconds}
	changed.emit()

func remove_flat_recovery_buff(id: String) -> void:
	if _flat_buffs.erase(id):
		changed.emit()

# Future Emergency Rest hook: instant partial recovery.
func burst_recover(amount: int) -> void:
	if hero == null or amount <= 0:
		return
	var was_ready: bool = is_ready()
	hero.current_energy = mini(hero.current_energy + amount, hero.max_energy)
	if hero.current_energy >= hero.max_energy and recovery_enabled:
		_finish_rest()
	else:
		sync_guild_status()
	changed.emit()
	if is_ready() and not was_ready:
		ready_reached.emit()

func snapshot() -> Dictionary:
	return {
		"guild_status": hero.guild_status if hero != null else "",
		"current_energy": hero.current_energy if hero != null else 0,
		"max_energy": hero.max_energy if hero != null else 0,
		"recovery_rate": recovery_rate(),
		"recovery_enabled": recovery_enabled,
		"ready_threshold": ready_threshold,
		"ready": is_ready(),
		"debug_multiplier": debug_multiplier,
	}

func _finish_rest() -> void:
	recovery_enabled = false
	_tick_elapsed = 0.0
	_fractional_energy = 0.0
	hero.guild_status = "READY" if is_ready() else "IDLE_AT_GUILD"

func _expire_buffs(delta: float) -> void:
	for buffs in [_rate_buffs, _flat_buffs]:
		for id in buffs.keys():
			if buffs[id].remaining > 0.0:
				buffs[id].remaining -= delta
				if buffs[id].remaining <= 0.0:
					buffs.erase(id)
					changed.emit()
