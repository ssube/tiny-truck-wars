extends GdUnitTestSuite
## The water simulation: volume kept, water running downhill and pooling,
## sources and sinks, soaking, and the current it makes.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")

var world: Fixture.TestWorld

func after_test() -> void:
	if world != null:
		world.queue_free()
		world = null

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0)
	assert_bool(result.success).is_true()

func _sloped(tiles: Vector2i, fall_per_tile: float) -> TtwTerrain:
	var t := Fixture.flat(tiles, TtwMaterials.MUD)
	for y in tiles.y:
		for x in tiles.x:
			t.set_elevation(Vector2i(x, y), -fall_per_tile * x)
	return t

func test_water_keeps_its_volume_as_it_flows() -> void:
	var t := _sloped(Vector2i(24, 12), 0.5)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	for x in range(2, 6):
		water.fill_to(Vector2i(x, 5), 4.0)
	var start := water.total_volume()
	assert_float(start).is_greater(10.0)
	await _ticks(600)
	# What dry ground it ran onto took in is part of the books.
	assert_float(water.total_volume() + water.infiltrated).is_equal_approx(start, start * 1e-4)

func test_water_runs_downhill() -> void:
	var t := _sloped(Vector2i(24, 4), 0.5)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	# Ground already full, so all of it runs on.
	water.absorbed.fill(TtwWater.SOIL_HOLDS)
	water.fill_to(Vector2i(3, 1), 6.0)
	await _ticks(240)
	var mass := 0.0
	var moment := 0.0
	for y in 4:
		for x in 24:
			var d := water.depth[y * 24 + x]
			mass += d
			moment += d * x
	assert_float(moment / mass).is_greater(6.0)

func test_water_pools_in_a_pit_and_not_on_level_pavement() -> void:
	var t := Fixture.flat(Vector2i(12, 12), TtwMaterials.PAVEMENT)
	for y in range(5 * 8, 7 * 8):
		for x in range(5 * 8, 7 * 8):
			t.deform[y * t.size_cells.x + x] = -6.0
	t.mark_cells(Rect2i(40, 40, 16, 16))
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	for y in range(3, 9):
		for x in range(3, 9):
			water.fill_to(Vector2i(x, y), 0.4)
	await _ticks(600)
	var pit := water.depth[5 * 12 + 5]
	var flat := water.depth[1 * 12 + 1]
	assert_float(pit).is_greater(4.0)
	assert_float(flat).is_less(0.2)
	# The drawn level shows it in the pit and not on the pavement around it.
	assert_float(t.water_depth_at(Vector2(5.5, 5.5) * 16.0)).is_greater(4.0)
	assert_float(t.water_depth_at(Vector2(1.5, 1.5) * 16.0)).is_less(0.2)

func test_sources_and_sinks_account_for_every_drop() -> void:
	var t := _sloped(Vector2i(20, 4), 0.4)
	t.water_sources.append({"rect": Rect2i(0, 1, 1, 2), "level": 3.0})
	t.water_sinks.append({"rect": Rect2i(19, 1, 1, 2), "level": -0.4 * 19})
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	var start := water.total_volume()
	await _ticks(600)
	assert_float(water.added).is_greater(0.0)
	assert_float(water.drained).is_greater(0.0)
	assert_float(water.total_volume() + water.infiltrated).is_equal_approx(start + water.added - water.drained, 0.01)
	# A steady stream: it runs east, toward the sink.
	assert_float(t.flow[1 * 20 + 10].x).is_greater(0.0)

func test_ground_that_goes_under_is_soaked() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.MUD)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	water.fill_to(Vector2i(3, 3), 2.0)
	await _ticks(TtwWater.STEP_TICKS)
	var cell := Vector2i(3, 3) * TtwTerrain.CELLS_PER_TILE + Vector2i(2, 2)
	assert_float(t.cell_value(TtwTerrain.Layer.WET, cell)).is_equal(1.0)

func test_a_bed_under_water_keeps_its_shape_and_its_cells_leave_the_settling_queue() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.SAND)
	for y in range(3 * 8, 5 * 8):
		for x in range(3 * 8, 5 * 8):
			t.deform[y * t.size_cells.x + x] = -5.0
	t.mark_cells(Rect2i(24, 24, 16, 16))
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	for y in range(3, 5):
		for x in range(3, 5):
			water.fill_to(Vector2i(x, y), -1.0)
	var bed := Vector2i(30, 30)
	await _ticks(TtwSettleSystem.PERIOD_TICKS * 4)
	assert_float(t.cell_value(TtwTerrain.Layer.DEFORM, bed)).is_equal(-5.0)
	assert_float(t.cell_value(TtwTerrain.Layer.WET, bed)).is_equal(1.0)
	assert_bool(t.settling.has(t.cell_index(bed))).is_false()

func test_ground_dries_once_the_water_has_gone() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.MUD)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	water.fill_to(Vector2i(3, 3), 2.0)
	await _ticks(TtwWater.STEP_TICKS * 2)
	var cell := Vector2i(3, 3) * TtwTerrain.CELLS_PER_TILE + Vector2i(4, 4)
	assert_float(t.cell_value(TtwTerrain.Layer.WET, cell)).is_equal(1.0)
	# Gone: every tile drained.
	for y in 8:
		for x in 8:
			water.fill_to(Vector2i(x, y), TtwTerrain.NO_WATER)
	await _ticks(TtwSettleSystem.PERIOD_TICKS * 3)
	assert_float(t.cell_value(TtwTerrain.Layer.WET, cell)).is_less(1.0)

func test_pouring_and_drawing_keep_the_books() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.MUD)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	var start := water.total_volume()
	assert_float(water.pour(Vector2(128, 128), 30.0, 24.0)).is_equal(30.0)
	# The ground under it is soaked straight away: mud made on purpose.
	assert_float(t.cell_value(TtwTerrain.Layer.WET, t.cell_of(Vector2(128, 128)))).is_equal(1.0)
	var got := water.draw(Vector2(128, 128), 10.0, 40.0)
	assert_float(got).is_equal_approx(10.0, 0.0001)
	await _ticks(60)
	assert_float(water.total_volume() + water.infiltrated).is_equal_approx(start + water.poured - water.drawn, 0.001)

func test_drawing_from_dry_ground_gets_nothing() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.MUD)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	assert_float(water.draw(Vector2(64, 64), 10.0)).is_equal(0.0)

func test_a_little_water_poured_on_dry_ground_soaks_in_where_it_lands() -> void:
	var t := Fixture.flat(Vector2i(48, 48), TtwMaterials.GRASS)
	world = Fixture.make(self, t, true)
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	var volume := 4.0
	water.pour(Vector2(24, 24) * 16.0, volume, 22.0)
	await _ticks(600)
	# All of it in the ground, within a few tiles of where it landed.
	assert_float(water.total_volume()).is_less(0.001)
	assert_float(water.infiltrated).is_equal_approx(volume, 0.001)
	var furthest := 0.0
	for i in water.absorbed.size():
		if water.absorbed[i] > 0.0:
			furthest = maxf(furthest, Vector2(i % 48, i / 48).distance_to(Vector2(23.5, 23.5)))
	assert_float(furthest).is_less(4.0)
	# On pavement it stays on top.
	var full := Fixture.flat(Vector2i(8, 8), TtwMaterials.PAVEMENT)
	var other := Fixture.make(self, full, true)
	var on_top: TtwWater = other.session.view([TtwGround])[0].get_component(TtwGround).water
	on_top.pour(Vector2(64, 64), 1.0, 16.0)
	await _ticks(60)
	assert_float(on_top.infiltrated).is_equal(0.0)
	assert_float(on_top.total_volume()).is_equal_approx(1.0, 0.001)
	other.queue_free()
