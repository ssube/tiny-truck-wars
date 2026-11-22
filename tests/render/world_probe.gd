extends Node
## The world's objects and weather on a real renderer, for review
## (reports/render/world-*.png, looked at, not compared): the grove on the
## hill swaying, a blast felling trees into logs, a house cracked and then
## collapsed into rubble, logs floating off down the river, and rain driven
## by a strong wind. (Behaviour is tested in test_world_objects.gd.)
## ./run-probe.sh res://tests/render/world_probe.tscn

var problems: Array[String] = []
var lab: TtwMudLab

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
	lab = (load("res://tools/mud_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	lab.set_process(false)
	var t := lab.terrain
	var tile := TtwTerrain.tile_px()
	var grove := Vector2(14, 8) * tile
	lab.camera.position = grove + Vector2(0, 10)
	lab.camera.zoom = Vector2(3, 3)
	await _frames(10)
	await _shot("world-grove")
	lab.blast(grove + Vector2(-20, 30), &"vehicle")
	await _frames(70)
	await _shot("world-felled")
	await _frames(180)
	await _shot("world-grove-fire")
	# A house hurt, then brought down.
	var house: Entity = lab.game.session.view([TtwBuilding, KitBody])[0]
	var at := lab.game.session.body_of(house).position
	TtwDamage.hurt(lab.game.session, house, 190.0, at + Vector2(0, 40))
	lab.camera.position = at + Vector2(0, -10)
	await _frames(5)
	await _shot("world-house-damaged")
	TtwDamage.hurt(lab.game.session, house, 1000.0, at + Vector2(0, 40))
	await _frames(60)
	await _shot("world-house-rubble")
	# Logs in the river float away; rain in a gale.
	var river := Vector2(t.size_px().x * 0.78, t.size_px().y * 0.3)
	for k in 3:
		lab.game.spawn_prop(&"log", river + Vector2(0, k * 26), 0.3 * k)
	var weather := lab.game.fx.weather
	weather.rain = 0.7
	weather.wind = Vector2(50, 10)
	await _frames(90)
	lab.camera.position = river + Vector2(0, 60)
	await _shot("world-river-rain")
	# Oil: a puddle on the road, a slick on the river, a spill set alight.
	weather.rain = 0.0
	var ground: TtwGround = lab.game.session.resolve(TtwGame.MAP_ALIAS).get_component(TtwGround)
	var road := Vector2(20 * tile, t.size_px().y * 0.5)
	TtwOilSystem.spill(ground, road, 3.0, 14.0)
	TtwOilSystem.spill(ground, river + Vector2(0, -40), 6.0, 16.0)
	var grass := Vector2(10 * tile, t.size_px().y * 0.5 + 60)
	for k in 5:
		TtwOilSystem.spill(ground, grass + Vector2(k * 12, 0), 1.5, 8.0)
	ground.fire.ignite(t.tile_of(grass))
	await _frames(60)
	lab.camera.position = road
	await _shot("world-oil-road")
	lab.camera.position = river + Vector2(0, 20)
	await _shot("world-oil-river")
	lab.camera.position = grass + Vector2(24, 0)
	await _shot("world-oil-fire")
	print("WORLD_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	lab.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)

func _shot(name: String) -> void:
	lab.camera.force_update_scroll()
	await get_tree().process_frame
	for i in 4:
		lab.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://reports/render/%s.png" % name))
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
