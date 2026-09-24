# Run: godot --headless --path . --script res://tests/milestone3_check.gd
extends SceneTree

var failures: int = 0
var main: Node2D
var hits: Array[int] = []


func _initialize() -> void:
	run_check.call_deferred()


func check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		printerr("FAIL: " + description)


func wait_for(predicate: Callable, seconds: float = 10.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			check(false, "Timed out waiting for combat")
			quit(1)
			return false
		await process_frame
	return true


func find_text(message: String) -> Node2D:
	for child in main.get_children():
		if child.has_node("Label") and child.get_node("Label").text == message:
			return child
	return null


func on_attack(target: Node2D, damage: int) -> void:
	hits.append(damage)
	check(main.arthur.position.distance_to(target.position) <= 130.01, "Attack remains in melee range")


func run_check() -> void:
	# Test progression independently of combat, animations, and reward UI.
	var stats = load("res://scripts/hero_progression.gd").new()
	check(stats.level == 1 and stats.xp == 0 and stats.xp_required == 30, "Initial level and XP")
	check(stats.damage == 10 and stats.current_hp == 100 and stats.max_hp == 100, "Initial damage and HP")
	stats.add_xp(-10)
	stats.add_xp(0)
	check(stats.xp == 0, "Nonpositive XP is ignored")
	stats.current_hp = 1
	stats.add_xp(25)
	check(stats.level == 1 and stats.xp == 25, "XP below the threshold does not level up")
	stats.add_xp(15)
	check(stats.level == 2 and stats.xp == 10 and stats.xp_required == 45, "25 XP plus 15 XP reaches Level 2 with 10 XP left")
	check(stats.damage == 12 and stats.current_hp == 110 and stats.max_hp == 110, "Level-up raises stats and fully heals")
	stats.current_hp = 2
	stats.add_xp(110)
	check(stats.level == 4 and stats.xp == 10 and stats.xp_required == 90, "Large reward handles multiple level-ups and 30/45/65/90 curve")
	check(stats.damage == 16 and stats.max_hp == 130 and stats.current_hp == 130, "Each level grants exactly +2 damage and +10 HP")
	stats.free()

	main = load("res://scenes/main.tscn").instantiate()
	main.debug_combat_mode = true # Explicit legacy combat regression mode.
	root.add_child(main)
	main.arthur.attacked.connect(on_attack)
	var hero_stats = main.arthur.progression
	check(main.xp_label.text == "XP: 0 / 30" and main.xp_bar.value == 0, "XP UI starts at zero")
	check(main.arthur_label.text.contains("Level 1") and main.arthur_label.text.contains("Damage: 10"), "Initial level and damage UI")
	await create_timer(0.5).timeout
	check(main.arthur.state == main.arthur.State.MOVING and main.slime.hp == 30, "Movement and no out-of-range damage preserved")
	if not await wait_for(func(): return main.gold == 10):
		return
	check(hits.size() == 3 and hits == [10, 10, 10], "First Slime dies in three 10-damage hits")
	check(hero_stats.xp == 15 and hero_stats.level == 1, "First Slime grants exactly 15 XP")
	check(main.xp_label.text == "XP: 15 / 30" and main.xp_bar.value == 15, "XP label and half-full bar update")
	check(is_instance_valid(find_text("+10 Gold")), "Gold popup preserved")
	await create_timer(1.7).timeout
	check(main.slime == null and main.gold == 10, "Respawn still waits two seconds with no duplicate reward")
	if not await wait_for(func(): return is_instance_valid(main.slime)):
		return
	await create_timer(0.1).timeout
	check(main.arthur.state == main.arthur.State.MOVING, "Arthur approaches respawned Slime")
	hero_stats.current_hp = 1
	if not await wait_for(func(): return main.gold == 20):
		return
	check(hero_stats.level == 2 and hero_stats.xp == 0 and hero_stats.xp_required == 45, "Second kill reaches Level 2")
	check(hits.size() == 6 and hits[5] == 10, "Killing blow retains its pre-level damage")
	check(hero_stats.damage == 12 and hero_stats.max_hp == 110 and hero_stats.current_hp == 110, "Combat level-up increases stats and fully heals")
	check(main.arthur_label.text.contains("Level 2") and main.arthur_label.text.contains("Damage: 12") and main.arthur_label.text.contains("110 / 110"), "Stat display updates")
	check(main.xp_label.text == "XP: 0 / 45" and main.xp_bar.max_value == 45 and main.xp_bar.value == 0, "XP UI resets to new requirement")
	var popup = find_text("LEVEL UP!")
	check(is_instance_valid(popup) and is_equal_approx(popup.position.x, main.arthur.position.x), "Level-up popup appears above Arthur")
	var popup_ref = weakref(popup)
	await create_timer(0.9).timeout
	check(popup_ref.get_ref() == null, "Level-up popup removes itself")
	if not await wait_for(func(): return hits.size() == 7):
		return
	check(hits[6] == 12 and main.slime.hp == 18, "Next attack uses increased damage")
	check(is_instance_valid(find_text("-12")), "Damage popup reflects increased damage")
	for kill_count in range(3, 6):
		if not await wait_for(func(): return main.gold == kill_count * 10):
			return
		if kill_count < 5:
			check(hero_stats.xp == (kill_count - 2) * 15, "Each later Slime awards exactly 15 XP")
	check(hero_stats.level == 3 and hero_stats.xp == 0 and hero_stats.xp_required == 65, "Fifth kill reaches Level 3 with 65 XP required next")
	check(hero_stats.damage == 14 and hero_stats.max_hp == 120 and hero_stats.current_hp == 120, "Level 3 stats correct")
	check(main.gold_label.text == "Gold: 50" and hits.size() == 15, "Gold and Slime deaths remain correct over five cycles")
	print("XP milestone check finished: %d failures" % failures)
	quit(1 if failures > 0 else 0)