extends Node
## Snow on a real renderer, for review (reports/render/snow-*.png, looked at,
## not compared): a tank and a truck cutting packed tracks with berms through
## fresh snow, a blast clearing it and a fire melting it, and the slush of a
## thaw. (Behaviour is tested in test_snow.gd.)
## ./run-probe.sh res://tests/render/snow_probe.tscn

var problems: Array[String] = []
var lab: TtwMudLab

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
	var session: KitSession = lab.game.session
	var until := session.tick + count * TICKS_PER_FRAME
	for i in count:
		await get_tree().process_frame
	while session.tick < until:
		await get_tree().process_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	lab = (load("res://tools/mud_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	lab.set_process(false)
	lab.winter(true)
	var t := lab.terrain
	var start := Vector2(130, t.size_px().y * 0.5 + 90)
	var tank := lab.spawn(&"tank", start, 0.0)
	var truck := lab.spawn(&"truck", start + Vector2(-10, 40), -0.15)
	for e in [tank, truck]:
		(e.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	(tank.get_component(TtwDrive) as TtwDrive).steer = 0.25
	await _frames(240)
	lab.camera.position = start + Vector2(120, 20)
	lab.camera.zoom = Vector2(3, 3)
	await _shot("snow-tracks")
	var blast := start + Vector2(60, -70)
	lab.blast(blast, &"rocket")
	var ground: TtwGround = lab.game.session.resolve(TtwGame.MAP_ALIAS).get_component(TtwGround)
	var spill := blast + Vector2(90, 0)
	TtwOilSystem.spill(ground, spill, 3.0, 12.0)
	ground.fire.ignite(t.tile_of(spill))
	await _frames(120)
	lab.camera.position = blast + Vector2(45, 10)
	await _shot("snow-blast-fire")
	# Thawing: halfway gone, slushy.
	lab.winter(false)
	t.snow_level = -2.5
	RenderingServer.global_shader_parameter_set(&"ttw_snow", t.snow_level)
	await _frames(10)
	lab.camera.position = start + Vector2(120, 20)
	await _shot("snow-thaw")
	print("SNOW_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	lab.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)

func _shot(name: String) -> void:
	lab.camera.force_update_scroll()
	await get_tree().process_frame
	for i in 6:
		lab.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://reports/render/%s.png" % name))
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
