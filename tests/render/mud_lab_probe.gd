extends Node
## Draws the Mud Lab's ground on a real renderer after scripted brush work:
## ruts dug into mud and crossing each other, a berm, loose mud dragged onto
## the road, a wet patch, puddles in ruts, the river and the cliff. Writes
## review pictures to reports/render/mud-lab-*.png (looked at, not compared).
## Checks that every chunk on screen was uploaded and the tiers follow the view.
## ./run-probe.sh res://tests/render/mud_lab_probe.tscn

var problems: Array[String] = []
var lab: TtwMudLab

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	lab = (load("res://tools/mud_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	lab.set_process(false)
	var t := lab.terrain
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var road_y := t.size_px().y * 0.5
	# Two tread lines through the mud field, a second pass crossing them.
	for i in 60:
		var x := 120.0 + i * 4.0
		for side in [-7.0, 7.0]:
			lab.paint(TtwBrushes.Kind.DIG, Vector2(x, road_y - 70 + side), 3.5, 2.6)
			lab.paint(TtwBrushes.Kind.RAISE, Vector2(x, road_y - 70 + side + signf(side) * 5.0), 2.5, 0.9)
			lab.paint(TtwBrushes.Kind.TRACK, Vector2(x, road_y - 70 + side), 3.0, 1.0, 0.0)
	for i in 40:
		var y := road_y - 140.0 + i * 4.0
		for side in [-6.0, 6.0]:
			lab.paint(TtwBrushes.Kind.DIG, Vector2(260 + side, y), 3.5, 2.0)
			lab.paint(TtwBrushes.Kind.TRACK, Vector2(260 + side, y), 3.0, 1.0, PI / 2)
	# Loose mud carried onto the road, thinning out.
	for i in 30:
		lab.paint(TtwBrushes.Kind.LOOSE, Vector2(330 + i * 5.0, road_y + rng.randf_range(-6, 6)), 4.0, 1.2 * (1.0 - i / 30.0))
	# A wet patch, and water standing in the ruts.
	lab.paint(TtwBrushes.Kind.WET, Vector2(200, road_y - 70), 60.0, 1.0)
	lab.paint(TtwBrushes.Kind.WATER, Vector2(160, road_y - 70), 20.0, -2.0)
	lab.camera.position = Vector2(260, road_y - 40)
	lab.camera.zoom = Vector2(3, 3)
	await _shot("mud-lab-ruts")
	var center_chunk := lab.view.chunk_at(t.cell_of(lab.camera.position) / TtwTerrain.CHUNK_CELLS)
	if center_chunk == null or center_chunk.tier != TtwTerrainView.Tier.FULL:
		problems.append("the chunk under the camera is not drawn at full detail")
	if t.dirty_chunk_count() > 0 and _visible_dirty() > 0:
		problems.append("chunks on screen were left dirty")
	# The river and the rock shelf.
	lab.camera.position = Vector2(t.size_px().x * 0.8, t.size_px().y * 0.75)
	await _shot("mud-lab-river")
	# Zoomed out: everything is drawn cheaply.
	lab.camera.position = t.size_px() * 0.5
	lab.camera.zoom = Vector2(0.75, 0.75)
	await _shot("mud-lab-overview")
	for chunk in lab.view.get_children():
		if chunk.visible and chunk.tier != TtwTerrainView.Tier.FAR:
			problems.append("%s is not at the far tier when zoomed out" % chunk.name)
			break
	print("MUD_LAB_PROBE: ", "PASS" if problems.is_empty() else str(problems))
	lab.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)

func _visible_dirty() -> int:
	var count := 0
	for chunk in lab.view.get_children():
		if chunk.visible and lab.terrain.is_chunk_dirty(chunk.coord):
			count += 1
	return count

func _shot(name: String) -> void:
	lab.camera.force_update_scroll()
	await get_tree().process_frame
	lab.view.refresh(0.0)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://reports/render/%s.png" % name)
	var error := get_viewport().get_texture().get_image().save_png(path)
	if error != OK:
		problems.append("%s: %s" % [name, error_string(error)])
