extends GdUnitTestSuite
## Saving and loading a skirmish: a game loaded from a save is the game that
## was saved (the ground, the water, every entity and its fields and links,
## shots in flight, the opponent, the tick) and plays on from there; the
## menu stops the game, and starts a new one on any map.

const Simulation := preload("res://tests/support/simulation.gd")
const UI := preload("res://tests/support/ui.gd")
const PATH := "user://saves/test.ttwsave"

var game: TtwSkirmish

func after_test() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	game = null
	get_tree().paused = false

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0)
	assert_bool(result.success).is_true()

func _start(map: StringName = &"river") -> void:
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.map_name = map
	add_child(game)
	await _ticks(1)

## Entities by alias, each its components' fields and links (TtwSave's view).
func _by_alias(data: Dictionary) -> Dictionary:
	var out := {}
	for record in data.entities:
		out[record.alias] = record
	return out

func test_a_loaded_game_is_the_game_that_was_saved() -> void:
	await _start()
	# Something going on: units sent off, a winch on, a shot in the air,
	# ruts and water poured, a depot drawn on.
	var session := game.session
	var units := session.view([TtwUnit, TtwTeam]).filter(func(e): return TtwTeam.of(e) == 1)
	for unit in units:
		if unit.has_component(TtwDrive):
			TtwPilotSystem.order(unit, Vector2(24, 24) * 16.0)
	var wrecker: Entity = session.view([TtwWinch])[0]
	var tank: Entity = units.filter(func(u): return TtwUnits.kind_of(u) == &"tank")[0]
	(tank.get_component(TtwFuel) as TtwFuel).amount = 0.0
	TtwPilotSystem.stop(tank)
	session.body_of(tank).position = session.body_of(wrecker).position + Vector2(50, 0)
	await _ticks(90)
	TtwWinchSystem.winch(session, wrecker, tank)
	var enemy: Entity = session.view([TtwGarage, TtwTeam]).filter(func(e): return TtwTeam.of(e) == 2)[0]
	(session.system(&"guns") as TtwGunSystem).fire(tank, enemy)
	game.pour(session.body_of(wrecker).position + Vector2(0, 60), 3.0, 20.0)
	await _ticks(5)
	assert_int(session.view([TtwShell]).size()).is_greater(0)
	assert_str(TtwSave.save(game, PATH)).is_empty()
	var saved := TtwSave.capture(game)
	var wrecker_alias := String(wrecker.alias)
	var tank_alias := String(tank.alias)
	var next := game.restart(game.map_name, PATH)
	game = next
	var loaded := TtwSave.capture(game)
	assert_int(loaded.tick).is_equal(saved.tick)
	for name in TtwSave.LAYERS:
		assert_bool(loaded.terrain.layers[name] == saved.terrain.layers[name]).override_failure_message("layer %s differs" % name).is_true()
	for name in saved.water:
		assert_bool(loaded.water[name] == saved.water[name]).override_failure_message("water %s differs" % name).is_true()
	assert_bool(loaded.fire.heat == saved.fire.heat).is_true()
	var before := _by_alias(saved)
	var after := _by_alias(loaded)
	assert_array(after.keys().map(func(k): return String(k))).contains_exactly_in_any_order(before.keys().map(func(k): return String(k)))
	for alias in before:
		var a: Dictionary = before[alias]
		var b: Dictionary = after[alias]
		assert_bool(a.get("body", {}) == b.get("body", {})).override_failure_message("%s: body %s != %s" % [alias, a.get("body"), b.get("body")]).is_true()
		var parts_a := {}
		for c in a.components:
			parts_a[c.script] = c.fields
		var parts_b := {}
		for c in b.components:
			parts_b[c.script] = c.fields
		assert_array(parts_b.keys()).contains_exactly_in_any_order(parts_a.keys())
		for script in parts_a:
			assert_bool(parts_a[script] == parts_b.get(script)).override_failure_message("%s %s: %s != %s" % [alias, script.get_file(), parts_a[script], parts_b.get(script)]).is_true()
		assert_bool(a.links == b.links).override_failure_message("%s links %s != %s" % [alias, a.links, b.links]).is_true()
	# The winch is still on, and one opponent, not two.
	assert_object(game.session.linked(game.session.resolve(wrecker_alias), TtwWinching)).is_same(game.session.resolve(tank_alias))
	assert_int(game.session.view([TtwAi]).size()).is_equal(1)

func test_a_loaded_game_plays_on() -> void:
	await _start(&"snowfield")
	await _ticks(60)
	assert_str(TtwSave.save(game, PATH)).is_empty()
	var tick := game.session.tick
	game = game.restart(game.map_name, PATH)
	assert_str(String(game.map_name)).is_equal("snowfield")
	await _ticks(120)
	assert_int(game.session.tick).is_equal(tick + 120)
	# The opponent goes on building.
	var garage: Entity = game.session.view([TtwGarage, TtwTeam]).filter(func(e): return TtwTeam.of(e) == 2)[0]
	assert_bool((garage.get_component(TtwBuildQueue) as TtwBuildQueue).queue.is_empty()).is_false()

func test_loading_with_no_save_says_so() -> void:
	await _start()
	var said := UI.observe(game.session.notified)
	assert_object(game.restart(game.map_name, "user://saves/none.ttwsave")).is_null()
	assert_str(said.value).is_equal("There is no saved game.")

func test_the_menu_stops_the_game_and_starts_a_new_one_on_another_map() -> void:
	await _start()
	game.menu.open()
	var tick := game.session.tick
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(game.session.tick).is_equal(tick)
	assert_bool(UI.press(game.menu, "menu_new_dunes")).is_true()
	game = get_children().filter(func(c): return c is TtwSkirmish)[0]
	assert_str(String(game.map_name)).is_equal("dunes")
	assert_bool(get_tree().paused).is_false()
