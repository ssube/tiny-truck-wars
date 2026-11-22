extends GdUnitTestSuite
## The special units: a boss near a garage makes it build faster (not past
## its reach); a hippy's smoke slows ground units inside and hides them from
## guns, drifts downwind, clears in its time and waits on its cooldown; a
## nurse heals its side's ground vehicles near it, not helicopters.

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

func _world(material: int = TtwMaterials.GRASS) -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(48, 32), material))

func _build_ticks(boss_at: Vector2) -> int:
	_world()
	var garage := world.structure(&"garage", Vector2(200, 200))
	var depot := world.structure(&"depot", Vector2(320, 200))
	(depot.get_component(TtwDepot) as TtwDepot).refill = 0.0
	world.spawn(&"boss", boss_at)
	var made := []
	(world.session.system(&"garages") as TtwGarageSystem).produced.connect(func(_g, _u): made.append(world.session.tick))
	TtwGarageSystem.enqueue(garage, &"wrecker")
	var start := world.session.tick
	await _ticks(ceili(TtwProduction.unit_seconds(&"wrecker") * 60.0))
	assert_int(made.size()).is_equal(1)
	var took: int = made[0] - start
	world.queue_free()
	world = null
	return took

func test_a_boss_near_a_garage_speeds_its_building_and_not_from_past_its_reach() -> void:
	var b := TtwBoss.new()
	var reach := b.reach_tiles * 16.0
	var seconds := TtwProduction.unit_seconds(&"wrecker")
	var near := await _build_ticks(Vector2(200, 200 + reach))
	assert_int(near).is_equal(ceili(seconds * 60.0 / (1.0 + b.speedup) - 0.0001))
	var far := await _build_ticks(Vector2(200, 200 + reach + 1.0))
	assert_int(far).is_equal(ceili(seconds * 60.0))

func test_smoke_slows_ground_units_inside_drifts_downwind_and_clears() -> void:
	_world(TtwMaterials.PAVEMENT)
	var w := TtwWeather.new()
	w.wind = Vector2(20, 0)
	world.session.resolve("map").add_component(w)
	var hippy := world.spawn(&"hippy", Vector2(100, 100))
	var launcher: TtwSmokeLauncher = hippy.get_component(TtwSmokeLauncher)
	var inside := world.spawn(&"truck", Vector2(100, 200))
	var outside := world.spawn(&"truck", Vector2(100, 400))
	await _ticks(1)
	# Thrown further than it reaches, it lands at the edge of its reach toward the spot.
	assert_str(TtwSpecialSystem.smoke(world.session, hippy, Vector2(100, 300))).is_empty()
	var cloud: TtwSmokeCloud = world.session.view([TtwSmokeCloud])[0].get_component(TtwSmokeCloud)
	assert_float(cloud.center.distance_to(Vector2(100, 100 + launcher.throw_tiles * 16.0))).is_less(0.001)
	assert_str(TtwSpecialSystem.smoke(world.session, hippy, Vector2(100, 120))).starts_with("Smoke is not ready")
	# Both at the speed they hold: the one in the smoke at its share of the
	# other's, which it keeps while inside.
	world.session.body_of(inside).position = cloud.center - Vector2(cloud.radius_px * 0.8, 0)
	var top := (outside.get_component(TtwDrive) as TtwDrive).max_speed_tiles * 16.0
	for truck in [inside, outside]:
		(truck.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	(inside.get_component(TtwDrive) as TtwDrive).speed = top * launcher.slow
	(outside.get_component(TtwDrive) as TtwDrive).speed = top
	var start_in := world.session.body_of(inside).position.x
	var start_out := world.session.body_of(outside).position.x
	var start_cloud := cloud.center
	await _ticks(30)
	var went_in := world.session.body_of(inside).position.x - start_in
	var went_out := world.session.body_of(outside).position.x - start_out
	assert_float(went_in / went_out).is_equal_approx(launcher.slow, 0.001)
	assert_float(cloud.center.x).is_greater(start_cloud.x)
	# Gone in its time.
	await _ticks(ceili(launcher.seconds * 60.0) - 30)
	assert_int(world.session.view([TtwSmokeCloud]).size()).is_equal(0)

func test_guns_cannot_pick_out_a_target_in_smoke_beyond_a_few_tiles() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(100, 250))
	var gun: TtwGun = tank.get_component(TtwGun)
	var hippy := world.spawn(&"hippy", Vector2(200, 250), 0.0, 2)
	var guns: TtwGunSystem = world.session.system(&"guns")
	assert_object(guns.pick(tank, gun, Vector2(100, 250))).is_same(hippy)
	await _ticks(1)
	TtwSpecialSystem.smoke(world.session, hippy, Vector2(200, 250))
	assert_object(guns.pick(tank, gun, Vector2(100, 250))).is_null()
	# Close enough, it is seen through the smoke.
	var sight := TtwGunSystem.SMOKE_SIGHT_TILES * 16.0
	world.session.body_of(tank).position = Vector2(200 - sight, 250)
	assert_object(guns.pick(tank, gun, Vector2(200 - sight, 250))).is_same(hippy)

func test_a_nurse_heals_its_sides_ground_vehicles_near_it_not_helicopters() -> void:
	_world()
	var nurse := world.spawn(&"nurse", Vector2(200, 200))
	var m: TtwMedic = nurse.get_component(TtwMedic)
	var reach := m.reach_tiles * 16.0
	var tank := world.spawn(&"tank", Vector2(200 + reach, 200))
	(tank.get_component(TtwGun) as TtwGun).ready_tick = 1 << 30 # no shooting here
	var far := world.spawn(&"truck", Vector2(200, 200 + reach + 1.0))
	var enemy := world.spawn(&"truck", Vector2(200 - reach, 200), 0.0, 2)
	var heli := world.spawn(&"helicopter", Vector2(200, 200 - reach * 0.5))
	for unit in [tank, far, enemy, heli]:
		(unit.get_component(TtwCondition) as TtwCondition).health = 20.0
	var services := 6
	await _ticks(TtwSpecialSystem.SERVICE_TICKS * services)
	var healed := m.rate * TtwSpecialSystem.SERVICE_TICKS / 60.0 * services
	assert_float((tank.get_component(TtwCondition) as TtwCondition).current()).is_equal_approx(20.0 + healed, 0.001)
	for unit in [far, enemy, heli]:
		assert_float((unit.get_component(TtwCondition) as TtwCondition).current()).is_equal(20.0)
