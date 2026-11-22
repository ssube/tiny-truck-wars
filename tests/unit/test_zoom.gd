extends GdUnitTestSuite
## The wheel zooms one step per notch: a high-resolution wheel's parts of a
## notch add up to one step, never one step per event; the ends hold.

func _wheel(up: bool, factor: float) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	event.pressed = true
	event.factor = factor
	return event

func test_parts_of_a_notch_add_up_to_one_step() -> void:
	var zoom := TtwZoom.new(PackedFloat32Array([0.5, 1.0, 2.0, 3.0, 4.0]))
	var z := 4.0
	for k in 4:
		z = zoom.apply(_wheel(false, 0.25), z)
	assert_float(z).is_equal(3.0)
	# Three more quarters do not reach the next step.
	for k in 3:
		z = zoom.apply(_wheel(false, 0.25), z)
	assert_float(z).is_equal(3.0)

func test_a_plain_wheel_steps_once_per_event_and_the_ends_hold() -> void:
	var zoom := TtwZoom.new(PackedFloat32Array([1.0, 2.0, 3.0]))
	assert_float(zoom.apply(_wheel(true, 0.0), 2.0)).is_equal(3.0)
	assert_float(zoom.apply(_wheel(true, 1.0), 3.0)).is_equal(3.0)
	assert_float(zoom.apply(_wheel(false, 1.0), 1.0)).is_equal(1.0)

func test_zooming_keeps_the_point_under_the_cursor_where_it_is() -> void:
	var camera := Camera2D.new()
	add_child(camera)
	camera.position = Vector2(500, 300)
	camera.zoom = Vector2(2, 2)
	var cursor := Vector2(560, 330)
	# On screen the cursor is (cursor - position) * zoom from the middle.
	var on_screen := (cursor - camera.position) * camera.zoom.x
	TtwZoom.toward(camera, cursor, 4.0)
	assert_vector((cursor - camera.position) * camera.zoom.x).is_equal_approx(on_screen, Vector2(0.001, 0.001))
	assert_float(camera.zoom.x).is_equal(4.0)
	camera.free()
