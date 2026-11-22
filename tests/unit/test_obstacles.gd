extends GdUnitTestSuite
## Pushing a vehicle's circle out of obstacle shapes.

func _circle(r: float) -> TtwObstacle:
	var o := TtwObstacle.new()
	o.shape = TtwObstacle.Shape.CIRCLE
	o.radius = r
	return o

func _box(h: Vector2, angle: float) -> TtwObstacle:
	var o := TtwObstacle.new()
	o.shape = TtwObstacle.Shape.BOX
	o.half_extents = h
	o.angle = angle
	return o

func test_a_circle_overlapping_a_trunk_is_pushed_to_touch_it() -> void:
	var out := TtwObstacles.push_out(Vector2(5, 0), 4.0, _circle(3.0), Vector2.ZERO)
	assert_vector(out).is_equal_approx(Vector2(7, 0), Vector2(0.001, 0.001))
	# Clear already: unchanged.
	assert_vector(TtwObstacles.push_out(Vector2(10, 0), 4.0, _circle(3.0), Vector2.ZERO)).is_equal(Vector2(10, 0))

func test_a_circle_is_pushed_out_of_a_turned_box_along_its_side() -> void:
	# A log along y (turned 90°): 20 long, 8 wide.
	var log := _box(Vector2(10, 4), PI / 2)
	var out := TtwObstacles.push_out(Vector2(6, 0), 3.0, log, Vector2.ZERO)
	assert_float(out.x).is_equal_approx(7.0, 0.001)
	assert_float(out.y).is_equal_approx(0.0, 0.001)

func test_a_centre_inside_a_box_leaves_by_the_nearest_side() -> void:
	var out := TtwObstacles.push_out(Vector2(0, 3), 2.0, _box(Vector2(10, 4), 0.0), Vector2.ZERO)
	assert_vector(out).is_equal_approx(Vector2(0, 6), Vector2(0.001, 0.001))
