extends Node
## What the ground costs at scale: 100 units of every kind, two sides, driving
## and flying over a 128×128-tile map with its river, firing at each other,
## craters going off (tests/support/perf_scene.gd). Prints each system's cost per tick
## (GECS's own timers), the frame's process and physics time, and how many
## chunks were uploaded per frame; writes them to reports/render/perf.txt.
## A measurement, not a check: it fails only if the run does.
## ./run-probe.sh res://tests/render/perf_probe.tscn
## KIT_PERF_WINTER=1 lays snow over the map and spills oil, so the snow and
## oil presses are measured too.

const TICKS := 300
const PerfScene := preload("res://tests/support/perf_scene.gd")

var lines: PackedStringArray = []

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	var winter := OS.get_environment("KIT_PERF_WINTER") == "1"
	var scene := PerfScene.new(self, winter)
	var game := scene.game
	game.camera.make_current()
	game.camera.zoom = Vector2(3, 3)
	var size := scene.size
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
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
	# Wall time, for frames per second: a measurement, not a game input.
	var wall_start := Time.get_ticks_usec()
	while game.session.tick - start_tick < TICKS:
		await get_tree().process_frame
		frames += 1
		process += Performance.get_monitor(Performance.TIME_PROCESS)
		physics += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		uploads += game.view.uploads_last_refresh()
		game.camera.position = game.session.body_of(game.session.resolve("unit:tank:1")).position
	var ticks := game.session.tick - start_tick
	var wall := (Time.get_ticks_usec() - wall_start) / 1.0e6
	_line("== %d units on %s tiles%s, %d ticks, %d frames" % [PerfScene.VEHICLES, str(game.terrain.size_tiles), ", winter" if winter else "", ticks, frames])
	var total := 0.0
	for row in systems:
		var system: System = row[1]
		var per_tick: float = system._metric_avg_ms * 1000.0 * system._metric_sample_count / ticks
		total += per_tick
		_line("   %-10s %8.1f us per tick" % [row[0], per_tick])
	_line("   %-10s %8.1f us per tick (%.1f%% of a 60 Hz tick)" % ["total", total, total / 166.67])
	_line("   %.1f frames per second, %.1f ticks per second (%.0f%% of game speed), over %.1f s on %s" % [
		frames / wall, ticks / wall, ticks / wall / Engine.physics_ticks_per_second * 100.0, wall, RenderingServer.get_video_adapter_name()])
	_line("   path grid: built in %.1f ms, a route across the map in %.2f ms" % [build_us / 1000.0, find_us / 1000.0])
	_line("   frame: process %.2f ms, physics %.2f ms; %.2f chunk uploads per frame; settling queue %d cells; %d bits, %d puff particles" % [
		process / frames * 1000.0, physics / frames * 1000.0, float(uploads) / frames, game.terrain.settling.size(), game.fx.debris.count(), game.fx.puffs.live()])
	var file := FileAccess.open(ProjectSettings.globalize_path("res://reports/render/perf.txt"), FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("PERF_PROBE: PASS")
	scene.free_game()
	await get_tree().process_frame
	get_tree().quit(0)

func _line(text: String) -> void:
	lines.append(text)
	print(text)
