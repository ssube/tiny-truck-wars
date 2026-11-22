extends GdUnitTestSuite
## The truck kits and the bucket: a Tanker carries fuel from depots to its
## side; an Engineer lays gravel road over ruts for fuel; a Water tanker pumps
## a pond and sprays a spot into mud and out of fire; a bucket helicopter
## dips to fill and drops it all. The water is accounted for throughout.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")
const UI := preload("res://tests/support/ui.gd")

var world: Fixture.TestWorld

func after_test() -> void:
	if world != null:
		world.queue_free()
		world = null

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0)
	assert_bool(result.success).is_true()

## Grass with a pond 4 px deep over tiles (4..9, 4..9).
func _pond_world() -> void:
	var t := Fixture.flat(Vector2i(32, 24), TtwMaterials.GRASS)
	var n := TtwTerrain.CELLS_PER_TILE
	for ty in range(4, 10):
		for tx in range(4, 10):
			t.water[t.tile_index(Vector2i(tx, ty))] = 0.0
			for cy in range(ty * n, (ty + 1) * n):
				for cx in range(tx * n, (tx + 1) * n):
					t.deform[cy * t.size_cells.x + cx] = -4.0
	t.mark_all()
	world = Fixture.make(self, t, true, true)

func test_a_tanker_fuels_its_side_near_it_and_fills_up_at_a_depot() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(32, 24), TtwMaterials.GRASS))
	var tanker := world.spawn(&"tanker", Vector2(100, 100))
	var t: TtwTanker = tanker.get_component(TtwTanker)
	var reach := t.reach_tiles * 16.0
	var own := world.spawn(&"truck", Vector2(100 + reach, 100))
	var far := world.spawn(&"truck", Vector2(100, 100 + reach + 1.0))
	var enemy := world.spawn(&"truck", Vector2(100 - reach, 100), 0.0, 2)
	for unit in [own, far, enemy]:
		(unit.get_component(TtwFuel) as TtwFuel).amount = 10.0
	var services := 3
	await _ticks(TtwKitSystem.SERVICE_TICKS * services)
	var given := t.rate * TtwKitSystem.SERVICE_TICKS / 60.0 * services
	# The one out of reach only burned its idle; the one in reach got the rest.
	var idle := (far.get_component(TtwFuel) as TtwFuel).level()
	assert_float(idle).is_less(10.0)
	assert_float((own.get_component(TtwFuel) as TtwFuel).level()).is_equal_approx(idle + given, 0.001)
	assert_float((enemy.get_component(TtwFuel) as TtwFuel).level()).is_less(10.0)
	assert_float(t.level()).is_equal_approx(t.cargo_capacity - given, 0.01)
	# At a depot the cargo is topped up.
	world.structure(&"depot", Vector2(100, 140))
	await _ticks(TtwDepotSystem.SERVICE_TICKS * 2)
	assert_float(t.level()).is_greater(t.cargo_capacity - given)

func test_a_paving_engineer_lays_gravel_over_ruts_for_fuel() -> void:
	var t := Fixture.flat(Vector2i(32, 16), TtwMaterials.MUD)
	t.deform.fill(-2.0)
	t.loose.fill(0.5)
	world = Fixture.make(self, t)
	var engineer := world.spawn(&"engineer", Vector2(40, 120))
	var fuel: TtwFuel = engineer.get_component(TtwFuel)
	var e: TtwEngineer = engineer.get_component(TtwEngineer)
	var d: TtwDrive = engineer.get_component(TtwDrive)
	# Not paving: the ground is left as it is.
	d.throttle = 1.0
	await _ticks(30)
	var row := 120 / 16
	assert_int(t.material_at_tile(Vector2i(2, row))).is_equal(TtwMaterials.MUD)
	TtwKitSystem.set_paving(engineer, true)
	var start := t.tile_of(world.session.body_of(engineer).position).x
	await _ticks(90)
	var end := t.tile_of(world.session.body_of(engineer).position).x
	assert_int(end).is_greater(start + 1)
	var paved := 0
	for x in range(start, end + 1):
		assert_int(t.material_at_tile(Vector2i(x, row))).is_equal(TtwMaterials.GRAVEL)
		paved += 1
		var cell := t.cell_index(Vector2i(x * 8 + 4, row * 8 + 4))
		assert_float(t.deform[cell]).is_greater_equal(0.0)
		assert_float(t.loose[cell]).is_equal(0.0)
	assert_float(d.max_speed_tiles).is_greater(0.0)
	# Each tile paid for once (and driving burned the rest).
	assert_float(fuel.capacity - fuel.level()).is_greater_equal(paved * e.pave_fuel)

func test_a_water_tanker_pumps_a_pond_and_sprays_a_spot_into_mud_and_out_of_fire() -> void:
	_pond_world()
	var water := TtwGround.water_of(world.session)
	var field := TtwGround.fire_of(world.session)
	var truck := world.spawn(&"water_tanker", Vector2(10.5, 7) * 16.0)
	var tank: TtwWaterTank = truck.get_component(TtwWaterTank)
	assert_str(TtwKitSystem.spray(truck, Vector2(200, 200))).is_equal("Its tank is empty: drive it to water to pump.")
	await _ticks(1)
	var drawn := water.drawn
	var held := tank.amount
	var fill := ceili(tank.capacity / tank.pump_rate * 60.0) + 1
	await _ticks(fill)
	assert_float(tank.amount).is_equal_approx(tank.capacity, 0.001)
	assert_float(water.drawn - drawn).is_equal_approx(tank.amount - held, 0.001)
	# A burning patch of grass within reach.
	var spot := Vector2(13.5, 7.5) * 16.0
	var tile := world.terrain.tile_of(spot)
	field.add_fuel(tile, 50.0)
	field.ignite(tile, 1.0)
	var poured := water.poured
	assert_str(TtwKitSystem.spray(truck, spot)).is_empty()
	var spray := ceili(tank.capacity / tank.spray_rate * 60.0) + 1
	await _ticks(spray)
	assert_float(tank.amount).is_equal(0.0)
	assert_bool(truck.has_component(TtwSprayOrder)).is_false()
	assert_float(water.poured - poured).is_equal_approx(tank.capacity, 0.01)
	assert_float(world.terrain.cell_value(TtwTerrain.Layer.WET, world.terrain.cell_of(spot))).is_equal(1.0)
	await _ticks(1)
	assert_bool(field.is_burning(tile)).is_false()

func test_a_bucket_helicopter_dips_to_fill_and_drops_it_all_on_a_spot() -> void:
	_pond_world()
	var water := TtwGround.water_of(world.session)
	var heli := world.spawn(&"bucket_heli", Vector2(7, 7) * 16.0)
	var f: TtwFlight = heli.get_component(TtwFlight)
	f.altitude = f.cruise_px
	var b: TtwBucket = heli.get_component(TtwBucket)
	var down := ceili((f.cruise_px - b.dip_px) / f.climb_px * 60.0) + 1
	var fill := ceili(b.capacity / b.fill_rate * 60.0) + 1
	await _ticks(down + fill)
	assert_float(b.amount).is_equal_approx(b.capacity, 0.001)
	var spot := Vector2(22, 16) * 16.0
	var poured := water.poured
	var dropped := UI.observe((world.session.system(&"kits") as TtwKitSystem).dropped)
	assert_str(TtwKitSystem.drop(heli, spot)).is_empty()
	var distance := (Vector2(7, 7) * 16.0).distance_to(spot)
	var seconds := (f.cruise_px - b.dip_px) / f.climb_px + distance / (f.max_speed_tiles * 16.0) + f.max_speed_tiles / f.accel_tiles + TtwFlightSystem.SLOW_PX / (f.max_speed_tiles * 16.0 * 0.15)
	var result: Dictionary = await dropped.wait(get_tree(), seconds)
	assert_bool(result.received).is_true()
	assert_float(result.value[2]).is_equal_approx(b.capacity, 0.001)
	assert_float(b.amount).is_equal(0.0)
	assert_float(water.poured - poured).is_equal_approx(b.capacity, 0.01)
	assert_str(TtwKitSystem.drop(heli, spot)).is_equal("Its bucket is empty: hover it over water to fill.")
