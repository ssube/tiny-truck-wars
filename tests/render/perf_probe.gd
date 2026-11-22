extends Node
## What the ground costs at scale: 100 units of every kind, two sides, driving
## and flying over a 128×128-tile map with its river, firing at each other,
## craters going off. Prints each system's cost per tick
## (GECS's own timers), the frame's process and physics time, and how many
## chunks were uploaded per frame; writes them to reports/render/perf.txt.
## A measurement, not a check: it fails only if the run does.
## ./run-probe.sh res://tests/render/perf_probe.tscn

const TICKS := 300
const VEHICLES := 100
const KINDS := [&"tank", &"wrecker", &"hippy", &"boss", &"nurse", &"tank", &"gunship", &"tanker", &"engineer", &"water_tanker", &"bucket_heli", &"tank"]

var lines: PackedStringArray = []

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	var game := TtwGame.new()
	add_child(game)
	game.load_ground(TtwMapGen.mud_lab(Vector2i(128, 128)))
	game.camera.make_current()
	game.camera.zoom = Vector2(3, 3)
	var size := game.terrain.size_px()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var drives: Array[TtwDrive] = []
	for k in VEHICLES:
		var at := Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y)
		var unit := game.spawn_unit(KINDS[k % KINDS.size()], at, rng.randf() * TAU, 1 + k % 2)
		var drive: TtwDrive = unit.get_component(TtwDrive)
		if drive != null:
			drive.throttle = 1.0
			drive.steer = rng.randf_range(-0.4, 0.4)
			drives.append(drive)
		if k % 3 == 0 or drive == null:
			# A third drive routes the path grid finds.
			TtwPilotSystem.order(unit, Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y))
	var build_from := Time.get_ticks_usec()
	var grid := TtwPathGrid.new(game.terrain)
	var build_us := Time.get_ticks_usec() - build_from
	var find_from := Time.get_ticks_usec()
	for k in 20:
		grid.find(Vector2(rng.randf() * size.x, rng.randf() * size.y), Vector2(rng.randf() * size.x, rng.randf() * size.y))
	var find_us := (Time.get_ticks_usec() - find_from) / 20.0
	var systems: Array = []
	for key in [&"weather", &"pilot", &"water", &"flight", &"winch", &"drive", &"tow", &"separation", &"obstacles", &"tracks", &"settle", &"fire", &"oil", &"snow", &"paths", &"depots", &"garages", &"specials", &"kits", &"guns", &"ballistics", &"match", &"wakes", &"effects"]:
		var system: System = game.session.system(key)
		system.performance_monitor = true
		systems.append([key, system])
	var process := 0.0
	var physics := 0.0
	var uploads := 0
	var frames := 0
	var start_tick := game.session.tick
	while game.session.tick - start_tick < TICKS:
		await get_tree().process_frame
		frames += 1
		process += Performance.get_monitor(Performance.TIME_PROCESS)
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		uploads += game.view.uploads_last_refresh()
		if frames % 30 == 0:
			var at := Vector2(rng.randf() * size.x, rng.randf() * size.y)
			TtwStamps.crater(game.terrain, at, &"rocket")
			game.fx.explode(at, &"rocket")
		game.camera.position = game.session.body_of(game.session.resolve("unit:tank:1")).position
	var ticks := game.session.tick - start_tick
	_line("== %d units on %s tiles, %d ticks, %d frames" % [VEHICLES, str(game.terrain.size_tiles), ticks, frames])
	var total := 0.0
	for row in systems:
		var system: System = row[1]
		var per_tick: float = system._metric_avg_ms * 1000.0 * system._metric_sample_count / ticks
		total += per_tick
		_line("   %-10s %8.1f us per tick" % [row[0], per_tick])
	_line("   %-10s %8.1f us per tick (%.1f%% of a 60 Hz tick)" % ["total", total, total / 166.67])
	_line("   path grid: built in %.1f ms, a route across the map in %.2f ms" % [build_us / 1000.0, find_us / 1000.0])
	_line("   frame: process %.2f ms, physics %.2f ms; %.2f chunk uploads per frame; settling queue %d cells; %d bits, %d puff particles" % [
		process / frames * 1000.0, physics / frames * 1000.0, float(uploads) / frames, game.terrain.settling.size(), game.fx.debris.count(), game.fx.puffs.live()])
	var file := FileAccess.open(ProjectSettings.globalize_path("res://reports/render/perf.txt"), FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("PERF_PROBE: PASS")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _line(text: String) -> void:
	lines.append(text)
	print(text)
