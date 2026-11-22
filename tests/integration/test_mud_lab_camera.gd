extends GdUnitTestSuite
## The Mud Lab's camera follows the selected vehicle.

var lab: TtwMudLab

func after_test() -> void:
	if lab != null:
		lab.queue_free()
		lab = null

func test_the_camera_follows_the_selected_vehicle() -> void:
	lab = (load("res://tools/mud_lab.tscn") as PackedScene).instantiate()
	add_child(lab)
	await get_tree().process_frame
	var far := lab.camera.position + Vector2(300, 120)
	var truck := lab.spawn(&"truck", far)
	assert_object(lab.selected_vehicle()).is_same(truck)
	var before := lab.camera.position.distance_to(far)
	# Frames, not ticks: the camera eases toward it each frame it draws.
	for k in 120:
		await get_tree().process_frame
	assert_float(lab.camera.position.distance_to(lab.game.session.body_of(truck).position)).is_less(before * 0.1)
