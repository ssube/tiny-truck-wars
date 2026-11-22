extends Node
## The skirmish on a real renderer, for review (reports/render/skirmish-*.png,
## looked at, not compared): the west base with its units selected and sent
## off along their routes, a helipad being placed, a stuck tank winched out of
## the mud at the ford, and a cluster of depots going up one after another.
## (Behaviour is tested in test_skirmish.gd, test_depots.gd, test_recovery.gd.)
## ./run-probe.sh res://tests/render/skirmish_probe.tscn

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
	game = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	var tile := TtwTerrain.tile_px()
	var c := game.commander
	await _frames(10)
	game.camera.position = Vector2(12, 28) * tile
	await _shot("skirmish-base")
	c.select_rect(Rect2(Vector2.ZERO, game.terrain.size_px()))
	c.order_at(Vector2(30, 20) * tile)
	await _frames(90)
	await _shot("skirmish-orders")
	# A helipad being placed beside the depots (the ghost and its reach).
	c.begin_placing(&"helipad")
	var site := Vector2(14, 33) * tile
	get_viewport().warp_mouse((site - game.camera.position) * game.camera.zoom + get_viewport().get_visible_rect().size * 0.5)
	await _frames(2)
	c.queue_redraw()
	await _shot("skirmish-placing")
	c.place(site)
	# A tank stuck in the ford's mud; the truck winches it out.
	var ford := Vector2(TtwSkirmishMap.RIVER_X - 7, TtwSkirmishMap.FORDS[0]) * tile
	var tank: Entity = game.session.view([TtwVehicle, TtwTeam]).filter(func(e): return TtwTeam.of(e) == 1 and (e.get_component(TtwVehicle) as TtwVehicle).kind == &"tank")[0]
	var truck: Entity = game.session.view([TtwWinch])[0]
	for e in [tank, truck]:
		TtwPilotSystem.stop(e)
	TtwBrushes.paint(game.terrain, TtwBrushes.Kind.WET, ford, 20.0, 1.0)
	TtwBrushes.paint(game.terrain, TtwBrushes.Kind.DIG, ford, 10.0, 5.0)
	game.terrain.set_material(game.terrain.tile_of(ford), TtwMaterials.MUD)
	game.session.body_of(tank).position = ford
	game.session.body_of(truck).position = ford + Vector2(-60, 0)
	(tank.get_component(TtwDrive) as TtwDrive).traction = 2.0
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _frames(30)
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 0.0
	TtwWinchSystem.winch(game.session, truck, tank)
	game.camera.position = ford + Vector2(-30, 0)
	await _frames(60)
	await _shot("skirmish-winch")
	# Three depots in a row: the first is destroyed and the rest follow.
	var east := Vector2(70, 46) * tile
	var depots: Array[Entity] = []
	for k in 3:
		depots.append(game.spawn_structure(&"depot", east + Vector2(k * 44, 0), 2))
		var d: TtwDepot = depots[k].get_component(TtwDepot)
		d.stock = d.capacity
	await _frames(5)
	game.camera.position = east + Vector2(44, -10)
	game.camera.zoom = Vector2(2, 2)
	TtwDamage.hurt(game.session, depots[0], 1.0e6, east - Vector2(30, 0))
	await _frames(TtwDepotSystem.CHAIN_TICKS + 8)
	await _shot("skirmish-chain-1")
	await _frames(TtwDepotSystem.CHAIN_TICKS * 2)
	await _shot("skirmish-chain-3")
	await _frames(120)
	await _shot("skirmish-chain-after")
	print("SKIRMISH_PROBE: ", "PASS" if problems.is_empty() else str(problems))
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
