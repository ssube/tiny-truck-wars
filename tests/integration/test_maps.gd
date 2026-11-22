extends GdUnitTestSuite
## Every skirmish map: two mirrored bases with the same start, neutral depots
## to take, a ground route between the bases, and its own character: the
## snowfield's cover, cold and lake that routes go round; the dunes' rock
## ridges, open only at the gaps, its heat and wind.

const Simulation := preload("res://tests/support/simulation.gd")

var game: TtwSkirmish

func after_test() -> void:
	if game != null:
		game.queue_free()
		game = null

func _ticks(count: int) -> void:
	var result: Dictionary = await Simulation.physics_ticks(get_tree(), count, count / 60.0 + 1.0)
	assert_bool(result.success).is_true()

func _start(map: StringName) -> void:
	game = (load("res://main.tscn") as PackedScene).instantiate()
	game.map_name = map
	game.ai_teams = []
	add_child(game)
	await _ticks(1) # the path grid

func _side(part: Script, team: int) -> Array:
	return game.session.view([part, TtwTeam]).filter(func(e): return TtwTeam.of(e) == team)

func _base(team: int) -> Vector2:
	return game.session.body_of(_side(TtwGarage, team)[0]).position

## Where a side's first tank starts: open ground by its base.
func _start_of(team: int) -> Vector2:
	return _base(team) + Vector2(5.0 if team == 1 else -5.0, 2.0) * 16.0

## The tiles a route from `from` passes over.
func _route_tiles(from: Vector2, to: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at := from
	for p in TtwGround.paths_of(game.session).find(from, to):
		for k in 33:
			out.append(game.terrain.tile_of(at.lerp(p, k / 32.0)))
		at = p
	return out

func _fair_and_connected(map: StringName) -> void:
	await _start(map)
	var t := game.terrain
	for team in [1, 2]:
		assert_int(_side(TtwGarage, team).size()).is_equal(1)
		assert_int(_side(TtwDepot, team).size()).is_equal(2)
		assert_int(_side(TtwUnit, team).size()).is_equal(4)
		assert_int(_side(TtwEngineer, team).size()).is_equal(1)
	assert_int(_side(TtwDepot, TtwTeam.NEUTRAL).size()).is_greater_equal(2)
	# Mirrored: the same ground either side of the middle.
	for y in t.size_tiles.y:
		for x in t.size_tiles.x / 2:
			var other := Vector2i(t.size_tiles.x - 1 - x, y)
			assert_int(t.material_at_tile(Vector2i(x, y))).override_failure_message("%s: %s" % [map, Vector2i(x, y)]).is_equal(t.material_at_tile(other))
	assert_float(_base(1).x + _base(2).x).is_equal_approx(t.size_px().x, 0.01)
	# A ground route from one base to the other (where its tanks start).
	var from := _start_of(1)
	var to := _start_of(2)
	var route := TtwGround.paths_of(game.session).find(from, to)
	assert_bool(route.is_empty()).is_false()
	assert_float(route[route.size() - 1].distance_to(to)).is_less(1.0)

func test_the_river_map_is_fair_and_connected() -> void:
	await _fair_and_connected(&"river")

func test_the_snowfield_is_fair_and_connected() -> void:
	await _fair_and_connected(&"snowfield")

func test_the_dunes_are_fair_and_connected() -> void:
	await _fair_and_connected(&"dunes")

func test_the_snowfield_is_cold_snowed_over_and_its_lake_is_gone_round() -> void:
	await _start(&"snowfield")
	var w: TtwWeather = game.session.resolve("map").get_component(TtwWeather)
	assert_float(w.temperature).is_less(0.0)
	assert_float(TtwSnowSystem.thaw_rate(w)).is_equal(0.0)
	assert_float(TtwSnow.depth(game.terrain, _base(1) + Vector2(10, 0) * 16.0)).is_greater(1.0)
	var lake := TtwSnowfieldMap.LAKE_X
	for tile in _route_tiles(_start_of(1), _start_of(2)):
		if absi(tile.x - lake) <= 2:
			assert_bool(tile.y < TtwSnowfieldMap.LAKE_ROWS.x or tile.y >= TtwSnowfieldMap.LAKE_ROWS.y).override_failure_message("crossed the lake at %s" % tile).is_true()

func test_the_dunes_are_hot_windy_and_crossed_only_at_the_gaps() -> void:
	await _start(&"dunes")
	var w: TtwWeather = game.session.resolve("map").get_component(TtwWeather)
	assert_float(w.temperature).is_greater(25.0)
	assert_float(w.wind.length()).is_greater(TtwFx.SAND_DUST_WIND)
	for tile in _route_tiles(_start_of(1), _start_of(2)):
		for ridge in TtwDunesMap.RIDGE_X:
			if absi(tile.x - ridge) <= 1:
				assert_bool(TtwDunesMap.GAPS.any(func(g): return absi(tile.y - g) <= 2)).override_failure_message("over the ridge at %s" % tile).is_true()

func _clear_of_roads(map: StringName) -> void:
	await _start(map)
	var roads: Dictionary = TtwMaps.MAPS[map].road_tiles()
	assert_bool(roads.is_empty()).is_false()
	var tile := TtwTerrain.tile_px()
	for e in game.session.view([TtwObstacle, KitBody]):
		if TtwTeam.of(e) != TtwTeam.NEUTRAL and e.has_component(TtwStructure):
			continue
		var o: TtwObstacle = e.get_component(TtwObstacle)
		var half := (o.half_extents if o.shape == TtwObstacle.Shape.BOX else Vector2(o.radius, o.radius)) + Vector2.ONE * TtwPathGrid.OBSTACLE_GROW
		var at := game.session.body_of(e).position + o.offset
		var lo := Vector2i(((at - half) / tile).floor())
		var hi := Vector2i(((at + half) / tile).floor())
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				assert_bool(roads.has(Vector2i(x, y))).override_failure_message("%s: %s stands on the road at %s" % [map, e.alias, Vector2i(x, y)]).is_false()

func test_nothing_stands_on_the_rivers_roads() -> void:
	await _clear_of_roads(&"river")

func test_nothing_stands_on_the_snowfields_roads() -> void:
	await _clear_of_roads(&"snowfield")

func test_nothing_stands_on_the_dunes_tracks() -> void:
	await _clear_of_roads(&"dunes")
