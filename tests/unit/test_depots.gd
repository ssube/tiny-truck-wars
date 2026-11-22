extends GdUnitTestSuite
## Fuel depots: clustering raises the refill per neighbour inside the reach
## and not past it, up to the cap; they refuel their side within reach; a
## neutral one falls to a side that holds it; destroyed, one goes up after the
## fuse with a blast that grows with its fuel, setting off the depots it
## destroys in turn.

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
	world = Fixture.make(self, Fixture.flat(Vector2i(64, 32), TtwMaterials.GRASS))

## Waits for `depot` to count `count` neighbours (the overlaps the physics
## engine reports).
func _neighbours(depot: Entity, count: int) -> void:
	var body := world.session.body_of(depot) as TtwStructure2D
	if body.neighbours() == count:
		return
	var seen := UI.observe(body.neighbours_changed, func(n): return n == count)
	var result: Dictionary = await seen.wait(get_tree(), 1.0)
	assert_bool(result.received).override_failure_message("never counted %d neighbours" % count).is_true()

func test_each_neighbour_inside_the_reach_raises_the_refill_up_to_the_cap() -> void:
	_world()
	var a := world.structure(&"depot", Vector2(200, 256))
	var d: TtwDepot = a.get_component(TtwDepot)
	var reach := d.cluster_tiles * 16.0
	var depots := world.session.system(&"depots") as TtwDepotSystem
	var alone := depots.refill_rate(a)
	assert_float(alone).is_equal(d.refill)
	# One just past the reach does not count.
	world.structure(&"depot", Vector2(200 + reach + 1.0, 256))
	# One just inside does.
	world.structure(&"depot", Vector2(200, 256 + reach - 1.0))
	await _neighbours(a, 1)
	assert_float(depots.refill_rate(a)).is_equal_approx(alone * (1.0 + d.cluster_bonus), 0.0001)
	# Enough to reach the cap, then one more changes nothing.
	var needed := ceili((d.cluster_cap - 1.0) / d.cluster_bonus)
	for k in needed:
		world.structure(&"depot", Vector2(200 - 20.0 - k * 10.0, 256 - 30.0))
	await _neighbours(a, 1 + needed)
	assert_float(depots.refill_rate(a)).is_equal_approx(alone * d.cluster_cap, 0.0001)
	# An enemy depot alongside is no help.
	world.structure(&"depot", Vector2(200, 256 - 20.0), 2)
	await _ticks(2)
	assert_float(depots.refill_rate(a)).is_equal_approx(alone * d.cluster_cap, 0.0001)

func test_a_depot_refuels_its_side_within_reach_and_not_past_it() -> void:
	_world()
	var depot := world.structure(&"depot", Vector2(200, 256))
	var d: TtwDepot = depot.get_component(TtwDepot)
	var reach := d.refuel_tiles * 16.0
	var near := world.spawn(&"truck", Vector2(200 + reach, 256))
	var far := world.spawn(&"truck", Vector2(200, 256 + reach + 1.0))
	var enemy := world.spawn(&"truck", Vector2(200 - reach, 256), 0.0, 2)
	for e in [near, far, enemy]:
		(e.get_component(TtwFuel) as TtwFuel).amount = 10.0
	await _ticks(TtwDepotSystem.SERVICE_TICKS)
	assert_float((near.get_component(TtwFuel) as TtwFuel).amount).is_greater(10.0)
	assert_float((far.get_component(TtwFuel) as TtwFuel).amount).is_less_equal(10.0)
	assert_float((enemy.get_component(TtwFuel) as TtwFuel).amount).is_less_equal(10.0)

func test_a_neutral_depot_falls_to_the_side_that_holds_it() -> void:
	_world()
	var depot := world.structure(&"depot", Vector2(200, 256), TtwTeam.NEUTRAL)
	world.spawn(&"truck", Vector2(210, 270))
	var taken := UI.observe((world.session.system(&"depots") as TtwDepotSystem).captured)
	var ticks := ceili(TtwDepotSystem.CAPTURE_SECONDS * 60.0 / TtwDepotSystem.SERVICE_TICKS) * TtwDepotSystem.SERVICE_TICKS
	await _ticks(ticks)
	assert_bool(taken.received).is_true()
	assert_int(TtwTeam.of(depot)).is_equal(1)

func test_a_contested_depot_stays_neutral() -> void:
	_world()
	var depot := world.structure(&"depot", Vector2(200, 256), TtwTeam.NEUTRAL)
	world.spawn(&"truck", Vector2(210, 270))
	world.spawn(&"truck", Vector2(190, 270), 0.0, 2)
	await _ticks(ceili(TtwDepotSystem.CAPTURE_SECONDS * 60.0) + TtwDepotSystem.SERVICE_TICKS)
	assert_int(TtwTeam.of(depot)).is_equal(TtwTeam.NEUTRAL)

func test_an_empty_depot_blasts_smaller_than_a_full_one() -> void:
	var empty := TtwDepot.new()
	empty.stock = 0.0
	var full := TtwDepot.new()
	full.stock = full.capacity
	assert_float(TtwDepotSystem.blast_radius_px(empty)).is_less(TtwDepotSystem.blast_radius_px(full))
	assert_float(TtwDepotSystem.blast_damage(empty)).is_less(TtwDepotSystem.blast_damage(full))

func test_a_chain_of_three_goes_up_a_fuse_apart_and_a_survivor_does_not() -> void:
	_world()
	# A full depot's blast kills a depot within `kill` of it; they stand just
	# inside that apart, so each sets off only the next.
	var full := TtwDepot.new()
	full.stock = full.capacity
	var sample: TtwStructure2D = load(TtwPlacement.SCENES[&"depot"]).instantiate()
	var health := sample.health.max_health
	sample.free()
	var kill := TtwDepotSystem.blast_radius_px(full) * (1.0 - health / TtwDepotSystem.blast_damage(full))
	var gap := kill - 1.0
	assert_float(gap).is_greater(40.0) # wider than a depot
	var a := world.structure(&"depot", Vector2(160, 256))
	var b := world.structure(&"depot", Vector2(160 + gap, 256))
	var c := world.structure(&"depot", Vector2(160 + gap * 2.0, 256))
	# Inside C's blast but too tough to die: it never goes up.
	var tough := world.structure(&"depot", Vector2(160 + gap * 3.0, 256))
	(tough.get_component(TtwHealth) as TtwHealth).max_health = 10000.0
	for e in [a, b, c]:
		(e.get_component(TtwDepot) as TtwDepot).stock = (e.get_component(TtwDepot) as TtwDepot).capacity
	var blasts := []
	(world.session.system(&"depots") as TtwDepotSystem).detonated.connect(func(e, _at, _r): blasts.append([e, world.session.tick]))
	await _ticks(1)
	TtwDamage.hurt(world.session, a, 1.0e6, Vector2(100, 256))
	var lit := world.session.tick
	await _ticks(3 * TtwDepotSystem.CHAIN_TICKS + 1)
	assert_int(blasts.size()).is_equal(3)
	assert_array(blasts.map(func(r): return r[0])).is_equal([a, b, c])
	assert_int(blasts[0][1]).is_equal(lit + TtwDepotSystem.CHAIN_TICKS)
	assert_int(blasts[1][1] - blasts[0][1]).is_equal(TtwDepotSystem.CHAIN_TICKS)
	assert_int(blasts[2][1] - blasts[1][1]).is_equal(TtwDepotSystem.CHAIN_TICKS)
	assert_array(world.session.view([TtwDetonating])).is_empty()
	assert_bool((tough.get_component(TtwHealth) as TtwHealth).current() < 10000.0).is_true()
	assert_bool(is_instance_valid(world.session.body_of(tough))).is_true()
