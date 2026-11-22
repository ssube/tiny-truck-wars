extends Node
## Where a frame's time goes, on a real renderer, scene by scene: the
## simulation's ticks, the scripts' _process, the canvas _draw callbacks, the
## renderer (its CPU side and what the GPU reports), and what is left.
## A measurement for review (reports/render/fps.txt), not a check: it fails
## only if the run does. Wall time is read to measure, never to play.
##   ./run-probe.sh res://tests/render/fps_probe.tscn             (llvmpipe)
##   DISPLAY=:0 godot --path . --audio-driver Dummy --resolution 1280x720 \
##       --disable-vsync res://tests/render/fps_probe.tscn        (the GPU)
## Environment:
## Each scene is seen at the zoom a game starts at in that window (TtwZoom:
## 3 at 1280×720, 5 at 1920×1080).
##   KIT_FPS_SCENES   stress,skirmish,idle (default: all three)
##     stress    the perf probe's scene: 100 units on 128×128 tiles
##     skirmish  main.tscn on the river map, the computer playing both sides
##     idle      the same map with nobody playing: nothing moves
##   KIT_FPS_WARM     ticks played before measuring (default 120)
##   KIT_FPS_SECONDS  seconds measured per scene (default 3)
##   KIT_FPS_SAVE     a save of the skirmish after its warm-up: written if it
##     is not there (play the minute once, headless on fixed ticks:
##     godot --headless --fixed-fps 60 ... with KIT_FPS_SECONDS=0), loaded
##     if it is, so a later run starts from the same minute of play.

const KINDS := [&"tank", &"wrecker", &"hippy", &"boss", &"nurse", &"tank", &"gunship", &"tanker", &"engineer", &"water_tanker", &"bucket_heli", &"tank"]
const VEHICLES := 100

## Runs last in each tick and each frame, to mark where scripts end.
class Last extends Node:
	signal process_done
	func _init() -> void:
		process_priority = 1 << 20
	func _process(_delta: float) -> void:
		process_done.emit()

enum { REST, TICK, PROCESS, DRAW_CALLBACKS, RENDER }
const PHASES := ["rest (events, swap wait)", "ticks (systems, bodies, physics)", "_process scripts", "_draw callbacks", "renderer (submit and swap)"]

var lines: PackedStringArray = []
var spent := PackedFloat64Array([0, 0, 0, 0, 0])
var phase := REST
var mark := 0
var measuring := false
var ticks := 0
var frames := 0
var render_cpu := 0.0
## GPU ms per viewport measured: the window, the water's detail, the terrain's buffer.
var render_gpu := PackedFloat64Array([0, 0, 0])
var viewports: Array[RID] = []
var refresh_us := 0
var uploads := 0
var layers := 0
var view: TtwTerrainView

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _enter(next: int) -> void:
	var now := Time.get_ticks_usec()
	if measuring:
		spent[phase] += now - mark
	phase = next
	mark = now

func _on_tick() -> void:
	_enter(TICK)
	if measuring:
		ticks += 1

func _on_frame() -> void:
	_enter(PROCESS)
	if measuring:
		frames += 1
		render_cpu += RenderingServer.get_frame_setup_time_cpu()
		for i in viewports.size():
			render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(viewports[i])
			render_gpu[i] += RenderingServer.viewport_get_measured_render_time_gpu(viewports[i])
	# The terrain view's refresh, timed on its own (it is part of _process).
	if view != null and is_instance_valid(view):
		var from := Time.get_ticks_usec()
		view.refresh(get_process_delta_time())
		if measuring:
			refresh_us += Time.get_ticks_usec() - from
			uploads += view.uploads_last_refresh()
			layers += view.call("layers_last_refresh") if view.has_method("layers_last_refresh") else view.uploads_last_refresh() * TtwTerrain.LAYER_COUNT

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	var last := Last.new()
	add_child(last)
	get_tree().physics_frame.connect(_on_tick)
	get_tree().process_frame.connect(_on_frame)
	last.process_done.connect(_enter.bind(DRAW_CALLBACKS))
	RenderingServer.frame_pre_draw.connect(_enter.bind(RENDER))
	RenderingServer.frame_post_draw.connect(_enter.bind(REST))
	var scenes := (OS.get_environment("KIT_FPS_SCENES") if OS.has_environment("KIT_FPS_SCENES") else "stress,skirmish,idle").split(",")
	var warm := int(OS.get_environment("KIT_FPS_WARM")) if OS.has_environment("KIT_FPS_WARM") else 120
	var seconds := float(OS.get_environment("KIT_FPS_SECONDS")) if OS.has_environment("KIT_FPS_SECONDS") else 3.0
	_line("== frames on %s, vsync %s, %s" % [RenderingServer.get_video_adapter_name(), "on" if DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED else "off", str(get_viewport().get_visible_rect().size)])
	for scene in scenes:
		await _measure(scene.strip_edges(), warm, seconds)
	var file := FileAccess.open(ProjectSettings.globalize_path("res://reports/render/fps.txt"), FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	print("FPS_PROBE: PASS")
	get_tree().quit(0)

func _measure(scene: String, warm: int, seconds: float) -> void:
	var game: TtwGame
	var save := OS.get_environment("KIT_FPS_SAVE") if scene == "skirmish" else ""
	var loaded := false
	match scene:
		"stress":
			game = _stress()
		"skirmish", "idle":
			# Not named as a TtwSkirmish here: a probe script that names that class
			# and quits without having made one leaves scripts alive at exit.
			var skirmish: TtwGame = (load("res://main.tscn") as PackedScene).instantiate()
			skirmish.map_name = &"river"
			var sides: Array = skirmish.get("ai_teams")
			sides.assign([1, 2] if scene == "skirmish" else [])
			if not save.is_empty() and FileAccess.file_exists(save):
				skirmish.load_path = save
				loaded = true
			add_child(skirmish)
			game = skirmish
		_:
			_line("== %s: no such scene" % scene)
			return
	view = game.view
	view.set_process(false)
	viewports = [get_viewport().get_viewport_rid(), game.water_fx.viewport.get_viewport_rid()]
	if view.get("buffer") != null:
		viewports.append((view.get("buffer") as SubViewport).get_viewport_rid())
	for rid in viewports:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	var follow: Entity = game.session.resolve("unit:tank:1") if scene == "stress" else null
	var start := game.session.tick
	var until := start + (0 if loaded else warm)
	while game.session.tick < until:
		await get_tree().process_frame
		_follow(game, follow)
	if not save.is_empty() and not loaded:
		var error := TtwSave.save(game, save)
		_line("   saved after %d ticks to %s %s" % [game.session.tick, save, error])
	var systems: Dictionary = game.session._systems
	for key in systems:
		(systems[key] as System).performance_monitor = true
		(systems[key] as System).reset_performance_metrics()
	spent.fill(0.0)
	ticks = 0
	frames = 0
	render_cpu = 0.0
	render_gpu.fill(0.0)
	refresh_us = 0
	uploads = 0
	layers = 0
	var draws := 0
	var objects := 0
	var from := Time.get_ticks_usec()
	var deadline := from + int(seconds * 1.0e6)
	if seconds > 0.0:
		# Start on a frame's edge.
		await get_tree().process_frame
		from = Time.get_ticks_usec()
		deadline = from + int(seconds * 1.0e6)
		mark = from
		measuring = true
		while Time.get_ticks_usec() < deadline:
			await get_tree().process_frame
			_follow(game, follow)
			draws += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
			objects += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		measuring = false
	var wall := (Time.get_ticks_usec() - from) / 1.0e6
	if frames > 0:
		var shown := 0
		# (Asked by name where an older checkout, measured with this same probe
		# for a before-and-after, does not have the method.)
		var chunks: Array = view.call("chunks") if view.has_method("chunks") else view.get_children()
		for chunk in chunks:
			if chunk.visible:
				shown += 1
		_line("== %s: %d units, tick %d%s, zoom %.0f" % [scene, game.session.view([TtwUnit]).size(), game.session.tick, " (from the save)" if loaded else "", game.camera.zoom.x])
		_line("   %.1f frames per second (%.2f ms a frame), %.2f ticks a frame, %.0f%% of game speed, over %.1f s" % [
			frames / wall, wall / frames * 1000.0, float(ticks) / frames, ticks / wall / Engine.physics_ticks_per_second * 100.0, wall])
		for i in [TICK, PROCESS, DRAW_CALLBACKS, RENDER, REST]:
			var extra := ""
			if i == TICK and ticks > 0:
				extra = " (%.2f ms a tick)" % (spent[i] / ticks / 1000.0)
			elif i == PROCESS:
				extra = " (terrain refresh %.2f ms: %.2f chunks, %.1f layer textures uploaded)" % [refresh_us / 1000.0 / frames, float(uploads) / frames, float(layers) / frames]
			_line("   %6.2f ms  %4.1f%%  %s%s" % [spent[i] / frames / 1000.0, spent[i] / (wall * 1.0e6) * 100.0, PHASES[i], extra])
		_line("   the renderer's own clocks: cpu %.2f ms, gpu %.2f ms a frame (window %.2f, water detail %.2f, terrain buffer %.2f); %d draw calls, %d objects; %d of %d chunks shown" % [
			render_cpu / frames, (render_gpu[0] + render_gpu[1] + render_gpu[2]) / frames, render_gpu[0] / frames, render_gpu[1] / frames, render_gpu[2] / frames,
			draws / frames, objects / frames, shown, chunks.size()])
		if ticks > 0:
			var rows: Array = []
			var total := 0.0
			for key in systems:
				var system: System = systems[key]
				var per_tick: float = system._metric_avg_ms * 1000.0 * system._metric_sample_count / ticks
				total += per_tick
				rows.append([per_tick, key])
			rows.sort_custom(func(a, b): return a[0] > b[0])
			var text := PackedStringArray()
			for row in rows.slice(0, 10):
				text.append("%s %.0f" % [row[1], row[0]])
			_line("   systems %.0f us a tick of %.0f (the rest: bodies, physics): %s" % [total, spent[TICK] / ticks, ", ".join(text)])
	view = null
	viewports.clear()
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _follow(game: TtwGame, entity: Entity) -> void:
	if entity == null:
		return
	var body := game.session.body_of(entity)
	if body != null:
		game.camera.position = body.position

## The perf probe's scene.
func _stress() -> TtwGame:
	var game := TtwGame.new()
	add_child(game)
	game.load_ground(TtwMapGen.mud_lab(Vector2i(128, 128)))
	game.camera.make_current()
	var size := game.terrain.size_px()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for k in VEHICLES:
		var at := Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y)
		var unit := game.spawn_unit(KINDS[k % KINDS.size()], at, rng.randf() * TAU, 1 + k % 2)
		var drive: TtwDrive = unit.get_component(TtwDrive)
		if drive != null:
			drive.throttle = 1.0
			drive.steer = rng.randf_range(-0.4, 0.4)
		if k % 3 == 0 or drive == null:
			TtwPilotSystem.order(unit, Vector2(rng.randf_range(0.05, 0.95) * size.x, rng.randf_range(0.05, 0.95) * size.y))
	return game

func _line(text: String) -> void:
	lines.append(text)
	print(text)
