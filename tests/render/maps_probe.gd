extends Node
## Each skirmish map on a real renderer, for review (reports/render/map-*.png,
## looked at, not compared): side 1's base and the middle of the map, after
## a few seconds of its weather. (What each must be is in test_maps.gd.)
## ./run-probe.sh res://tests/render/maps_probe.tscn

var problems: Array[String] = []
var game: TtwSkirmish

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

## Game ticks waited for each frame asked for: about what a frame took on
## the software renderer these pictures were set up on. The wait is counted
## in ticks as well, so a picture shows the same moment of the game however
## fast the machine draws.
const TICKS_PER_FRAME := 4

func _frames(count: int) -> void:
	var session: KitSession = game.session
	var until := session.tick + count * TICKS_PER_FRAME
	for i in count:
		await get_tree().process_frame
	while session.tick < until:
		await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	for map in TtwMaps.MAPS:
		game = (load("res://main.tscn") as PackedScene).instantiate()
		game.map_name = map
		game.ai_teams = []
		add_child(game)
		await _frames(90)
		await _shot("map-%s-base" % map)
		game.camera.position = game.terrain.size_px() * 0.5
		game.camera.zoom = Vector2(2, 2)
		await _frames(10)
		await _shot("map-%s-middle" % map)
		game.queue_free()
		await get_tree().process_frame
	print("MAPS_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	get_tree().quit(0 if problems.is_empty() else 1)

func _shot(name: String) -> void:
	game.camera.force_update_scroll()
	await get_tree().process_frame
	for i in 4:
		game.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://reports/render/%s.png" % name))
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
