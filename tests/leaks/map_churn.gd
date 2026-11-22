extends SceneTree
## Leak gate driver for run-leak-check.sh: the real game path, with none of the
## test runner's exit-time static/script release. Each round starts a game on
## a map, plays a simulated second (LEAK_DWELL_SECONDS) and frees it; the
## wrapper then rejects any engine "leaked at exit" report and any growth in
## the counters across rounds after warmup.
##
## Game classes are loaded at runtime, never named: a -s script compiles before
## autoloads (ECS) register, so naming a game class here fails to compile.
##
## Output: one `LEAK_SAMPLE {json}` line per round, then `LEAK_DONE {json}`.

const DEFAULT_DWELL_SECONDS := 1.0

const CHURN_SAVE := "user://saves/churn.ttwsave"

func _initialize() -> void:
	_run.call_deferred()

static func sample(label: String, session: Node) -> Dictionary:
	var row := {
		"label": label,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		row["tweens"] = tree.get_processed_tweens().size()
	if session != null and is_instance_valid(session.get("world")):
		row["archetypes"] = session.world.archetypes.size()
		row["entities"] = session.world.entities.size()
	return row

func _fail(message: String) -> void:
	printerr("LEAK_DRIVER_ERROR " + message)
	quit(1)

func _run() -> void:
	var rounds := int(OS.get_environment("LEAK_ROUNDS")) if OS.has_environment("LEAK_ROUNDS") else 6
	var dwell := float(OS.get_environment("LEAK_DWELL_SECONDS")) if OS.has_environment("LEAK_DWELL_SECONDS") else DEFAULT_DWELL_SECONDS
	var maps: Array = []
	if not OS.get_environment("LEAK_MAPS").is_empty():
		maps = Array(OS.get_environment("LEAK_MAPS").split(",", false))
	var simulation: GDScript = load("res://tests/support/simulation.gd")
	var packed := load("res://main.tscn") as PackedScene
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CHURN_SAVE))
	for round in rounds:
		var game: Node = packed.instantiate()
		if not maps.is_empty():
			game.set("map_name", StringName(maps[round % maps.size()]))
		# The first round starts fresh and is saved; every later one loads that.
		if round > 0 and FileAccess.file_exists(CHURN_SAVE):
			game.set("load_path", CHURN_SAVE)
		root.add_child(game)
		# Vehicles driving (pressing ruts, burning fuel), one into the river.
		if game.has_method("spawn_unit"):
			var size: Vector2 = game.terrain.size_px()
			var kinds: Array = [&"tank", &"truck", &"hippy", &"boss", &"nurse"]
			for k in kinds.size():
				var unit = game.spawn_unit(kinds[k], Vector2(size.x * (0.15 + 0.12 * k), size.y * 0.3), 0.0)
				var drive = unit.get_component(load("res://game/components/drive.gd"))
				drive.set("throttle", 1.0)
				drive.set("steer", 0.2 * (k - 2))
			# The other side's tanks and a gunship in range: shells and rockets
			# fly, units are wrecked; a hippy's smoke and a water drop.
			var enemy = game.spawn_unit(&"tank", Vector2(size.x * 0.3, size.y * 0.4), PI, 2)
			game.spawn_unit(&"gunship", Vector2(size.x * 0.4, size.y * 0.25), PI, 2)
			var hippy = game.session.view([load("res://game/components/smoke_launcher.gd")])
			if not hippy.is_empty():
				load("res://game/systems/specials.gd").smoke(game.session, hippy[0], Vector2(size.x * 0.3, size.y * 0.35))
			var bucket = game.spawn_unit(&"bucket_heli", Vector2(size.x * 0.5, size.y * 0.5), 0.0)
			bucket.get_component(load("res://game/components/bucket.gd")).set("amount", 4.0)
			load("res://game/systems/kits.gd").drop(bucket, Vector2(size.x * 0.52, size.y * 0.5))
			load("res://game/systems/guns.gd").attack(game.session, enemy, game.session.view([load("res://game/components/unit.gd")])[0])
			# A depot going up (its chain, fire, rubble) and garages building.
			var session = game.session
			var depots: Array = session.view([load("res://game/components/depot.gd")])
			if not depots.is_empty():
				load("res://game/world/damage.gd").hurt(session, depots[0], 1.0e6, Vector2.ZERO)
			for garage in session.view([load("res://game/components/garage.gd")]):
				load("res://game/systems/garages.gd").enqueue(garage, &"wrecker")
		var ticks := maxi(1, roundi(dwell * Engine.physics_ticks_per_second))
		var advanced: Dictionary = await simulation.physics_ticks(self, ticks, dwell + 1.0)
		if not advanced.success:
			_fail("dwell did not complete: " + str(advanced.reason))
			return
		if round == 0 and game.has_method("quick_save"):
			load("res://game/rts/save.gd").save(game, CHURN_SAVE)
		print("LEAK_SAMPLE " + JSON.stringify(sample("round%d" % round, game.session)))
		game.queue_free()
		await process_frame
	print("LEAK_DONE " + JSON.stringify(sample("after_free", null)))
	quit(0)
