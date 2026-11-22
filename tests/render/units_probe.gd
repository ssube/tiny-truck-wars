extends Node
## Milestone 8's units on a real renderer, for review (reports/render/units-*.png,
## looked at, not compared): tanks trading shells across open ground, a
## gunship's rockets, helicopters' rotor wash over the river, a bucket drop
## and a water tanker spraying a field into mud, a hippy's smoke over a
## column. (Behaviour is tested in test_combat.gd, test_helicopters.gd,
## test_kits.gd and test_specials.gd.)
## ./run-probe.sh res://tests/render/units_probe.tscn

var problems: Array[String] = []
var game: TtwSkirmish

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	game = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	var tile := TtwTerrain.tile_px()
	await _frames(10)
	# Two lines of tanks on the west bank, facing each other.
	var field := Vector2(26, 44) * tile
	for k in 3:
		game.spawn_unit(&"tank", field + Vector2(-70, k * 26 - 26), 0.0, 1)
		game.spawn_unit(&"tank", field + Vector2(70, k * 26 - 26), PI, 2)
	game.spawn_unit(&"nurse", field + Vector2(-100, 0), 0.0, 1)
	var gunship := game.spawn_unit(&"gunship", field + Vector2(-40, -70), 0.0, 1)
	(gunship.get_component(TtwFlight) as TtwFlight).altitude = 26.0
	game.camera.position = field
	game.camera.zoom = Vector2(3, 3)
	await _frames(100)
	await _shot("units-battle")
	await _frames(90)
	await _shot("units-battle-later")
	# Helicopters low over the river, one dipping its bucket.
	var river := Vector2(TtwSkirmishMap.RIVER_X, 30) * tile
	var bucket := game.spawn_unit(&"bucket_heli", river, 0.0, 1)
	(bucket.get_component(TtwFlight) as TtwFlight).altitude = 12.0
	var low := game.spawn_unit(&"gunship", river + Vector2(-50, 30), 0.0, 1)
	(low.get_component(TtwFlight) as TtwFlight).altitude = 10.0
	(low.get_component(TtwFlight) as TtwFlight).cruise_px = 10.0
	game.camera.position = river
	await _frames(150)
	await _shot("units-river")
	# The bucket drops on a field; a water tanker sprays another.
	var dry := Vector2(40, 38) * tile
	var b: TtwBucket = bucket.get_component(TtwBucket)
	b.amount = b.capacity
	TtwKitSystem.drop(bucket, dry)
	var tanker := game.spawn_unit(&"water_tanker", dry + Vector2(-50, 40), 0.0, 1)
	var w: TtwWaterTank = tanker.get_component(TtwWaterTank)
	w.amount = w.capacity
	TtwKitSystem.spray(tanker, dry + Vector2(0, 40))
	game.camera.position = dry + Vector2(-10, 20)
	await _frames(150)
	await _shot("units-water")
	# A hippy smokes a column on the road.
	var road := Vector2(30, 28) * tile
	var hippy := game.spawn_unit(&"hippy", road + Vector2(-60, 0), 0.0, 1)
	for k in 3:
		var truck := game.spawn_unit(&"tanker", road + Vector2(k * 24 - 10, 0), PI, 2)
		(truck.get_component(TtwDrive) as TtwDrive).throttle = 0.6
	TtwSpecialSystem.smoke(game.session, hippy, road)
	game.camera.position = road
	await _frames(120)
	await _shot("units-smoke")
	print("UNITS_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	game.queue_free()
	await get_tree().process_frame
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
