class_name MissionRotationConfig
extends Resource

@export var refresh_seconds: float = 300.0
@export var missions: Array[MissionData] = []
@export var spawn_weights: Array[int] = [65, 25, 10]
# Normal expires after 20 minutes too. Elite/Boss are temporarily unlocked.
@export var expiration_seconds: Array[float] = [1200.0, 1200.0, 3600.0]
