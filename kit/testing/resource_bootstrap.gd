extends SceneTree

var runner: Node

## Tests never make sound: the run must use the Dummy audio driver
## (run-tests.sh passes --audio-driver Dummy; --headless implies it). Godot
## consumes those flags, so ask the audio server which driver it chose.
static func silent(driver: String = AudioServer.get_driver_name()) -> bool:
	return driver == "Dummy"

func _initialize() -> void:
	if not silent():
		printerr("ERROR: tests must run without audio: pass --audio-driver Dummy (run-tests.sh does).")
		quit(2)
		return
	# Must precede loading any suite or instantiating the CLI runner.
	root.unfocusable = true
	runner = load("res://kit/testing/resource_runner.gd").new()
	root.add_child(runner)

func _finalize() -> void:
	if is_instance_valid(runner):
		queue_delete(runner)
	# Let go of the static caches, or their resources count as leaked at exit.
	var release = load("res://kit/testing/static_release.gd")
	release.release()
	release.unlink_scripts(["res://kit/testing/"] as Array[String])
