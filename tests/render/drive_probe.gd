extends Node
## Drives vehicles over the Mud Lab's ground on a real renderer and keeps
## pictures for review (reports/render/drive-*.png, looked at, not compared):
## a tank sweeping a turn through mud and grass, a truck making repeated passes
## down one line (a trench, grass torn up), a car across the river's shallow
## edge, craters of every size, and the wear, relief and water overlays.
## ./run-probe.sh res://tests/render/drive_probe.tscn

var problems: Array[String] = []
var lab: TtwMudLab

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _ticks(count: int, each: Callable = Callable()) -> void:
	for i in count:
		await get_tree().physics_frame
		if each.is_valid():
			each.call(i)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	lab = (load("res://tools/mud_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	lab.set_process(false)
	var t := lab.terrain
	var road_y := t.size_px().y * 0.5
	var tank := lab.spawn(&"tank", Vector2(130, road_y - 110), 0.0)
	var truck := lab.spawn(&"truck", Vector2(110, road_y + 70), 0.0)
	var car := lab.spawn(&"hippy", Vector2(t.size_px().x * 0.78 - 64, road_y + 140), 0.0)
	var drives: Array[TtwDrive] = []
	for e in [tank, truck, car]:
		drives.append(e.get_component(TtwDrive))
		drives[-1].throttle = 1.0
	drives[1].max_speed_tiles = 6.0
	var truck_body := lab.game.session.body_of(truck)
	lab.camera.position = Vector2(260, road_y - 40)
	lab.camera.zoom = Vector2(2, 2)
	# The tank sweeps a long left turn; the truck shuttles along one line.
	await _ticks(420, func(i: int):
		drives[0].steer = 0.35 if i > 90 else 0.0
		if truck_body.position.x > 360.0 and drives[1].throttle > 0.0:
			drives[1].throttle = -1.0
		elif truck_body.position.x < 120.0 and drives[1].throttle < 0.0:
			drives[1].throttle = 1.0)
	for d in drives:
		d.throttle = 0.0
	await _shot("drive-ruts")
	if t.relief_at(truck_body.position + Vector2(-30, 9)) >= -1.0:
		problems.append("the truck's line has no rut")
	lab.camera.position = Vector2(240, road_y + 70)
	lab.camera.zoom = Vector2(4, 4)
	await _shot("drive-trench")
	var lane_cell := t.cell_of(Vector2(240, road_y + 70 + 9))
	if t.material_at_tile(lane_cell / TtwTerrain.CELLS_PER_TILE) == TtwMaterials.GRASS and t.effective_material(lane_cell) != TtwMaterials.MUD:
		problems.append("the truck's lane through grass was not torn up")
	lab.camera.position = lab.game.session.body_of(car).position
	lab.camera.zoom = Vector2(3, 3)
	await _shot("drive-river")
	# Craters on grass, mud and the road.
	for k in 4:
		TtwStamps.crater(t, Vector2(470 + k * 60, road_y - 20 + (k % 2) * 30), [&"shell", &"rocket", &"vehicle", &"building"][k])
	lab.camera.position = Vector2(560, road_y)
	lab.camera.zoom = Vector2(3, 3)
	await _shot("drive-craters")
	lab.camera.position = Vector2(260, road_y)
	lab.camera.zoom = Vector2(2, 2)
	for overlay in [TtwTerrainView.Overlay.WEAR, TtwTerrainView.Overlay.RELIEF, TtwTerrainView.Overlay.TIERS]:
		lab.view.overlay = overlay
		await _shot("drive-overlay-%s" % TtwTerrainView.Overlay.keys()[overlay].to_lower())
	print("DRIVE_PROBE: ", "PASS" if problems.is_empty() else str(problems))
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
