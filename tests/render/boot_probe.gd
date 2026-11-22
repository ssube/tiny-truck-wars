extends Node
## Starts the game on a real renderer, draws one frame and quits.
## ./run-probe.sh res://tests/render/boot_probe.tscn

func _ready() -> void:
	if not preload("res://kit/testing/resource_bootstrap.gd").silent():
		printerr("ERROR: render probes must run without audio: use ./run-probe.sh.")
		get_tree().quit(2)
		return
	_run.call_deferred()

func _run() -> void:
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	await RenderingServer.frame_post_draw
	var ok: bool = game.session.world != null
	print("BOOT_PROBE: ", "PASS" if ok else "no world")
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if ok else 1)
