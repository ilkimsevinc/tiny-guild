class_name RewardCalculator
extends RefCounted


# Multiply all sources before rounding once. Positive .5 values round upward.
static func calculate(base_reward: int, hero_bonus_percent: float, guild_multiplier: float = 1.0) -> int:
	var unrounded: float = base_reward * (100.0 + hero_bonus_percent) / 100.0 * guild_multiplier
	return roundi(unrounded)