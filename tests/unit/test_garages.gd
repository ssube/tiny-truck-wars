extends GdUnitTestSuite
## Garages build from their side's fuel (every depot together, nearest
## first) in the time each unit takes, say why they wait, repair their side (drying flooded engines) and break up wrecks
## for fuel. Helipads need a depot near. A side without garages has lost.

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

func _world() -> void:
	world = Fixture.make(self, Fixture.flat(Vector2i(48, 32), TtwMaterials.GRASS))

func test_a_garage_builds_a_unit_in_its_time_from_its_depots_fuel() -> void:
	_world()
	var garage := world.structure(&"garage", Vector2(200, 200))
	var depot := world.structure(&"depot", Vector2(320, 200))
	var d: TtwDepot = depot.get_component(TtwDepot)
	d.refill = 0.0
	var before := d.level()
	assert_str(TtwGarageSystem.enqueue(garage, &"wrecker")).is_empty()
	var made := []
	(world.session.system(&"garages") as TtwGarageSystem).produced.connect(func(_g, u): made.append([u, world.session.tick]))
	var start := world.session.tick
	var ticks := ceili(TtwProduction.unit_seconds(&"wrecker") * 60.0)
	await _ticks(ticks)
	assert_int(made.size()).is_equal(1)
	assert_int(made[0][1] - start).is_equal(ticks)
	assert_float(d.level()).is_equal_approx(before - TtwProduction.unit_fuel(&"wrecker"), 0.001)
	var unit: Entity = made[0][0]
	assert_int(TtwTeam.of(unit)).is_equal(1)
	assert_str(String((unit.get_component(TtwVehicle) as TtwVehicle).kind)).is_equal("truck")
	# On the truck's chassis, drawn as a wrecker.
	assert_str(world.session.body_of(unit).get("art")).is_equal("wrecker")

## A kit with art of its own is drawn with it, showing the sprite the body
## loaded (each facing's texture); one without keeps its chassis's.
func test_a_kit_with_its_own_art_is_drawn_with_it() -> void:
	_world()
	var wrecker := world.spawn(&"wrecker", Vector2(200, 200))
	var tanker := world.spawn(&"tanker", Vector2(300, 200))
	var body := world.session.body_of(wrecker) as TtwVehicle2D
	assert_str(body.art).is_equal("wrecker")
	assert_str(body.sprite.texture.resource_path).is_equal("res://assets/units/wrecker/east.png")
	assert_str((world.session.body_of(tanker) as TtwVehicle2D).art).is_equal("tanker")
	var engineer := world.spawn(&"engineer", Vector2(400, 200))
	assert_str((world.session.body_of(engineer) as TtwVehicle2D).art).is_equal("truck")
	# Its beacon flashes; the tanker has none; a wreck's goes dark. (Each
	# body's frame update is called here: a physics tick ends before the
	# frame's _process runs.)
	var tanker_body := world.session.body_of(tanker) as TtwVehicle2D
	body._process(0.0)
	tanker_body._process(0.0)
	assert_float(body.sprite.material.get_shader_parameter("beacon")).is_equal(1.0)
	assert_float(tanker_body.sprite.material.get_shader_parameter("beacon")).is_equal(0.0)
	wrecker.add_component(TtwWrecked.new())
	body._process(0.0)
	assert_float(body.sprite.material.get_shader_parameter("beacon")).is_equal(0.0)
	# Changed after it is drawn (a loaded save), the sprite follows.
	body.art = "truck"
	assert_str(body.sprite.texture.resource_path).is_equal("res://assets/units/truck/east.png")

func test_a_garage_says_why_it_waits() -> void:
	_world()
	var garage := world.structure(&"garage", Vector2(500, 300))
	TtwGarageSystem.enqueue(garage, &"tank")
	await _ticks(1)
	assert_str((garage.get_component(TtwBuildQueue) as TtwBuildQueue).status).is_equal("Waiting for fuel (0 of 120).")
	var depot := world.structure(&"depot", Vector2(620, 300))
	var d: TtwDepot = depot.get_component(TtwDepot)
	d.refill = 0.0
	d.stock = 10.0
	await _ticks(1)
	assert_str((garage.get_component(TtwBuildQueue) as TtwBuildQueue).status).is_equal("Waiting for fuel (10 of 120).")
	assert_float(d.level()).is_equal(10.0)
	d.stock = 200.0
	await _ticks(1)
	assert_str((garage.get_component(TtwBuildQueue) as TtwBuildQueue).status).is_empty()
	assert_float(d.level()).is_equal(80.0)

func test_a_garage_builds_from_all_its_sides_depots_nearest_first_however_far() -> void:
	_world()
	var garage := world.structure(&"garage", Vector2(200, 200))
	var reach := TtwGarageSystem.SUPPLY_TILES * 16.0
	var near := world.structure(&"depot", Vector2(300, 200))
	var far := world.structure(&"depot", Vector2(200 + reach * 2.0, 400))
	var enemy := world.structure(&"depot", Vector2(260, 260), 2)
	for depot in [near, far, enemy]:
		(depot.get_component(TtwDepot) as TtwDepot).refill = 0.0
	(near.get_component(TtwDepot) as TtwDepot).stock = 50.0
	(far.get_component(TtwDepot) as TtwDepot).stock = 500.0
	(enemy.get_component(TtwDepot) as TtwDepot).stock = 500.0
	TtwGarageSystem.enqueue(garage, &"tank")
	await _ticks(1)
	# 120: the near one's 50 first, the rest from the far one; never the enemy's.
	assert_float((near.get_component(TtwDepot) as TtwDepot).level()).is_equal(0.0)
	assert_float((far.get_component(TtwDepot) as TtwDepot).level()).is_equal(500.0 - 70.0)
	assert_float((enemy.get_component(TtwDepot) as TtwDepot).level()).is_equal(500.0)
	assert_str((garage.get_component(TtwBuildQueue) as TtwBuildQueue).status).is_empty()

func test_a_garage_repairs_its_side_and_dries_a_flooded_engine() -> void:
	_world()
	var garage := world.structure(&"garage", Vector2(200, 200))
	world.structure(&"depot", Vector2(320, 200))
	var g: TtwGarage = garage.get_component(TtwGarage)
	var truck := world.spawn(&"truck", Vector2(200, 240))
	var enemy := world.spawn(&"truck", Vector2(230, 240), 0.0, 2)
	var c: TtwCondition = truck.get_component(TtwCondition)
	c.health = c.max_health * 0.01
	truck.add_component(TtwFlooded.new())
	var e: TtwCondition = enemy.get_component(TtwCondition)
	e.health = 10.0
	var seconds := (c.max_health * TtwGarageSystem.DRY_SHARE - c.health) / g.repair_rate
	var services := ceili(seconds * 60.0 / TtwGarageSystem.SERVICE_TICKS)
	await _ticks(services * TtwGarageSystem.SERVICE_TICKS)
	assert_bool(truck.has_component(TtwFlooded)).is_false()
	assert_float(c.share()).is_greater_equal(TtwGarageSystem.DRY_SHARE)
	assert_float(e.health).is_equal(10.0)

func test_a_wreck_towed_in_is_broken_up_for_fuel() -> void:
	_world()
	world.structure(&"garage", Vector2(200, 200))
	var depot := world.structure(&"depot", Vector2(320, 200))
	var d: TtwDepot = depot.get_component(TtwDepot)
	d.refill = 0.0
	var before := d.level()
	var wreck := world.spawn(&"tank", Vector2(200, 240))
	wreck.add_component(TtwWrecked.new())
	await _ticks(TtwGarageSystem.SERVICE_TICKS)
	assert_bool(is_instance_valid(wreck) and world.session.body_of(wreck) != null).is_false()
	assert_float(d.level()).is_equal_approx(before + TtwProduction.unit_fuel(&"tank") * TtwProduction.SCRAP_SHARE, 0.001)

func test_a_helipad_needs_a_depot_within_reach() -> void:
	_world()
	await _ticks(1) # the path grid
	var reach := TtwPlacement.helipad_reach() * 16.0
	var half := Vector2(20, 14)
	var site := Vector2(300, 260)
	assert_str(TtwPlacement.check(world.session, &"helipad", site, 1, half, false, false)).is_equal("A helipad needs a fuel depot within %d tiles." % int(TtwPlacement.helipad_reach()))
	var depot := world.structure(&"depot", site + Vector2(reach + 1.0, 0))
	assert_str(TtwPlacement.check(world.session, &"helipad", site, 1, half, false, false)).is_not_empty()
	world.session.body_of(depot).position = site + Vector2(reach, 0)
	assert_str(TtwPlacement.check(world.session, &"helipad", site, 1, half, false, false)).is_empty()
	# An enemy depot does not count.
	assert_str(TtwPlacement.check(world.session, &"helipad", site, 2, half, false, false)).is_not_empty()

func test_placement_wants_clear_ground_and_the_fuel() -> void:
	_world()
	await _ticks(1)
	var depot := world.structure(&"depot", Vector2(120, 120))
	(depot.get_component(TtwDepot) as TtwDepot).refill = 0.0
	(depot.get_component(TtwDepot) as TtwDepot).stock = 50.0
	await _ticks(1)
	assert_str(TtwPlacement.check(world.session, &"garage", Vector2(120, 120), 1, Vector2(22, 14))).is_equal("The ground there is not clear.")
	assert_str(TtwPlacement.check(world.session, &"garage", Vector2(400, 300), 1, Vector2(22, 14))).is_equal("An engineer must be within 5 tiles.")
	# An engineer at the edge of its reach builds; a px further, not.
	var reach := TtwPlacement.engineer_reach() * 16.0
	var engineer := world.spawn(&"engineer", Vector2(400, 300 + reach + 1.0))
	assert_str(TtwPlacement.check(world.session, &"garage", Vector2(400, 300), 1, Vector2(22, 14))).is_equal("An engineer must be within 5 tiles.")
	world.session.body_of(engineer).position = Vector2(400, 300 + reach)
	assert_str(TtwPlacement.check(world.session, &"garage", Vector2(400, 300), 1, Vector2(22, 14))).is_equal("Not enough fuel: it costs 200.")
	# All the side's depots together pay: 50 here and 150 in another.
	var other := world.structure(&"depot", Vector2(600, 400))
	(other.get_component(TtwDepot) as TtwDepot).refill = 0.0
	(other.get_component(TtwDepot) as TtwDepot).stock = 149.0
	assert_str(TtwPlacement.check(world.session, &"garage", Vector2(400, 300), 1, Vector2(22, 14))).is_equal("Not enough fuel: it costs 200.")
	(other.get_component(TtwDepot) as TtwDepot).stock = 150.0
	assert_str(TtwPlacement.check(world.session, &"garage", Vector2(400, 300), 1, Vector2(22, 14))).is_empty()

func test_nothing_may_be_built_in_front_of_a_garages_door() -> void:
	_world()
	await _ticks(1)
	var garage := world.structure(&"garage", Vector2(200, 160))
	world.structure(&"depot", Vector2(400, 160))
	world.spawn(&"engineer", Vector2(300, 260))
	var door := TtwPlacement.door_of(world.session, garage)
	var half := TtwPlacement.footprint(&"depot")
	var in_front := Vector2(200, door.end.y - 4.0 + half.y - half.y)
	assert_str(TtwPlacement.check(world.session, &"depot", Vector2(200, door.position.y + half.y + 8.0), 1, half, false)).is_equal("That would block a garage's door.")
	# Clear of the door (beside it) is fine.
	assert_str(TtwPlacement.check(world.session, &"depot", Vector2(door.end.x + half.x + 24.0, 260), 1, half, false)).is_empty()
	assert_bool(in_front.y > 0.0).is_true()

func test_a_side_without_garages_has_lost() -> void:
	_world()
	world.session.resolve("map").add_component(TtwMatch.new())
	world.structure(&"garage", Vector2(120, 120), 1)
	var theirs := world.structure(&"garage", Vector2(600, 300), 2)
	var over := UI.observe((world.session.system(&"match") as TtwMatchSystem).match_over)
	await _ticks(2)
	assert_bool(over.received).is_false()
	TtwDamage.hurt(world.session, theirs, 1.0e6, Vector2(600, 260))
	await _ticks(1)
	assert_bool(over.received).is_true()
	assert_int(over.value).is_equal(1)
