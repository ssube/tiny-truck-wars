extends GdUnitTestSuite
## Getting stuck and getting out: the ground holds a vehicle once resistance
## passes its traction; a wrecker's winch drags it onto firm ground, and its
## tow hitch pulls a wreck along at rope length.

const Fixture := preload("res://tests/support/world.gd")
const Simulation := preload("res://tests/support/simulation.gd")
const UI := preload("res://tests/support/ui.gd")

var world: Fixture.TestWorld

func after_test() -> void:
	if world != null:
		world.queue_free()
		world = null

func _ticks(count: int, on_tick: Callable = Callable()) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0, on_tick)
	assert_bool(result.success).is_true()

## Pavement with a mud bog over tiles [from, to].
func _bog(from: int, to: int) -> TtwTerrain:
	var t := Fixture.flat(Vector2i(24, 8), TtwMaterials.PAVEMENT)
	for y in 8:
		for x in range(from, to + 1):
			t.set_material(Vector2i(x, y), TtwMaterials.MUD)
	return t

func test_stuck_on_the_tick_resistance_passes_traction_and_not_at_it() -> void:
	var t := Fixture.flat(Vector2i(8, 8), TtwMaterials.MUD)
	world = Fixture.make(self, t)
	var at_limit := world.spawn(&"truck", Vector2(40, 40))
	var past_limit := world.spawn(&"truck", Vector2(40, 100))
	var resistance := TtwDriveSystem.resistance_at(t, Vector2(40, 40), 0.0)
	(at_limit.get_component(TtwDrive) as TtwDrive).traction = resistance
	(past_limit.get_component(TtwDrive) as TtwDrive).traction = resistance - 0.001
	for e in [at_limit, past_limit]:
		(e.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	var stuck_on := []
	await _ticks(1, func(): stuck_on.append(past_limit.has_component(TtwStuck)))
	assert_array(stuck_on).is_equal([true])
	assert_bool(at_limit.has_component(TtwStuck)).is_false()

func test_a_stuck_vehicle_neither_moves_nor_turns_under_its_own_power() -> void:
	world = Fixture.make(self, _bog(0, 23))
	var truck := world.spawn(&"truck", Vector2(100, 64))
	var d: TtwDrive = truck.get_component(TtwDrive)
	d.traction = 2.0
	d.throttle = 1.0
	d.steer = 1.0
	await _ticks(60)
	assert_bool(truck.has_component(TtwStuck)).is_true()
	assert_float(world.session.body_of(truck).position.distance_to(Vector2(100, 64))).is_less(0.5)
	assert_float(d.heading).is_equal(0.0)

func test_not_trying_to_drive_is_not_stuck() -> void:
	world = Fixture.make(self, _bog(0, 23))
	var truck := world.spawn(&"truck", Vector2(100, 64))
	(truck.get_component(TtwDrive) as TtwDrive).traction = 2.0
	await _ticks(2)
	assert_bool(truck.has_component(TtwStuck)).is_false()

func test_a_winch_drags_a_stuck_truck_onto_firm_ground_and_lets_go() -> void:
	var t := _bog(4, 8)
	world = Fixture.make(self, t)
	var stuck := world.spawn(&"truck", Vector2(104, 64))
	var wrecker := world.spawn(&"truck", Vector2(176, 64), PI)
	wrecker.add_component(TtwWinch.new())
	var sd: TtwDrive = stuck.get_component(TtwDrive)
	sd.traction = 2.0
	sd.throttle = 1.0
	await _ticks(1)
	assert_bool(stuck.has_component(TtwStuck)).is_true()
	sd.throttle = 0.0 # it stops digging itself in
	(wrecker.get_component(TtwDrive) as TtwDrive).throttle = 1.0 # the winch brakes it
	assert_str(TtwWinchSystem.winch(world.session, wrecker, stuck)).is_empty()
	var released := []
	(world.session.system(&"winch") as TtwWinchSystem).released.connect(func(_w, l): released.append(l))
	# Through mud no stiffer than its force, the pull is at full speed until
	# the truck's centre is on pavement (x = 144).
	var winch: TtwWinch = wrecker.get_component(TtwWinch)
	var pace := winch.pull_tiles * TtwTerrain.tile_px()
	var ticks := ceili((144.0 - 104.0) / pace * 60.0) + 2
	await _ticks(ticks)
	assert_array(released).is_equal([stuck])
	assert_bool(stuck.has_component(TtwStuck)).is_false()
	assert_float(world.session.body_of(stuck).position.x).is_greater_equal(144.0)
	assert_float(world.session.body_of(wrecker).position.distance_to(Vector2(176, 64))).is_less(0.5)
	assert_object(world.session.linked(wrecker, TtwWinching)).is_null()

func test_the_cable_only_reaches_its_range() -> void:
	world = Fixture.make(self, _bog(4, 8))
	var stuck := world.spawn(&"truck", Vector2(104, 64))
	var winch := TtwWinch.new()
	var reach := winch.range_tiles * TtwTerrain.tile_px()
	var near := world.spawn(&"truck", Vector2(104 + reach, 64))
	var far := world.spawn(&"truck", Vector2(104 + reach + 1.0, 100))
	near.add_component(winch)
	far.add_component(TtwWinch.new())
	world.session.body_of(far).position = Vector2(104 + reach + 1.0, 64)
	assert_str(TtwWinchSystem.winch(world.session, near, stuck)).is_empty()
	assert_str(TtwWinchSystem.winch(world.session, far, stuck)).is_equal("Out of reach.")

func test_a_towed_wreck_follows_at_rope_length_and_slows_the_wrecker() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(40, 8), TtwMaterials.PAVEMENT))
	var wreck := world.spawn(&"truck", Vector2(40, 40))
	wreck.add_component(TtwWrecked.new())
	var wrecker := world.spawn(&"truck", Vector2(60, 40))
	wrecker.add_component(TtwWinch.new())
	var free := world.spawn(&"truck", Vector2(60, 100))
	assert_str(TtwWinchSystem.tow(world.session, wrecker, wreck)).is_empty()
	for e in [wrecker, free]:
		(e.get_component(TtwDrive) as TtwDrive).throttle = 1.0
	await _ticks(120)
	var a := world.session.body_of(wrecker).position
	var b := world.session.body_of(wreck).position
	var rope := (wrecker.get_component(TtwWinch) as TtwWinch).tow_tiles * TtwTerrain.tile_px()
	assert_float(a.distance_to(b)).is_equal_approx(rope, 0.01)
	assert_float(b.x).is_less(a.x)
	assert_float(a.x - 60.0).is_less(world.session.body_of(free).position.x - 60.0)

func _pace(wrecker: Entity) -> float:
	return (wrecker.get_component(TtwWinch) as TtwWinch).pull_tiles * TtwTerrain.tile_px()

## Where a wrecker stops hauling itself to a tree at `post`: up against it.
func _against(wrecker: Entity, tree: Entity) -> float:
	return TtwSeparationSystem.radius_of(wrecker.get_component(TtwVehicle)) + 1.0 + (tree.get_component(TtwObstacle) as TtwObstacle).radius

func test_a_wrecker_winches_itself_along_to_a_tree_and_lets_go_against_it() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(24, 8), TtwMaterials.PAVEMENT))
	var wrecker := world.spawn(&"wrecker", Vector2(60, 64), PI * 0.5)
	var tree := world.prop(&"tree_oak", Vector2(124, 64))
	var released := UI.observe((world.session.system(&"winch") as TtwWinchSystem).released)
	assert_str(TtwWinchSystem.anchor(world.session, wrecker, tree)).is_empty()
	# On firm ground at the winch's full pace, from 64 px off to up against it.
	var travel := 64.0 - _against(wrecker, tree)
	await _ticks(ceili(travel / _pace(wrecker) * 60.0) + 2)
	assert_bool(released.received).is_true()
	var at := world.session.body_of(wrecker).position
	assert_float(at.distance_to(Vector2(124, 64))).is_equal_approx(_against(wrecker, tree), 0.5)
	assert_float(at.y).is_equal_approx(64.0, 0.01)
	# It faces the cable, and the tree stands.
	assert_float((wrecker.get_component(TtwDrive) as TtwDrive).heading).is_equal_approx(0.0, 0.001)
	assert_bool((tree.get_component(TtwHealth) as TtwHealth).destroyed).is_false()
	assert_object(world.session.linked(wrecker, TtwWinching)).is_null()

func test_a_stuck_wrecker_winches_itself_out_of_a_bog_to_a_tree() -> void:
	var t := _bog(4, 8)
	world = Fixture.make(self, t)
	var wrecker := world.spawn(&"wrecker", Vector2(104, 64))
	var d: TtwDrive = wrecker.get_component(TtwDrive)
	d.traction = 2.0
	d.throttle = 1.0
	await _ticks(1)
	assert_bool(wrecker.has_component(TtwStuck)).is_true()
	var tree := world.prop(&"tree_pine", Vector2(176, 64))
	assert_str(TtwWinchSystem.anchor(world.session, wrecker, tree)).is_empty()
	# Slowed by the mud it sits in for the whole way, at most.
	var winch: TtwWinch = wrecker.get_component(TtwWinch)
	var effort := maxf(1.0, TtwDriveSystem.resistance_at(t, Vector2(104, 64), 0.0) / winch.force)
	var travel := 72.0 - _against(wrecker, tree)
	await _ticks(ceili(travel / (_pace(wrecker) / effort) * 60.0) + 2)
	assert_object(world.session.linked(wrecker, TtwWinching)).is_null()
	var at := world.session.body_of(wrecker).position
	assert_float(at.x).is_greater_equal(144.0)
	# On pavement it drives away under its own power.
	d.throttle = -1.0
	await _ticks(10)
	assert_bool(wrecker.has_component(TtwStuck)).is_false()
	assert_float(world.session.body_of(wrecker).position.x).is_less(at.x)

func test_the_cable_round_a_tree_needs_reach_and_comes_off_when_it_falls() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(24, 8), TtwMaterials.PAVEMENT))
	var wrecker := world.spawn(&"wrecker", Vector2(40, 64))
	var reach := (wrecker.get_component(TtwWinch) as TtwWinch).range_tiles * TtwTerrain.tile_px()
	var far := world.prop(&"tree_oak", Vector2(40 + reach + 1.0, 64))
	assert_str(TtwWinchSystem.anchor(world.session, wrecker, far)).is_equal("Out of reach.")
	var near := world.prop(&"tree_oak", Vector2(40 + reach - 1.0, 64))
	assert_str(TtwWinchSystem.anchor(world.session, wrecker, near)).is_empty()
	var released := UI.observe((world.session.system(&"winch") as TtwWinchSystem).released)
	TtwDamage.hurt(world.session, near, 1000.0, Vector2(40, 64))
	await _ticks(1)
	assert_bool(released.received).is_true()
	assert_object(world.session.linked(wrecker, TtwWinching)).is_null()
	assert_str(TtwWinchSystem.anchor(world.session, wrecker, near)).is_equal("Nothing to hook.")
