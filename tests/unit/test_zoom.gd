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

## Every screen shows about the same stretch of the world: the starting zoom
## and the wheel's ends are the whole zooms nearest to what the 1280×720
## layout shows at 3, and from 1 to 5 (the Mud Lab 0.5 to 8).
func test_a_game_starts_showing_about_what_the_layout_shows_at_zoom_3() -> void:
	assert_float(TtwZoom.start(Vector2(1280, 720))).is_equal(3.0)
	# 4.5 would be the same view: 5 (384×216 world px) is nearer it than 4 (480×270).
	assert_float(TtwZoom.start(Vector2(1920, 1080))).is_equal(5.0)
	# TtwDisplay enlarges these 2 and 3 times: their view is the layout's.
	assert_float(TtwZoom.start(Vector2(2560, 1440) / 2.0)).is_equal(3.0)
	assert_float(TtwZoom.start(Vector2(3840, 2160) / 3.0)).is_equal(3.0)
	# A view of another shape goes by its tighter side.
	assert_float(TtwZoom.start(Vector2(1280, 1280))).is_equal(3.0)
	assert_float(TtwZoom.start(Vector2(640, 360))).is_equal(2.0)

func test_the_wheels_levels_follow_the_view() -> void:
	var layout := Vector2(1280, 720)
	var hd := Vector2(1920, 1080)
	assert_array(Array(TtwZoom.levels_for(layout, TtwZoom.SKIRMISH_FAR, TtwZoom.SKIRMISH_NEAR))).is_equal([1.0, 2.0, 3.0, 4.0, 5.0])
	assert_array(Array(TtwZoom.levels_for(layout, TtwZoom.LAB_FAR, TtwZoom.LAB_NEAR))).is_equal([0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])
	# The same ends in world terms at 1080p.
	assert_array(Array(TtwZoom.levels_for(hd, TtwZoom.SKIRMISH_FAR, TtwZoom.SKIRMISH_NEAR))).is_equal([2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0])
	var lab := TtwZoom.levels_for(hd, TtwZoom.LAB_FAR, TtwZoom.LAB_NEAR)
	assert_float(lab[0]).is_equal(1.0)
	assert_float(lab[lab.size() - 1]).is_equal(12.0)
