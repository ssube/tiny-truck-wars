extends Node
## The computer playing both sides of a skirmish for a few minutes, for review
## (reports/render/ai-*.png and the lines it prints, looked at, not
## compared): what each side has every simulated minute, its waves, the
## depots it took, and who won if anyone did. (Each behaviour is tested in
## test_ai.gd.) Map from KIT_AI_MAP (river, snowfield, dunes).
## ./run-probe.sh res://tests/render/ai_probe.tscn

## Game minutes to play: a probe runs in real time (Engine.time_scale would
## scale each tick's delta, not run more ticks: a different game).
const MINUTES := 3
## Wall-clock seconds the probe may take (KIT_AI_PROBE_SECONDS): a slow
## machine (software rendering in CI) plays fewer game minutes in it, and
## the probe reports as far as it got. A guard on the probe, not the game.
const WALL_SECONDS := 240

var problems: Array[String] = []
var game: TtwSkirmish
var winner := -1
var finished := false

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	var map := StringName(OS.get_environment("KIT_AI_MAP")) if OS.has_environment("KIT_AI_MAP") else &"river"
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.map_name = map
	game.ai_teams = [1, 2]
	add_child(game)
	(game.session.system(&"match") as TtwMatchSystem).match_over.connect(func(w: int): winner = w)
	var log := func(text: String):
		if not finished: print("AI_PROBE: %5.1f s  %s" % [game.session.tick / 60.0, text])
	(game.session.system(&"depots") as TtwDepotSystem).captured.connect(func(d, team): log.call("side %d takes a depot" % team))
	(game.session.system(&"depots") as TtwDepotSystem).detonated.connect(func(d, at, r): log.call("a depot of side %d goes up" % TtwTeam.of(d)))
	(game.session.system(&"garages") as TtwGarageSystem).produced.connect(func(g, u): log.call("side %d builds a %s" % [TtwTeam.of(u), TtwUnits.kind_of(u)]))
	(game.session.system(&"drive") as TtwDriveSystem).destroyed.connect(func(u): log.call("side %d loses a %s" % [TtwTeam.of(u), TtwUnits.kind_of(u)]))
	game.session.entity_removing.connect(func(e):
		if e.has_component(TtwStructure):
			log.call("side %d loses a %s" % [TtwTeam.of(e), (e.get_component(TtwStructure) as TtwStructure).kind]))
	var per_minute := 60 * Engine.physics_ticks_per_second
	var budget := float(OS.get_environment("KIT_AI_PROBE_SECONDS")) if OS.has_environment("KIT_AI_PROBE_SECONDS") else float(WALL_SECONDS)
	var deadline := Time.get_ticks_msec() + int(budget * 1000.0)
	for minute in MINUTES:
		var until := game.session.tick + per_minute
		while game.session.tick < until and winner < 0 and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		_report(minute + 1)
		await _shot("ai-%s-%d" % [map, minute + 1])
		if winner >= 0 or Time.get_ticks_msec() >= deadline:
			break
	finished = true
	print("AI_PROBE: winner %s after %.1f min" % [str(winner) if winner >= 0 else "none", game.session.tick / 3600.0])
	print("AI_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)

func _report(minute: int) -> void:
	for team in [1, 2]:
		var kinds := {}
		for unit in game.session.view([TtwUnit, TtwTeam]):
			if TtwTeam.of(unit) == team and not unit.has_component(TtwWrecked):
				var kind := TtwUnits.kind_of(unit)
				kinds[kind] = kinds.get(kind, 0) + 1
		var structures := {}
		var fuel := 0.0
		for s in game.session.view([TtwStructure, TtwTeam]):
			if TtwTeam.of(s) == team:
				var kind := (s.get_component(TtwStructure) as TtwStructure).kind
				structures[kind] = structures.get(kind, 0) + 1
				if s.has_component(TtwDepot):
					fuel += (s.get_component(TtwDepot) as TtwDepot).level()
		var ai: TtwAi = game.session.resolve("ai:%d" % team).get_component(TtwAi)
		print("AI_PROBE: min %d side %d: units %s structures %s fuel %d wave %d attacking %s" % [minute, team, kinds, structures, int(fuel), ai.wave, ai.attacking])

func _shot(name: String) -> void:
	# Over the busiest place: the middle of all the units.
	var middle := Vector2.ZERO
	var count := 0
	for unit in game.session.view([TtwUnit, KitBody]):
		middle += game.session.body_of(unit).position
		count += 1
	if count > 0:
		game.camera.position = middle / count
	game.camera.zoom = Vector2(2, 2)
	game.camera.force_update_scroll()
	await get_tree().process_frame
	for i in 4:
		game.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://reports/render/%s.png" % name))
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
