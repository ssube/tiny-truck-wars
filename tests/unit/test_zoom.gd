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
