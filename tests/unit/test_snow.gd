extends GdUnitTestSuite
## Snow: pressed down into packed tracks with berms beside them, thawed by
## warmth (its melt booked: runoff into ruts, the rest into the soil), blown
## off by blasts; loose snow drags and packed snow slips.

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

func _snowy(tiles: Vector2i, depth: float) -> TtwTerrain:
	var t := Fixture.flat(tiles, TtwMaterials.GRASS)
	t.snow_base.fill(depth)
	return t

func test_a_pass_packs_the_snow_and_heaps_berms_beside_it() -> void:
	var t := _snowy(Vector2i(8, 8), 4.0)
	var at := Vector2(64, 64)
	TtwSnow.press(t, at, 0.0, 2.0, 6.0)
	assert_float(TtwSnow.depth(t, at)).is_equal_approx(4.0 * (1.0 - TtwSnow.PACK), 0.001)
	assert_bool(TtwSnow.is_packed(t, t.cell_index(t.cell_of(at)))).is_true()
	assert_float(TtwSnow.depth(t, at + Vector2(0, 4.5))).is_greater(4.0)

func test_the_thaw_follows_the_temperature_and_stops_below_freezing() -> void:
	var w := TtwWeather.new()
	w.temperature = -3.0
	assert_float(TtwSnowSystem.thaw_rate(w)).is_equal(0.0)
	w.temperature = 2.0
	var mild := TtwSnowSystem.thaw_rate(w)
	w.temperature = 10.0
	assert_float(TtwSnowSystem.thaw_rate(w)).is_greater(mild)
	assert_float(mild).is_greater(0.0)

func test_every_bit_of_melt_is_booked_and_ruts_get_the_runoff() -> void:
	var t := _snowy(Vector2i(8, 8), 2.0)
	var rut := Vector2i(3, 3)
	for y in range(rut.y * 8, rut.y * 8 + 8):
		for x in range(rut.x * 8 + 3, rut.x * 8 + 5):
			t.deform[y * t.size_cells.x + x] = -4.0
	t.mark_cells(Rect2i(rut * 8, Vector2i(8, 8)))
	world = Fixture.make(self, t, true)
	var w := TtwWeather.new()
	w.temperature = 15.0
	w.sun = 1.0
	world.session.resolve("map").add_component(w)
	var snow: TtwSnowSystem = world.session.system(&"snow")
	var water: TtwWater = world.session.view([TtwGround])[0].get_component(TtwGround).water
	snow.reset_books(t.snow_level)
	await _ticks(TtwSnowSystem.RUNOFF_TICKS * 3)
	assert_float(snow.melted).is_greater(0.0)
	assert_float(snow.ran_off + snow.soaked).is_equal_approx(snow.melted, 0.0001)
	assert_float(snow.ran_off).is_greater(0.0)
	assert_float(water.depth[t.tile_index(rut)]).is_greater(0.0)

func test_a_blast_clears_the_snow() -> void:
	var t := _snowy(Vector2i(8, 8), 3.0)
	TtwSnow.blast(t, Vector2(64, 64), 12.0)
	assert_float(TtwSnow.depth(t, Vector2(64, 64))).is_equal(0.0)
	assert_float(TtwSnow.depth(t, Vector2(64, 100))).is_equal(3.0)

func test_deep_loose_snow_drags_and_packed_snow_slips() -> void:
	var t := _snowy(Vector2i(32, 16), 6.0)
	world = Fixture.make(self, t)
	var deep := world.spawn(&"truck", Vector2(64, 64))
	(deep.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	# A lane of packed snow for the other.
	for y in range(23 * 8 / 2 - 8, 23 * 8 / 2 + 8):
		for x in t.size_cells.x:
			t.snow_gone[y * t.size_cells.x + x] = 4.0
	var packed := world.spawn(&"truck", Vector2(64, 184)) # cell row 92: the lane
	(packed.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(2)
	var d_deep: TtwDrive = deep.get_component(TtwDrive)
	var d_packed: TtwDrive = packed.get_component(TtwDrive)
	assert_float(d_deep.resistance).is_greater(TtwMaterials.RESISTANCE[TtwMaterials.GRASS] * 1.3)
	assert_float(d_packed.grip).is_less_equal(TtwDriveSystem.PACKED_SNOW_GRIP + 0.001)
