extends Node
## The water on a real renderer, for review (reports/render/water-*.png,
## looked at, not compared): the river running between its banks, a truck
## fording it, and water poured over a rutted field filling the ruts.
## ./run-probe.sh res://tests/render/water_probe.tscn

var problems: Array[String] = []
var lab: TtwMudLab

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	lab = (load("res://tools/mud_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	lab.set_process(false)
	var t := lab.terrain
	var size := t.size_px()
	var river_x := size.x * 0.78
	# Ruts across a muddy patch, then water poured over them.
	for i in 50:
		for side in [-7.0, 7.0]:
			lab.paint(TtwBrushes.Kind.DIG, Vector2(150 + i * 4.0, 440 + side), 3.5, 2.4)
			lab.paint(TtwBrushes.Kind.TRACK, Vector2(150 + i * 4.0, 440 + side), 3.0, 1.0, 0.0)
	lab.paint(TtwBrushes.Kind.WATER, Vector2(250, 440), 40.0, -1.0)
	var truck := lab.spawn(&"truck", Vector2(river_x - 70, size.y * 0.3), 0.0)
	(truck.get_component(TtwDrive) as TtwDrive).throttle = 0.6
	await _ticks(180)
	lab.camera.position = Vector2(river_x, size.y * 0.3)
	lab.camera.zoom = Vector2(4, 4)
	await _shot("water-river")
	lab.camera.position = Vector2(250, 440)
	await _shot("water-puddles")
	# A blast in the river, the truck's silt and rain rings, carried downstream.
	lab.blast(Vector2(river_x, size.y * 0.35), &"rocket")
	await _ticks(20)
	lab.camera.position = Vector2(river_x, size.y * 0.35)
	await _shot("water-spray")
	lab.game.water_fx.rain = 1.0
	await _ticks(70)
	lab.camera.position = Vector2(river_x, size.y * 0.42)
	lab.camera.zoom = Vector2(3, 3)
	await _shot("water-silt")
	if t.water_depth_at(Vector2(250, 433)) <= 0.0:
		problems.append("no water stands in the ruts")
	if t.water_depth_at(Vector2(250, 418)) > 0.3:
		problems.append("water stands on the flat beside the ruts")
	var bank := Vector2(river_x - 6.0 * TtwTerrain.tile_px(), size.y * 0.5)
	if t.water_depth_at(bank) > 0.0:
		problems.append("the river spilled over its bank")
	print("WATER_PROBE: ", "PASS" if problems.is_empty() else str(problems))
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
