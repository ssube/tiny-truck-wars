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
	var b := world.spawn(&"truck", Vector2(205, 200))
	await _ticks(1)
	assert_float(_at(a).distance_to(_at(b))).is_equal_approx(_r(a) + _r(b), 0.01)
	# Each moved half the overlap, along the line between them.
	assert_float(_at(a).x).is_less(200.0)
	assert_float(_at(b).x).is_greater(205.0)

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

func test_aircraft_and_a_ropes_two_ends_are_left_be() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(200, 200))
	_quiet(tank)
	world.spawn(&"helicopter", Vector2(202, 200))
	await _ticks(1)
	assert_vector(_at(tank)).is_equal(Vector2(200, 200))
	var wrecker := world.spawn(&"wrecker", Vector2(300, 300))
	var wreck := world.spawn(&"truck", Vector2(318, 300))
	wreck.add_component(TtwWrecked.new())
	assert_str(TtwWinchSystem.tow(world.session, wrecker, wreck)).is_empty()
	var before := _at(wrecker)
	await _ticks(1)
	assert_vector(_at(wrecker)).is_equal(before)

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
