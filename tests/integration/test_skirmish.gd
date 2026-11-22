extends GdUnitTestSuite
## The skirmish as the player meets it: two bases and neutral depots, ground
## routes that cross the river only at the fords, and the commander and HUD
## doing what their buttons and clicks say.

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
	await _ticks(1) # the path grid is made on the first tick

func _own(kind: StringName, team: int = 1) -> Array:
	return game.session.view([TtwVehicle, TtwTeam]).filter(func(e): return TtwTeam.of(e) == team and TtwUnits.kind_of(e) == kind)

func test_each_side_starts_with_a_base_and_the_middle_has_depots_to_take() -> void:
	await _start()
	for team in [1, 2]:
		var garages := game.session.view([TtwGarage, TtwTeam]).filter(func(e): return TtwTeam.of(e) == team)
		var depots := game.session.view([TtwDepot, TtwTeam]).filter(func(e): return TtwTeam.of(e) == team)
		assert_int(garages.size()).is_equal(1)
		assert_int(depots.size()).is_equal(2)
		assert_int(_own(&"tank", team).size()).is_equal(2)
		assert_int(_own(&"wrecker", team).size()).is_equal(1)
		assert_int(_own(&"engineer", team).size()).is_equal(1)
	var neutral := game.session.view([TtwDepot, TtwTeam]).filter(func(e): return TtwTeam.of(e) == TtwTeam.NEUTRAL)
	assert_int(neutral.size()).is_equal(4)
	assert_bool(game.session.resolve(TtwGame.MAP_ALIAS).has_component(TtwMatch)).is_true()

func test_the_way_between_the_bases_crosses_the_river_only_at_a_ford() -> void:
	await _start()
	var grid := TtwGround.paths_of(game.session)
	var tile := TtwTerrain.tile_px()
	var from := Vector2(14, 28) * tile
	var route := grid.find(from, Vector2(82, 28) * tile)
	assert_bool(route.is_empty()).is_false()
	var at := from
	for p in route:
		for k in 33:
			var t := game.terrain.tile_of(at.lerp(p, k / 32.0))
			if t.x >= TtwSkirmishMap.CHANNEL.x and t.x < TtwSkirmishMap.CHANNEL.y:
				var at_ford := TtwSkirmishMap.FORDS.any(func(y): return absi(t.y - y) <= 2)
				assert_bool(at_ford).override_failure_message("crossed the river at %s" % t).is_true()
		at = p

func test_a_drag_selects_own_units_and_a_right_click_sends_them() -> void:
	await _start()
	var c := game.commander
	c.select_rect(Rect2(Vector2.ZERO, game.terrain.size_px()))
	assert_int(c.selected.size()).is_equal(4)
	assert_bool(c.selected.all(func(e): return TtwTeam.of(e) == 1)).is_true()
	c.order_at(Vector2(30, 28) * TtwTerrain.tile_px())
	assert_bool(c.selected.all(func(e): return e.has_component(TtwMoveOrder))).is_true()

func test_a_selected_wrecker_winches_a_stuck_tank_it_is_sent_to() -> void:
	await _start()
	var c := game.commander
	var truck: Entity = _own(&"wrecker")[0]
	var tank: Entity = _own(&"tank")[0]
	game.session.body_of(tank).position = game.session.body_of(truck).position + Vector2(40, 0)
	tank.add_component(TtwStuck.new())
	c.select_at(game.session.body_of(truck).position)
	assert_array(c.selected).is_equal([truck])
	c.order_at(game.session.body_of(tank).position)
	assert_object(game.session.linked(truck, TtwWinching)).is_same(tank)

func test_the_garage_buttons_queue_units_and_a_helipad_far_from_depots_is_refused() -> void:
	await _start()
	var c := game.commander
	var garage: Entity = game.session.view([TtwGarage, TtwTeam]).filter(func(e): return TtwTeam.of(e) == 1)[0]
	c.select_at(game.session.body_of(garage).position)
	assert_object(c.selected_structure()).is_same(garage)
	assert_bool(UI.press(game.hud, "make_tank")).is_true()
	assert_array((garage.get_component(TtwBuildQueue) as TtwBuildQueue).queue).is_equal([&"tank"])
	assert_bool(UI.press(game.hud, "build_helipad")).is_true()
	assert_str(String(c.placing)).is_equal("helipad")
	var refused := UI.observe(c.rejected)
	assert_object(c.place(Vector2(24, 10) * TtwTerrain.tile_px())).is_null()
	assert_bool(refused.received).is_true()
	assert_str(refused.value).starts_with("A helipad needs a fuel depot")
	# Beside the base's depots it is built, paid for and supplied.
	var site := game.session.body_of(garage).position + Vector2(80, 80)
	var built := c.place(site)
	assert_object(built).is_not_null()
	assert_object(game.session.linked(built, TtwSuppliedBy)).is_not_null()

func _key(code: Key) -> void:
	var press := InputEventKey.new()
	press.keycode = code
	press.physical_keycode = code
	press.pressed = true
	game.commander._unhandled_input(press)

func test_r_sets_the_selected_engineer_laying_road_and_f_throws_the_hippys_smoke() -> void:
	await _start()
	var c := game.commander
	var engineer: Entity = _own(&"engineer")[0]
	c.select_at(game.session.body_of(engineer).position)
	_key(KEY_R)
	assert_bool((engineer.get_component(TtwEngineer) as TtwEngineer).paving).is_true()
	_key(KEY_R)
	assert_bool((engineer.get_component(TtwEngineer) as TtwEngineer).paving).is_false()
	var hippy := game.spawn_unit(&"hippy", Vector2(20, 40) * TtwTerrain.tile_px(), 0.0, 1)
	c.select_at(game.session.body_of(hippy).position)
	var smoked := UI.observe((game.session.system(&"specials") as TtwSpecialSystem).smoked)
	_key(KEY_F)
	assert_bool(smoked.received).is_true()

func test_a_selected_garage_destroyed_leaves_the_selection_and_the_hud_quietly() -> void:
	await _start()
	var c := game.commander
	var garage: Entity = game.session.view([TtwGarage, TtwTeam]).filter(func(e): return TtwTeam.of(e) == 1)[0]
	var tank: Entity = _own(&"tank")[0]
	c.select_at(game.session.body_of(garage).position)
	c.selected.append(tank)
	var over := UI.observe((game.session.system(&"match") as TtwMatchSystem).match_over)
	TtwDamage.hurt(game.session, garage, 1.0e6, Vector2.ZERO)
	# Frames, not ticks: the HUD and the commander draw from the selection
	# every frame while the garage is freed (run-tests fails on any script error).
	for k in 5:
		await get_tree().process_frame
	assert_bool(over.received).is_true()
	assert_int(over.value).is_equal(2)
	assert_bool(c.selected.has(tank)).is_true()
	assert_int(c.selected.size()).is_equal(1)
	assert_object(c.selected_structure()).is_null()
