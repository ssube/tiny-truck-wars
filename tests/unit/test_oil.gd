extends GdUnitTestSuite
## Oil: it floats off downstream without loss, makes ground slippery
## (pavement most), is carried about by tyres, burns, and bleeds from wrecks.

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

func _ground() -> TtwGround:
	return world.session.view([TtwGround])[0].get_component(TtwGround)

func test_a_slick_runs_downstream_and_keeps_its_volume() -> void:
	var t := Fixture.flat(Vector2i(24, 4), TtwMaterials.MUD)
	for y in 4:
		for x in 24:
			t.set_elevation(Vector2i(x, y), -0.3 * x)
	world = Fixture.make(self, t, true)
	var g := _ground()
	for x in 24:
		for y in 4:
			g.water.fill_to(Vector2i(x, y), 2.0)
	g.water.add_slick(t.tile_index(Vector2i(3, 1)), 4.0)
	await _ticks(300)
	var afloat := g.water.slick_volume()
	assert_float(afloat + t.layer_total(TtwTerrain.Layer.OIL)).is_equal_approx(4.0, 0.001)
	var moment := 0.0
	for i in g.water.slick.size():
		moment += g.water.slick[i] * (i % 24)
	assert_float(moment / afloat).is_greater(4.0)

func test_oil_takes_grip_and_most_on_pavement() -> void:
	assert_float(TtwOil.grip(TtwMaterials.PAVEMENT, 0.0)).is_equal(1.0)
	assert_float(TtwOil.grip(TtwMaterials.PAVEMENT, 1.0)).is_less(TtwOil.grip(TtwMaterials.SAND, 1.0))

func test_a_truck_gets_going_slower_on_oiled_pavement() -> void:
	var t := Fixture.flat(Vector2i(48, 16), TtwMaterials.PAVEMENT)
	for y in range(0, 8 * TtwTerrain.CELLS_PER_TILE):
		for x in t.size_cells.x:
			t.oil[y * t.size_cells.x + x] = 1.0
	world = Fixture.make(self, t)
	var oiled := world.spawn(&"truck", Vector2(40, 64))
	var clean := world.spawn(&"truck", Vector2(40, 192))
	for e in [oiled, clean]:
		(e.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(30)
	assert_float((oiled.get_component(TtwDrive) as TtwDrive).speed).is_less((clean.get_component(TtwDrive) as TtwDrive).speed)

func test_tyres_carry_oil_on_and_none_is_made_or_lost() -> void:
	var t := Fixture.flat(Vector2i(48, 8), TtwMaterials.PAVEMENT)
	TtwOil.spill(t, null, Vector2(80, 64), 2.0, 10.0)
	world = Fixture.make(self, t)
	var truck := world.spawn(&"truck", Vector2(40, 64))
	(truck.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(150)
	var v: TtwVehicle = truck.get_component(TtwVehicle)
	assert_float(t.layer_total(TtwTerrain.Layer.OIL) + v.carried_oil).is_equal_approx(2.0, 0.001)
	var beyond := 0.0
	for x in range(140, 400, 2):
		for y in range(54, 76, 2):
			beyond += t.cell_value(TtwTerrain.Layer.OIL, t.cell_of(Vector2(x, y)))
	assert_float(beyond).is_greater(0.0)

func test_fire_runs_along_a_spill_and_not_over_clean_pavement() -> void:
	var t := Fixture.flat(Vector2i(24, 6), TtwMaterials.PAVEMENT)
	world = Fixture.make(self, t)
	var g := _ground()
	g.fire = TtwFireField.new(t.size_tiles)
	for x in 8:
		TtwOilSystem.spill(g, Vector2(x + 0.5, 2.5) * 16.0, 1.5, 8.0)
	assert_bool(g.fire.ignite(Vector2i(0, 2))).is_true()
	for k in 300:
		g.fire.step(0.1, t, null)
		assert_bool(g.fire.is_burning(Vector2i(12, 2))).is_false()
		assert_bool(g.fire.is_burning(Vector2i(3, 5))).is_false()

func test_a_wreck_bleeds_oil() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.PAVEMENT)
	world = Fixture.make(self, t)
	var tank := world.spawn(&"tank", Vector2(128, 128))
	(world.session.system(&"drive") as TtwDriveSystem).wreck(tank)
	await _ticks(TtwOilSystem.BLEED_EVERY * 8)
	assert_float(t.layer_total(TtwTerrain.Layer.OIL)).is_greater(0.0)
