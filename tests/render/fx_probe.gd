extends Node
## Effects on a real renderer, for review (reports/render/fx-*.png, looked at,
## not compared): a tank slipping in mud throwing clods, a car raising dust,
## a burning wreck with its smoke lit from below, the hippy's smoke screen, a
## blast on the hill whose bits roll downhill, and one in the river whose bits
## drift downstream. Checks the bits did move down the slope and the stream.
## ./run-probe.sh res://tests/render/fx_probe.tscn

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
	var size := t.size_px()
	var fx := lab.game.fx
	# A tank floored in deep mud, a car on the sand bank.
	var mud := _muddiest(t)
	TtwBrushes.paint(t, TtwBrushes.Kind.WET, mud, 30.0, 1.0)
	var tank := lab.spawn(&"tank", mud, 0.3)
	var tank_drive: TtwDrive = tank.get_component(TtwDrive)
	tank_drive.throttle = 1.0
	tank_drive.traction = 2.6 # spinning in place: the mud is too much for it
	var car := lab.spawn(&"hippy", Vector2(size.x * 0.78 - 56, size.y * 0.15), PI / 2)
	(car.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _frames(50)
	lab.camera.position = mud
	lab.camera.zoom = Vector2(4, 4)
	await _shot("fx-clods")
	lab.camera.position = lab.game.session.body_of(car).position
	await _shot("fx-dust")
	# A wreck burning, and a smoke screen beside it.
	var wreck := mud + Vector2(90, 40)
	TtwStamps.crater(t, wreck, &"vehicle")
	fx.explode(wreck, &"vehicle")
	fx.smoke_screen(wreck + Vector2(70, 0))
	await _frames(70)
	lab.camera.position = wreck + Vector2(35, -10)
	lab.camera.zoom = Vector2(3, 3)
	await _shot("fx-fire")
	# A blast on the hill's flank: its bits roll down; one in the river drifts.
	var hill := Vector2(14, 8) * TtwTerrain.tile_px()
	var flank := hill + Vector2(48, 0)
	var river := Vector2(size.x * 0.78, size.y * 0.3)
	fx.debris.throw(TtwDebris.Kind.DEBRIS, Vector3(flank.x, flank.y, 1.0), Vector2.RIGHT, 1.0, TAU, 20.0, 12)
	fx.explode(river, &"rocket")
	await _frames(90)
	lab.camera.position = (hill + flank) * 0.5 + Vector2(20, 0)
	await _shot("fx-downhill")
	lab.camera.position = river + Vector2(0, 40)
	await _shot("fx-river")
	print("FX_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	lab.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)

## The middle of a patch of mud near the left of the map.
func _muddiest(t: TtwTerrain) -> Vector2:
	for y in range(t.size_tiles.y - 8, 8, -1):
		for x in range(8, t.size_tiles.x / 2):
			var all_mud := true
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if t.material_at_tile(Vector2i(x + dx, y + dy)) != TtwMaterials.MUD:
						all_mud = false
			if all_mud:
				return (Vector2(x, y) + Vector2(0.5, 0.5)) * TtwTerrain.tile_px()
	return t.size_px() * 0.3

func _shot(name: String) -> void:
	lab.camera.force_update_scroll()
	await get_tree().process_frame
	for i in 4:
		lab.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://reports/render/%s.png" % name))
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
