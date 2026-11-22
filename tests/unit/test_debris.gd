extends GdUnitTestSuite
## Thrown bits' rough physics: they land, slide down slopes, drift with the
## current, and never number more than MAX_BITS. (Drawing only, stepped by
## hand here: TtwDebris is a node, not a GECS system.)

const Fixture := preload("res://tests/support/world.gd")

func _debris(t: TtwTerrain) -> TtwDebris:
	var d := TtwDebris.new()
	d.terrain = t
	d.set_process(false)
	add_child(d)
	return d

func _run(d: TtwDebris, seconds: float) -> void:
	for i in int(seconds * 60.0):
		d.step(1.0 / 60.0)

func test_bits_slide_down_a_slope() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.PAVEMENT)
	for y in 8:
		for x in 16:
			t.set_elevation(Vector2i(x, y), 20.0 - 2.0 * x)
	var d := _debris(t)
	d.throw(TtwDebris.Kind.DEBRIS, Vector3(64, 64, 0.5), Vector2.RIGHT, 0.0, 0.0, 0.0, 8)
	_run(d, 2.0)
	assert_int(d.count()).is_equal(8)
	for k in d.count():
		assert_float(d.position3[k].x).is_greater(70.0)
	d.queue_free()

func test_bits_rest_on_level_ground() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	var d := _debris(t)
	d.throw(TtwDebris.Kind.CLOD, Vector3(64, 64, 0.5), Vector2.RIGHT, 0.0, 0.0, 0.0, 4)
	_run(d, 2.0)
	for k in d.count():
		assert_float(Vector2(d.position3[k].x, d.position3[k].y).distance_to(Vector2(64, 64))).is_less(1.0)
	d.queue_free()

func test_bits_in_water_drift_with_the_current() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.SAND)
	t.water.fill(3.0)
	t.flow.fill(Vector2(0, 20))
	var d := _debris(t)
	d.throw(TtwDebris.Kind.DEBRIS, Vector3(64, 32, 0.5), Vector2.RIGHT, 0.0, 0.0, 0.0, 4)
	_run(d, 2.0)
	for k in d.count():
		assert_float(d.position3[k].y).is_greater(50.0)
	d.queue_free()

func test_droplets_end_where_they_land() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.SAND)
	var d := _debris(t)
	d.throw(TtwDebris.Kind.DROPLET, Vector3(64, 64, 2.0), Vector2.RIGHT, 20.0, 1.0, 30.0, 10)
	_run(d, 1.0)
	assert_int(d.count()).is_equal(0)
	d.queue_free()

func test_never_more_than_max_bits() -> void:
	var t := Fixture.flat(Vector2i(16, 8), TtwMaterials.MUD)
	var d := _debris(t)
	d.throw(TtwDebris.Kind.CLOD, Vector3(64, 64, 5.0), Vector2.RIGHT, 20.0, TAU, 30.0, TtwDebris.MAX_BITS + 50)
	assert_int(d.count()).is_equal(TtwDebris.MAX_BITS)
	d.queue_free()
