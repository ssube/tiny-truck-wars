extends GdUnitTestSuite
## Tanks shoot: the nearest enemy in range, never past it; ballistic shells
## that lead a moving target (and miss it when leading is off), stopped short
## by a ridge or a tall building on the way; an attack order closes in, stops
## in range and fires until the target is gone.

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

func _world(material: int = TtwMaterials.PAVEMENT, tiles: Vector2i = Vector2i(48, 32)) -> void:
	world = Fixture.make(self, Fixture.flat(tiles, material))

func _guns() -> TtwGunSystem:
	return world.session.system(&"guns")

func _ballistics() -> TtwBallisticsSystem:
	return world.session.system(&"ballistics")

func _gun(tank: Entity) -> TtwGun:
	return tank.get_component(TtwGun)

func test_a_tank_picks_the_nearest_enemy_in_range_and_nothing_past_it() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(100, 250))
	var gun := _gun(tank)
	var reach := gun.range_px()
	world.spawn(&"truck", Vector2(130, 250)) # own side
	var far := world.spawn(&"truck", Vector2(100 + reach + 0.5, 250), 0.0, 2)
	assert_object(_guns().pick(tank, gun, Vector2(100, 250))).is_null()
	var edge := world.spawn(&"truck", Vector2(100, 250 + reach), 0.0, 2)
	assert_object(_guns().pick(tank, gun, Vector2(100, 250))).is_same(edge)
	# A unit comes before a structure, even a nearer one.
	world.structure(&"garage", Vector2(160, 250), 2)
	assert_object(_guns().pick(tank, gun, Vector2(100, 250))).is_same(edge)
	assert_bool(is_instance_valid(far)).is_true()

func _crossing(lead: bool) -> float:
	_world()
	var tank := world.spawn(&"tank", Vector2(100, 400))
	_gun(tank).ready_tick = 1 << 30 # fired by hand
	var truck := world.spawn(&"truck", Vector2(80, 270), 0.0, 2)
	var d: TtwDrive = truck.get_component(TtwDrive)
	d.speed = d.max_speed_tiles * TtwTerrain.tile_px()
	d.throttle = 1.0
	_guns().leading = lead
	var landed := UI.observe(_ballistics().burst)
	await _ticks(1)
	_guns().fire(tank, truck)
	var shell_ticks := TtwCombat.flight_ticks(_gun(tank), Vector2(100, 400), Vector2(80, 270))
	var result: Dictionary = await landed.wait(get_tree(), (shell_ticks + 30) / 60.0)
	assert_bool(result.received).is_true()
	var at: Vector2 = result.value[1]
	return at.distance_to(world.session.body_of(truck).position)

func test_a_shell_meets_a_moving_target_it_leads() -> void:
	var miss := await _crossing(true)
	assert_float(miss).is_less(2.0)

func test_without_leading_the_shell_lands_behind_a_moving_target() -> void:
	var miss := await _crossing(false)
	assert_float(miss).is_greater(24.0)

func test_a_ridge_between_stops_the_shell_short() -> void:
	_world()
	for y in 32:
		for x in range(14, 16):
			world.terrain.set_elevation(Vector2i(x, y), 80.0)
	var tank := world.spawn(&"tank", Vector2(150, 250))
	_gun(tank).ready_tick = 1 << 30
	var target := world.spawn(&"truck", Vector2(290, 250), 0.0, 2)
	var c: TtwCondition = target.get_component(TtwCondition)
	var landed := UI.observe(_ballistics().burst)
	await _ticks(1)
	_guns().fire(tank, target)
	var result: Dictionary = await landed.wait(get_tree(), 3.0)
	assert_bool(result.received).is_true()
	var at: Vector2 = result.value[1]
	assert_str(String(result.value[2])).is_equal("ground")
	assert_float(at.x).is_less(16.0 * 16.0)
	assert_float(c.current()).is_equal(c.max_health)

func test_a_tall_building_near_the_target_takes_the_shell_and_a_low_pad_does_not() -> void:
	_world()
	var tank := world.spawn(&"tank", Vector2(60, 250))
	_gun(tank).ready_tick = 1 << 30
	var target := world.spawn(&"truck", Vector2(262, 250), 0.0, 2)
	# The shot comes down over the last tenth of its way: a garage there is in it.
	var garage := world.structure(&"garage", Vector2(230, 250), 2)
	var h: TtwHealth = garage.get_component(TtwHealth)
	var landed := UI.observe(_ballistics().burst)
	await _ticks(1)
	_guns().fire(tank, target)
	var result: Dictionary = await landed.wait(get_tree(), 3.0)
	assert_str(String(result.value[2])).is_equal("obstacle")
	assert_float(h.current()).is_less(h.max_health)
	# A helipad is too low to be in the way.
	world.session.retire(garage)
	world.structure(&"helipad", Vector2(230, 250), 2)
	landed = UI.observe(_ballistics().burst)
	await _ticks(1)
	_guns().fire(tank, target)
	result = await landed.wait(get_tree(), 3.0)
	assert_str(String(result.value[2])).is_equal("ground")
	assert_float((result.value[1] as Vector2).distance_to(world.session.body_of(target).position)).is_less(1.0)

func test_an_attack_order_closes_in_stops_in_range_and_fires_until_the_target_is_gone() -> void:
	_world(TtwMaterials.PAVEMENT, Vector2i(64, 24))
	var tank := world.spawn(&"tank", Vector2(60, 190))
	var target := world.spawn(&"truck", Vector2(60 + 15 * 16, 190), 0.0, 2)
	await _ticks(1) # the path grid
	TtwGunSystem.attack(world.session, tank, target)
	assert_bool(tank.has_component(TtwMoveOrder)).is_true()
	var gun := _gun(tank)
	var wrecked := UI.observe((world.session.system(&"drive") as TtwDriveSystem).destroyed)
	# Six tiles to close at the tank's speed (plus getting going), then the
	# shots that the truck's health takes, each a reload apart.
	var c: TtwCondition = target.get_component(TtwCondition)
	var shots := ceili(c.max_health / gun.damage)
	var seconds := 6.0 / 3.0 + 2.0 + shots * gun.reload_seconds + 2.0
	var result: Dictionary = await wrecked.wait(get_tree(), seconds)
	assert_bool(result.received).is_true()
	assert_object(result.value).is_same(target)
	var gap := world.session.body_of(tank).position.distance_to(world.session.body_of(target).position)
	assert_float(gap).is_less_equal(gun.range_px())
	assert_float(gap).is_greater(gun.range_px() - 2.0 * 16.0)
	await _ticks(1)
	assert_object(world.session.linked(tank, TtwAttacking)).is_null()
