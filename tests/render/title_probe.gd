extends Node
## The title screen on a real renderer, for review (reports/render/title.png).
## ./run-probe.sh res://tests/render/title_probe.tscn

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/render"))
	var title: Node = (load(TtwTitle.TITLE) as PackedScene).instantiate()
	add_child(title)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://reports/render/title.png"))
	print("TITLE_PROBE: ", "PASS" if error == OK else error_string(error))
	title.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if error == OK else 1)
