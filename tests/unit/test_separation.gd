extends GdUnitTestSuite
## Ground vehicles keep out of each other: overlapping ones are parted to
## their two radii, tanks driven at each other stop against each other, a
## vehicle that cannot move holds its ground, a group sent to one spot
## settles round it without overlapping, and aircraft and a rope's two ends
## are left be.

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

func _world() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(48, 32), TtwMaterials.PAVEMENT))

func _at(entity: Entity) -> Vector2:
	return world.session.body_of(entity).position

func _r(entity: Entity) -> float:
	return TtwSeparationSystem.radius_of(entity.get_component(TtwVehicle))

func _quiet(tank: Entity) -> void:
	var gun: TtwGun = tank.get_component(TtwGun)
	if gun != null:
		gun.ready_tick = 1 << 30

func test_two_on_one_spot_are_parted_to_their_two_radii_in_a_tick() -> void:
	_world()
	var a := world.spawn(&"tank", Vector2(200, 200))
	var b := world.spawn(&"tank", Vector2(205, 200))
	_quiet(a)
	_quiet(b)
	await _ticks(1)
	assert_float(_at(a).distance_to(_at(b))).is_equal_approx(_r(a) + _r(b), 0.01)
	# Two of a class each moved half the overlap, along the line between them.
	assert_float(_at(a).x).is_less(200.0)
	assert_float(_at(b).x).is_greater(205.0)
	# A truck on a tank's spot gives way the whole overlap.
	var tank := world.spawn(&"tank", Vector2(200, 400))
	_quiet(tank)
	var truck := world.spawn(&"truck", Vector2(205, 400))
	await _ticks(1)
	assert_vector(_at(tank)).is_equal(Vector2(200, 400))
	assert_float(_at(tank).distance_to(_at(truck))).is_equal_approx(_r(tank) + _r(truck), 0.01)

func test_tanks_driven_at_each_other_stop_against_each_other() -> void:
	_world()
	var a := world.spawn(&"tank", Vector2(150, 250), 0.0)
	var b := world.spawn(&"tank", Vector2(300, 250), PI, 2)
	for tank in [a, b]:
		_quiet(tank)
		(tank.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	# 150 px closing at up to 2 × 3 tiles a second: well within 3 s.
	await _ticks(180)
	assert_float(_at(a).x).is_less(_at(b).x)
	assert_float(_at(a).distance_to(_at(b))).is_greater_equal(_r(a) + _r(b) - 0.01)

func test_one_that_cannot_move_holds_its_ground() -> void:
	_world()
	var stuck := world.spawn(&"tank", Vector2(250, 250))
	_quiet(stuck)
	(stuck.get_component(TtwFuel) as TtwFuel).amount = 0.0
	var truck := world.spawn(&"truck", Vector2(180, 252), 0.0)
	(truck.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(90)
	assert_vector(_at(stuck)).is_equal(Vector2(250, 250))
	assert_float(_at(truck).distance_to(_at(stuck))).is_greater_equal(_r(truck) + _r(stuck) - 0.01)

func test_a_group_sent_to_one_spot_settles_round_it_without_overlapping() -> void:
	_world()
	var tanks: Array[Entity] = []
	for k in 4:
		var tank := world.spawn(&"tank", Vector2(100, 120 + k * 60), 0.0)
		_quiet(tank)
		tanks.append(tank)
	await _ticks(1) # the path grid
	var spot := Vector2(400, 210)
	for tank in tanks:
		TtwPilotSystem.order(tank, spot)
	# 300 px at 3 tiles a second, turns, and the jostle at the end.
	await _ticks(600)
	for k in tanks.size():
		assert_bool(tanks[k].has_component(TtwMoveOrder)).override_failure_message("tank %d still going" % k).is_false()
		for j in range(k + 1, tanks.size()):
			assert_float(_at(tanks[k]).distance_to(_at(tanks[j]))).is_greater_equal(_r(tanks[k]) + _r(tanks[j]) - 0.5)
		assert_float(_at(tanks[k]).distance_to(spot)).is_less(TtwPilotSystem.CROWD_RADII * _r(tanks[k]))

func test_aircraft_in_the_air_and_a_winch_cables_two_ends_are_left_be() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(200, 200))
	_quiet(tank)
	world.spawn(&"helicopter", Vector2(202, 200))
	await _ticks(1)
	assert_vector(_at(tank)).is_equal(Vector2(200, 200))
	var wrecker := world.spawn(&"wrecker", Vector2(300, 300))
	var load := world.spawn(&"truck", Vector2(318, 300))
	load.add_component(TtwStuck.new())
	assert_str(TtwWinchSystem.winch(world.session, wrecker, load)).is_empty()
	var before := _at(wrecker)
	await _ticks(1)
	assert_vector(_at(wrecker)).is_equal(before)

## Drives `entity` at full throttle for long enough to cover `px` and more.
func _drive_at(entity: Entity, px: float) -> int:
	var d: TtwDrive = entity.get_component(TtwDrive)
	d.throttle = 1.0
	# Up to speed in a second, then the distance, then a second against it.
	return ceili(px / Kit2D.tiles(d.max_speed_tiles) * 60.0) + 120

func test_a_truck_cannot_push_a_tank_and_a_tank_pushes_a_truck() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(250, 120))
	_quiet(tank)
	var truck := world.spawn(&"truck", Vector2(180, 121), 0.0)
	await _ticks(_drive_at(truck, 70.0))
	assert_vector(_at(tank)).is_equal(Vector2(250, 120))
	assert_float(_at(truck).distance_to(_at(tank))).is_greater_equal(_r(truck) + _r(tank) - 0.01)
	var parked := world.spawn(&"truck", Vector2(250, 300))
	var pusher := world.spawn(&"tank", Vector2(180, 301), 0.0)
	_quiet(pusher)
	await _ticks(_drive_at(pusher, 70.0))
	assert_float(_at(parked).x).is_greater(260.0)

func test_a_car_pushes_nothing_not_even_another_car() -> void:
	_world()
	var parked := world.spawn(&"hippy", Vector2(250, 120))
	var car := world.spawn(&"boss", Vector2(180, 121), 0.0)
	var truck := world.spawn(&"truck", Vector2(250, 300))
	var other := world.spawn(&"nurse", Vector2(180, 301), 0.0)
	var ticks := maxi(_drive_at(car, 70.0), _drive_at(other, 70.0))
	await _ticks(ticks)
	assert_vector(_at(parked)).is_equal(Vector2(250, 120))
	assert_vector(_at(truck)).is_equal(Vector2(250, 300))
	assert_float(_at(car).distance_to(_at(parked))).is_greater_equal(_r(car) + _r(parked) - 0.01)
	assert_float(_at(other).distance_to(_at(truck))).is_greater_equal(_r(other) + _r(truck) - 0.01)

func test_wrecks_and_crashed_helicopters_hold_their_ground() -> void:
	_world()
	var drive := world.session.system(&"drive") as TtwDriveSystem
	var wreck := world.spawn(&"tank", Vector2(250, 120))
	_quiet(wreck)
	drive.wreck(wreck)
	var heli := world.spawn(&"helicopter", Vector2(250, 300))
	drive.wreck(heli)
	assert_bool(TtwCombat.flying(heli)).is_false()
	var a := world.spawn(&"tank", Vector2(180, 121), 0.0)
	var b := world.spawn(&"truck", Vector2(180, 301), 0.0)
	_quiet(a)
	await _ticks(maxi(_drive_at(a, 70.0), _drive_at(b, 70.0)))
	assert_vector(_at(wreck)).is_equal(Vector2(250, 120))
	assert_vector(_at(heli)).is_equal(Vector2(250, 300))
	assert_float(_at(b).distance_to(_at(heli))).is_greater_equal(_r(b) + (heli.get_component(TtwFlight) as TtwFlight).ground_radius_px - 0.01)

func test_a_wrecker_cannot_back_through_the_wreck_it_tows() -> void:
	_world()
	var wreck := world.spawn(&"tank", Vector2(200, 200))
	_quiet(wreck)
	(world.session.system(&"drive") as TtwDriveSystem).wreck(wreck)
	var wrecker := world.spawn(&"wrecker", Vector2(224, 200))
	assert_str(TtwWinchSystem.tow(world.session, wrecker, wreck)).is_empty()
	var d: TtwDrive = wrecker.get_component(TtwDrive)
	d.throttle = -1.0
	await _ticks(120)
	assert_vector(_at(wreck)).is_equal(Vector2(200, 200))
	assert_float(_at(wrecker).x).is_greater(_at(wreck).x)
	assert_float(_at(wrecker).distance_to(_at(wreck))).is_greater_equal(_r(wrecker) + _r(wreck) - 0.01)

func test_vehicles_that_come_and_go_are_parted_like_the_rest() -> void:
	_world()
	var a := world.spawn(&"tank", Vector2(200, 200))
	var b := world.spawn(&"tank", Vector2(400, 200))
	_quiet(a)
	_quiet(b)
	await _ticks(1)
	assert_vector(_at(a)).is_equal(Vector2(200, 200))
	# One that arrives after the others were first looked at is parted too.
	var c := world.spawn(&"truck", Vector2(205, 200))
	await _ticks(1)
	assert_float(_at(a).distance_to(_at(c))).is_equal_approx(_r(a) + _r(c), 0.01)
	# One that is gone pushes nothing.
	world.session.retire(c)
	var before := _at(a)
	await _ticks(1)
	assert_vector(_at(a)).is_equal(before)
	# A body out of the tree is not there to push or be pushed; back in, it is.
	var body := world.session.body_of(b)
	world.units.remove_child(body)
	body.position = before + Vector2(4, 0)
	await _ticks(1)
	assert_vector(_at(a)).is_equal(before)
	assert_vector(body.position).is_equal(before + Vector2(4, 0))
	world.units.add_child(body)
	await _ticks(1)
	assert_float(_at(a).distance_to(_at(b))).is_equal_approx(_r(a) + _r(b), 0.01)
