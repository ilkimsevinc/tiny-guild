class_name GoldWallet
extends Node

signal changed

var balance: int = 0:
	set(value):
		balance = maxi(value, 0)
		changed.emit()


func add_gold(amount: int) -> void:
	if amount > 0:
		balance += amount


func try_spend(amount: int) -> bool:
	if amount < 0 or balance < amount:
		return false
	balance -= amount
	return true