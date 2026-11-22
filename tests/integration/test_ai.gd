extends GdUnitTestSuite
## The computer opponent on the skirmish: it keeps its garage building, takes
## the nearest neutral depot, winches its stranded units in, builds depots with
## its engineer when it can pay, defends its base, and attacks the player's
## garage once it has a wave of tanks.

const Simulation := preload("res://tests/support/simulation.gd")
const UI := preload("res://tests/support/ui.gd")

var game: TtwSkirmish

func after_test() -> void:
	if game != null:
		game.queue_free()
		game = null

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0)
	assert_bool(result.success).is_true()

func _start() -> void:
	game = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _ticks(1)

func _ai() -> TtwAi:
	return game.session.resolve("ai:2").get_component(TtwAi)

func _own(kind: StringName, team: int = 2) -> Array:
	return game.session.view([TtwUnit, TtwTeam]).filter(func(e): return TtwTeam.of(e) == team and TtwUnits.kind_of(e) == kind)

func _side(part: Script, team: int) -> Array:
	return game.session.view([part, TtwTeam]).filter(func(e): return TtwTeam.of(e) == team)

## Waits for the opponent's next think.
func _think() -> void:
	var thought := UI.observe((game.session.system(&"ai") as TtwAiSystem).thought)
	var result: Dictionary = await thought.wait(get_tree(), (_ai().think_ticks + 1) / 60.0)
	assert_bool(result.received).is_true()

func test_it_keeps_its_garage_building() -> void:
	await _start()
	var garage: Entity = _side(TtwGarage, 2)[0]
	var queue: TtwBuildQueue = garage.get_component(TtwBuildQueue)
	# It starts with an engineer, a wrecker and two tanks: a third tank next.
	assert_array(queue.queue).is_equal([&"tank"])
	assert_array(_side(TtwGarage, 1)[0].get_component(TtwBuildQueue).queue).is_empty()

func test_it_takes_the_nearest_neutral_depot() -> void:
	await _start()
	var captured := UI.observe((game.session.system(&"depots") as TtwDepotSystem).captured, func(v): return v[1] == 2)
	# The nearest is about 30 tiles off over mud: well under a minute's drive
	# for a tank, and five seconds to take it.
	var result: Dictionary = await captured.wait(get_tree(), 60.0)
	assert_bool(result.received).is_true()
	var depot: Entity = result.value[0]
	var home := game.session.body_of(_side(TtwGarage, 2)[0]).position
	for other in game.session.view([TtwDepot, TtwTeam]):
		if TtwTeam.of(other) == TtwTeam.NEUTRAL:
			assert_float(game.session.body_of(other).position.distance_to(home)).is_greater_equal(game.session.body_of(depot).position.distance_to(home))

func test_an_idle_wrecker_winches_its_stranded_tank() -> void:
	await _start()
	var wrecker: Entity = _own(&"wrecker")[0]
	var tank: Entity = _own(&"tank")[0]
	game.session.body_of(tank).position = game.session.body_of(wrecker).position + Vector2(-40, 0)
	# Out of fuel: it cannot move by itself.
	(tank.get_component(TtwFuel) as TtwFuel).amount = 0.0
	await _think()
	assert_object(game.session.linked(wrecker, TtwWinching)).is_same(tank)

func test_its_engineer_builds_a_depot_when_it_can_pay() -> void:
	await _start()
	var before := _side(TtwDepot, 2).size()
	for depot in _side(TtwDepot, 2):
		var d: TtwDepot = depot.get_component(TtwDepot)
		d.stock = d.capacity
	var built := UI.observe(game.session.entity_registered, func(e): return e.has_component(TtwDepot) and TtwTeam.of(e) == 2)
	# A few thinks to pick a site and drive the engineer there (a few tiles).
	var result: Dictionary = await built.wait(get_tree(), 20.0)
	assert_bool(result.received).is_true()
	assert_int(_side(TtwDepot, 2).size()).is_equal(before + 1)
	var engineer: Entity = _own(&"engineer")[0]
	assert_float(game.session.body_of(engineer).position.distance_to(game.session.body_of(result.value).position)).is_less_equal(TtwPlacement.engineer_reach() * 16.0)

func test_it_defends_its_base_against_an_enemy_near_it() -> void:
	await _start()
	var home := game.session.body_of(_side(TtwGarage, 2)[0]).position
	var raider := game.spawn_unit(&"tank", home + Vector2(-8.0 * 16.0, 40.0), 0.0, 1)
	(raider.get_component(TtwGun) as TtwGun).ready_tick = 1 << 30
	await _think()
	var defenders := _own(&"tank").filter(func(t): return game.session.linked(t, TtwAttacking) == raider)
	assert_bool(defenders.is_empty()).is_false()

func test_with_a_wave_of_tanks_it_goes_for_the_players_garage() -> void:
	await _start()
	var ai := _ai()
	var home := game.session.body_of(_side(TtwGarage, 2)[0]).position
	for k in ai.attack_size:
		game.spawn_unit(&"tank", home + Vector2(-5.0 * 16.0, 70.0 + k * 24.0), PI, 2)
	await _think()
	var garage: Entity = _side(TtwGarage, 1)[0]
	assert_bool(ai.attacking).is_true()
	assert_str(ai.target).is_equal(String(garage.alias))
	var wave := _own(&"tank").filter(func(t): return game.session.linked(t, TtwAttacking) == garage)
	assert_int(wave.size()).is_greater_equal(ai.attack_size)
