extends GdUnitTestSuite
## Helicopters fly straight over what stops ground units, crab into the wind
## and hold station against it, sink and drift downwind out of fuel, land on
## their side's helipad to be refuelled, are built there, fire rockets from
## the air, and are hit by tank fire only at the gun's air accuracy.

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

func _world(tiles: Vector2i = Vector2i(48, 32)) -> void:
	world = Fixture.make(self, Fixture.flat(tiles, TtwMaterials.GRASS))

func _wind(wind: Vector2) -> void:
	var w := TtwWeather.new()
	w.wind = wind
	world.session.resolve("map").add_component(w)

func _flight(heli: Entity) -> TtwFlight:
	return heli.get_component(TtwFlight)

## Ticks to fly `distance` px from the ground: lift off, get up to speed,
## cover it, and the slow last stretch.
func _flight_ticks(f: TtwFlight, distance: float) -> int:
	var speed := f.max_speed_tiles * 16.0
	var seconds := TtwFlightSystem.LIFT_OFF_PX / f.climb_px + speed / (f.accel_tiles * 16.0) + distance / speed + TtwFlightSystem.SLOW_PX / (speed * 0.15)
	return ceili(seconds * 60.0)

func test_a_helicopter_crosses_a_river_that_ground_units_path_around() -> void:
	_world()
	var t := world.terrain
	var n := TtwTerrain.CELLS_PER_TILE
	for y in t.size_tiles.y:
		for x in range(22, 26):
			t.water[t.tile_index(Vector2i(x, y))] = -1.5
	for cy in t.size_cells.y:
		for cx in range(22 * n, 26 * n):
			t.deform[cy * t.size_cells.x + cx] = -12.0
	t.mark_all()
	var from := Vector2(10, 16) * 16.0
	var to := Vector2(38, 16) * 16.0
	await _ticks(1) # the path grid
	var route := TtwGround.paths_of(world.session).find(from, to)
	assert_bool(route.is_empty() or route[route.size() - 1].distance_to(to) > 16.0 * 10.0).is_true()
	var heli := world.spawn(&"helicopter", from)
	var landed_at := UI.observe((world.session.system(&"flight") as TtwFlightSystem).arrived)
	TtwPilotSystem.order(heli, to)
	var result: Dictionary = await landed_at.wait(get_tree(), _flight_ticks(_flight(heli), from.distance_to(to)) / 60.0)
	assert_bool(result.received).is_true()
	assert_float(world.session.body_of(heli).position.distance_to(to)).is_less(TtwFlightSystem.ARRIVE_PX)

func test_across_the_wind_it_crabs_into_it_and_still_arrives() -> void:
	_world()
	_wind(Vector2(30, 0))
	var from := Vector2(200, 440)
	var to := Vector2(200, 100)
	var heli := world.spawn(&"helicopter", from)
	var f := _flight(heli)
	var arrived := UI.observe((world.session.system(&"flight") as TtwFlightSystem).arrived)
	TtwPilotSystem.order(heli, to)
	var headings: Array[float] = []
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), _flight_ticks(f, from.distance_to(to)), 30.0, func():
		if f.velocity.length() > f.max_speed_tiles * 16.0 * 0.8:
			headings.append(f.heading))
	assert_bool(arrived.received).is_true()
	assert_bool(result.success).is_true()
	assert_bool(headings.is_empty()).is_false()
	# Flying north (−y) with the wind blowing east, the nose is turned west of north.
	assert_bool(headings.all(func(h): return Vector2.from_angle(h).x < -0.05)).is_true()

func test_hovering_it_holds_station_and_out_of_fuel_it_sinks_and_drifts_downwind() -> void:
	_world()
	_wind(Vector2(30, 0))
	var heli := world.spawn(&"helicopter", Vector2(200, 250))
	var f := _flight(heli)
	f.altitude = f.cruise_px
	await _ticks(60)
	var held := world.session.body_of(heli).position
	await _ticks(120)
	assert_float(world.session.body_of(heli).position.distance_to(held)).is_less(1.0)
	(heli.get_component(TtwFuel) as TtwFuel).amount = 0.0
	var ticks := ceili(f.cruise_px / f.climb_px * 60.0) + 1
	await _ticks(ticks)
	assert_float(f.altitude).is_equal(0.0)
	var drifted := world.session.body_of(heli).position - held
	assert_float(drifted.x).is_greater(16.0)
	assert_float(absf(drifted.y)).is_less(2.0)
	# Down, it stays put.
	var down := world.session.body_of(heli).position
	await _ticks(30)
	assert_vector(world.session.body_of(heli).position).is_equal(down)

func test_it_lands_on_its_sides_helipad_and_is_refuelled_there() -> void:
	_world()
	var pad := world.structure(&"helipad", Vector2(300, 250))
	world.structure(&"depot", Vector2(380, 250))
	var heli := world.spawn(&"helicopter", Vector2(300, 250))
	var f := _flight(heli)
	f.altitude = f.cruise_px
	var tank: TtwFuel = heli.get_component(TtwFuel)
	tank.amount = 10.0
	var down := ceili(f.cruise_px / f.climb_px * 60.0) + 1
	await _ticks(down)
	assert_float(f.altitude).is_equal(0.0)
	var low := tank.level()
	await _ticks(TtwGarageSystem.SERVICE_TICKS * 3)
	assert_float(tank.level()).is_greater(low)
	assert_bool(is_instance_valid(pad)).is_true()

func test_a_helipad_builds_gunships_and_a_garage_does_not() -> void:
	_world()
	var garage := world.structure(&"garage", Vector2(120, 120))
	var pad := world.structure(&"helipad", Vector2(300, 250))
	world.structure(&"depot", Vector2(380, 250))
	world.structure(&"depot", Vector2(120, 200))
	assert_str(TtwGarageSystem.enqueue(garage, &"gunship")).is_equal("A garage cannot build gunship.")
	assert_str(TtwGarageSystem.enqueue(pad, &"tank")).is_equal("A helipad cannot build tank.")
	assert_str(TtwGarageSystem.enqueue(pad, &"gunship")).is_empty()
	var made := UI.observe((world.session.system(&"garages") as TtwGarageSystem).produced)
	var result: Dictionary = await made.wait(get_tree(), TtwProduction.unit_seconds(&"gunship") + 1.0)
	assert_bool(result.received).is_true()
	var heli: Entity = result.value[1]
	assert_bool(heli.has_component(TtwAircraft)).is_true()
	assert_object(heli.get_component(TtwGun)).is_not_null()
	assert_str(String((heli.get_component(TtwGun) as TtwGun).ammo)).is_equal("rocket")
	assert_vector(world.session.body_of(heli).position).is_equal(Vector2(300, 250))

func test_tank_fire_hits_an_aircraft_at_exactly_its_air_accuracy() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(100, 250))
	var gun: TtwGun = tank.get_component(TtwGun)
	gun.ready_tick = 1 << 30
	var heli := world.spawn(&"helicopter", Vector2(200, 250), 0.0, 2)
	var f := _flight(heli)
	f.altitude = f.cruise_px
	var c: TtwCondition = heli.get_component(TtwCondition)
	c.max_health = 1.0e6
	c.health = 1.0e6
	var ballistics: TtwBallisticsSystem = world.session.system(&"ballistics")
	var shots := 20
	var hits := 0
	await _ticks(1)
	for k in shots:
		var before := c.current()
		var landed := UI.observe(ballistics.burst)
		(world.session.system(&"guns") as TtwGunSystem).fire(tank, heli)
		var result: Dictionary = await landed.wait(get_tree(), 2.0)
		assert_bool(result.received).is_true()
		assert_str(String(result.value[2])).is_equal("air")
		if c.current() < before:
			hits += 1
	assert_int(hits).is_equal(floori(shots * gun.air_accuracy))

func test_a_gunship_fires_rockets_from_the_air_at_ground_units() -> void:
	_world()
	var heli := world.spawn(&"gunship", Vector2(100, 250))
	var f := _flight(heli)
	f.altitude = f.cruise_px
	var gun: TtwGun = heli.get_component(TtwGun)
	var target := world.spawn(&"truck", Vector2(100 + gun.range_px() - 8.0, 250), 0.0, 2)
	var c: TtwCondition = target.get_component(TtwCondition)
	TtwGunSystem.attack(world.session, heli, target)
	var landed := UI.observe((world.session.system(&"ballistics") as TtwBallisticsSystem).burst)
	var flight := TtwCombat.flight_ticks(gun, Vector2(100, 250), world.session.body_of(target).position)
	var result: Dictionary = await landed.wait(get_tree(), (flight + 2) / 60.0)
	assert_bool(result.received).is_true()
	assert_float(c.current()).is_less(c.max_health)
	# The same helicopter on the ground (out of fuel, it stays there) does not fire.
	f.altitude = 0.0
	(heli.get_component(TtwFuel) as TtwFuel).amount = 0.0
	gun.ready_tick = 0
	var again := UI.observe((world.session.system(&"guns") as TtwGunSystem).fired)
	await _ticks(3)
	assert_bool(again.received).is_false()
