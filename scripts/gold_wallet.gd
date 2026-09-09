class_name GoldWallet
extends Node

signal changed

# Account currencies. Keep the existing Gold API for class purchases and rewards.
var _gold: int = 0
var _tokens: int = 0

var balance: int:
	get:
		return _gold
	set(value):
		_gold = maxi(value, 0)
		changed.emit()

var guild_tokens: int:
	get:
		return _tokens
	set(value):
		_tokens = maxi(value, 0)
		changed.emit()


func add_gold(amount: int) -> void:
	if amount > 0:
		balance += amount


func add_guild_tokens(amount: int) -> void:
	if amount > 0:
		guild_tokens += amount


func try_spend(gold_cost: int, token_cost: int = 0) -> bool:
	if gold_cost < 0 or token_cost < 0 or balance < gold_cost or guild_tokens < token_cost:
		return false
	# Validate both currencies first, then notify once with the complete result.
	_gold -= gold_cost
	_tokens -= token_cost
	changed.emit()
	return true