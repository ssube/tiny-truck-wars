extends GdUnitTestSuite
## Vehicles on the ground: grade, current, ruts, fuel, water wear, flooding
## and stalling. Ticks are counted from the rule each test covers.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")

var world: Fixture.TestWorld

func after_test() -> void:
	if world != null:
		world.queue_free()
		world = null

func _ticks(count: int, on_tick: Callable = Callable()) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0, on_tick)
	assert_bool(result.success).is_true()

func test_uphill_is_slower_and_downhill_faster() -> void:
	assert_float(TtwDriveSystem.slope_factor(0.3, 1.0)).is_less(1.0)
	assert_float(TtwDriveSystem.slope_factor(-0.3, 1.0)).is_greater(1.0)
	# Reversing up the same slope (pointing downhill) is the climb.
	assert_float(TtwDriveSystem.slope_factor(-0.3, -1.0)).is_less(1.0)

func test_driving_along_a_rut_is_easier_than_crossing_it() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.MUD)
	var at := Vector2(64, 64)
	TtwBrushes.paint(t, TtwBrushes.Kind.DIG, at, 6.0, 4.0)
	TtwBrushes.paint(t, TtwBrushes.Kind.TRACK, at, 6.0, 1.0, 0.0)
	var along := TtwDriveSystem.resistance_at(t, at, 0.0)
	var across := TtwDriveSystem.resistance_at(t, at, PI / 2)
	assert_float(along).is_less(across)
	assert_float(along).is_greater(TtwDriveSystem.resistance_at(Fixture.flat(Vector2i(8, 8), TtwMaterials.MUD), at, 0.0))

func test_the_same_ticks_take_a_truck_further_on_pavement_than_on_mud() -> void:
	var t := Fixture.flat(Vector2i(64, 16), TtwMaterials.PAVEMENT)
	for y in range(8, 16):
		for x in 64:
			t.set_material(Vector2i(x, y), TtwMaterials.MUD)
	world = Fixture.make(self, t)
	var road := world.spawn(&"truck", Vector2(40, 64))
	var mud := world.spawn(&"truck", Vector2(40, 192))
	for e in [road, mud]:
		(e.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(120)
	var road_x := world.session.body_of(road).position.x
	var mud_x := world.session.body_of(mud).position.x
	assert_float(road_x).is_greater(mud_x)
	# And mud costs more fuel per px.
	var road_burn: float = (road.get_component(TtwFuel) as TtwFuel).capacity - road.get_component(TtwFuel).amount
	var mud_burn: float = (mud.get_component(TtwFuel) as TtwFuel).capacity - mud.get_component(TtwFuel).amount
	assert_float(mud_burn / (mud_x - 40.0)).is_greater(road_burn / (road_x - 40.0))
	# The mud truck left ruts behind it; the road truck none.
	assert_float(t.relief_at(Vector2(60, 192 - 9))).is_less(0.0)

func test_with_the_current_is_faster_than_against_it() -> void:
	var t := Fixture.flat(Vector2i(64, 16), TtwMaterials.PAVEMENT)
	t.water.fill(3.0)
	t.flow.fill(Vector2(20, 0))
	world = Fixture.make(self, t)
	var down := world.spawn(&"tank", Vector2(400, 64), 0.0)
	var up := world.spawn(&"tank", Vector2(600, 192), PI)
	for e in [down, up]:
		(e.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(60)
	var down_run := world.session.body_of(down).position.x - 400.0
	var up_run := 600.0 - world.session.body_of(up).position.x
	assert_float(down_run).is_greater(up_run)

func test_water_wear_starts_at_the_wading_depth_and_outgrows_the_depth() -> void:
	var v := TtwVehicle.new()
	v.wading_depth_px = 4.0
	var c := TtwCondition.new()
	assert_float(TtwDriveSystem.water_wear(c, v, 4.0)).is_equal(0.0)
	var one := TtwDriveSystem.water_wear(c, v, 5.0)
	var two := TtwDriveSystem.water_wear(c, v, 6.0)
	assert_float(one).is_greater(0.0)
	assert_float(two).is_greater(2.0 * one)

func test_deep_water_floods_the_engine_to_one_percent_without_exploding() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.PAVEMENT)
	t.water.fill(10.0) # the truck floods at 9
	world = Fixture.make(self, t)
	var truck := world.spawn(&"truck", Vector2(128, 128))
	(truck.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(1)
	var condition: TtwCondition = truck.get_component(TtwCondition)
	assert_bool(truck.has_component(TtwFlooded)).is_true()
	assert_float(condition.health).is_equal_approx(condition.max_health * 0.01, 0.0001)
	assert_bool(truck.has_component(TtwWrecked)).is_false()
	assert_float(t.layer_total(TtwTerrain.Layer.SCORCH)).is_equal(0.0)
	var before := world.session.body_of(truck).position
	await _ticks(120)
	assert_bool(TtwDriveSystem.engine_runs(truck)).is_false()
	assert_vector(world.session.body_of(truck).position).is_equal(before)
	assert_float(condition.health).is_equal_approx(condition.max_health * 0.01, 0.0001)

## A tank in still water twice its wading depth: strain 1 per second, so a
## full-health tank stalls on tick 60 exactly.
func _straining_tank() -> Entity:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.PAVEMENT)
	t.water.fill(10.0) # wading 5, flooding 12
	world = Fixture.make(self, t)
	var tank := world.spawn(&"tank", Vector2(64, 128))
	(tank.get_component(TtwCondition) as TtwCondition).water_wear = 0.0
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	return tank

func test_a_strained_engine_stalls_on_the_tick_its_meter_fills() -> void:
	var tank := _straining_tank()
	var stalled_at := [-1]
	var tick := [0]
	await _ticks(61, func():
		tick[0] += 1
		if stalled_at[0] < 0 and tank.has_component(TtwStalled):
			stalled_at[0] = tick[0])
	assert_int(stalled_at[0]).is_equal(60)

func test_a_stalled_engine_restarts_unless_more_than_95_percent_worn() -> void:
	var tank := _straining_tank()
	await _ticks(60)
	assert_bool(tank.has_component(TtwStalled)).is_true()
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 0.0
	await _ticks(TtwDriveSystem.RESTART_TICKS - 1)
	assert_bool(tank.has_component(TtwStalled)).is_true()
	await _ticks(1)
	assert_bool(tank.has_component(TtwStalled)).is_false()
	# Worn past 95%, a stall is for good.
	var condition: TtwCondition = tank.get_component(TtwCondition)
	condition.health = condition.max_health * 0.04
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(60)
	assert_bool(tank.has_component(TtwStalled)).is_true()
	(tank.get_component(TtwDrive) as TtwDrive).throttle = 0.0
	await _ticks(TtwDriveSystem.RESTART_TICKS * 3)
	assert_bool(tank.has_component(TtwStalled)).is_true()

func test_an_empty_tank_does_not_drive() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.PAVEMENT)
	world = Fixture.make(self, t)
	var car := world.spawn(&"hippy", Vector2(64, 128))
	(car.get_component(TtwFuel) as TtwFuel).amount = 0.0
	(car.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(30)
	assert_float(world.session.body_of(car).position.x).is_equal(64.0)

func test_a_vehicle_spinning_in_place_digs_itself_in() -> void:
	var t := Fixture.flat(Vector2i(16, 16), TtwMaterials.MUD)
	world = Fixture.make(self, t)
	var tank := world.spawn(&"tank", Vector2(128, 128))
	var drive: TtwDrive = tank.get_component(TtwDrive)
	drive.traction = 1.0 # mud is too much for it: it spins
	drive.throttle = 1.0
	var contact: Vector2 = (tank.get_component(TtwVehicle) as TtwVehicle).contacts(Vector2(128, 128), 0.0)[0]
	await _ticks(TtwTrackSystem.DIG_EVERY * 6)
	assert_float(world.session.body_of(tank).position.x).is_equal(128.0)
	assert_float(t.relief_at(contact)).is_less(-1.0)
